import 'dart:async';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/symphony_logger.dart';
import '../../../../core/result/result.dart';
import '../../../storage/domain/session_storage.dart';
import '../../domain/adapters/auth_adapter.dart';
import '../../domain/entities/auth_credentials.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Default [AuthRepository]: coordinates the project's [AuthAdapter] (remote)
/// with a [SessionStorage] (local).
///
/// **Session restoration** ([restoreSession]):
///
/// 1. without persisted tokens there is no session;
/// 2. tokens that are expired (or expire within [expiryLeeway]) are refreshed
///    when a refresh token exists, otherwise the session is discarded. If the
///    backend rejects the refresh (`UnauthorizedFailure`, `AuthFailure`,
///    `ForbiddenFailure`, `ValidationFailure`, other 4xx) the session is
///    discarded; if the backend cannot be reached (`NetworkFailure`,
///    `TimeoutFailure`, 5xx) the stored session is kept so offline users stay
///    signed in;
/// 3. the profile is reloaded with [AuthAdapter.fetchCurrentUser]: an
///    `UnauthorizedFailure` or `AuthFailure` discards the session, any other
///    failure falls back to the stored profile;
/// 4. [AuthAdapter.validateSession] applies the project's business rules (a
///    rejection discards the session and is returned as the failure);
/// 5. the session is persisted and becomes [currentSession].
///
/// Restoring while a session is already active (a forced restoration)
/// revalidates that session instead (steps 3 to 5): memory is never older
/// than the storage, and an expired access token is refreshed through
/// [refreshTokens].
///
/// **Token refresh** ([refreshTokens]) is single-flight: concurrent callers
/// share one request (a refresh started for a previous session is never
/// shared with the next one). The previous refresh token is kept when the
/// backend does not rotate it.
///
/// **Sign-in during a restoration**: a sign-in (or registration) never waits
/// for a restoration in progress. The restoration it overtakes reports the
/// session the sign-in settled on, never a session that is still being
/// validated; a sign-in that fails reinstates the previous session, and the
/// restoration it overtook then goes on.
///
/// Storage writes are serialized and every operation checks that the session
/// it works on is still current, so a refresh finishing after a sign-out can
/// never resurrect the session, and [updateSession] never reinstates tokens
/// that a refresh already replaced. Errors are returned as [Result] failures;
/// storage problems surface as [StorageFailure]. Tokens are never logged.
class AuthRepositoryImpl extends AuthRepository {
  /// Creates the repository.
  ///
  /// [clock] is used for expiry checks (handy in tests).
  AuthRepositoryImpl({
    required this.adapter,
    required this.storage,
    SymphonyLogger? logger,
    this.expiryLeeway = const Duration(seconds: 30),
    DateTime Function()? clock,
  })  : _logger = logger,
        _clock = clock ?? DateTime.now;

  /// The project's authentication backend.
  final AuthAdapter adapter;

  /// Where the session is persisted.
  final SessionStorage storage;

  /// Access tokens expiring within this duration are treated as expired when
  /// a session is restored.
  final Duration expiryLeeway;

  final SymphonyLogger? _logger;
  final DateTime Function() _clock;

  AuthSession? _session;

  /// Identifies the current session: takes a new value (never used before)
  /// whenever [_session] is replaced by another session or cleared, and
  /// returns to the previous value when a failed sign-in reinstates the
  /// previous session. Pending operations compare it to detect that their
  /// session is no longer current.
  int _epoch = 0;

  Future<AuthTokens?>? _refreshing;

  /// [_epoch] of the session [_refreshing] refreshes.
  int _refreshingEpoch = 0;

  /// Tokens of the current session replaced by refreshes (most recent
  /// last), so that [updateSession] never reinstates them.
  final List<AuthTokens> _replacedTokens = <AuthTokens>[];

  static const int _maxReplacedTokens = 8;

  /// Source of [_epoch] values, which are never reused.
  int _lastEpoch = 0;

  /// Completes once the sign-in (or registration) being activated settled.
  Future<void>? _activation;

  Future<void> _storageQueue = Future<void>.value();

  @override
  AuthSession? get currentSession => _session;

  @override
  bool get supportsRegistration => adapter.supportsRegistration;

  @override
  bool get supportsPasswordRecovery => adapter.supportsPasswordRecovery;

  @override
  Future<Result<AuthSession?>> restoreSession() =>
      guardResult<AuthSession?>(_restore);

  @override
  Future<Result<AuthSession>> login(AuthCredentials credentials) =>
      guardResult<AuthSession>(
        () async => _activate(await adapter.login(credentials)),
      );

  @override
  Future<void> logout() async {
    final session = _session ?? await _readStoredSession();
    if (session != null) {
      try {
        await adapter.logout(session);
      } on Object catch (error, stackTrace) {
        _logger?.warning(
          'Remote sign-out failed; the local session is cleared anyway.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    await clearSession();
    _logger?.info('Signed out.');
  }

  @override
  Future<AuthTokens?> refreshTokens() {
    final pending = _refreshing;
    if (pending != null && _refreshingEpoch == _epoch) return pending;
    Future<AuthTokens?>? flight;
    flight = _refresh().whenComplete(() {
      if (identical(_refreshing, flight)) _refreshing = null;
    });
    _refreshing = flight;
    _refreshingEpoch = _epoch;
    return flight;
  }

  @override
  Future<void> clearSession() async {
    _setSession(null);
    try {
      await _serialize(() => _guardStorage(storage.clear));
    } on Object catch (error, stackTrace) {
      _logger?.error(
        'Unable to clear the persisted session.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Replaces the active session (see [AuthRepository.updateSession]).
  ///
  /// Tokens that a refresh already replaced (for example those of a session
  /// read before the refresh completed) are never reinstated: the current
  /// tokens are kept and only the user of [session] is applied.
  @override
  Future<Result<void>> updateSession(AuthSession session) =>
      guardResult<void>(() async {
        final active = _session;
        if (active == null) {
          throw const AuthFailure('There is no active session to update.');
        }
        final next = _isReplaced(session.tokens, active.tokens)
            ? AuthSession(tokens: active.tokens, user: session.user)
            : session;
        _session = next;
        await _writeSession(next, replace: next.user == null);
      });

  @override
  Future<Result<AuthSession?>> register(AuthCredentials data) =>
      guardResult<AuthSession?>(() async {
        final session = await adapter.register(data);
        if (session == null) return null;
        return _activate(session);
      });

  @override
  Future<Result<void>> requestPasswordReset(AuthCredentials data) =>
      guardResult<void>(() => adapter.requestPasswordReset(data));

  @override
  Future<Result<void>> confirmPasswordReset(AuthCredentials data) =>
      guardResult<void>(() => adapter.confirmPasswordReset(data));

  // -------------------------------------------------------------------------
  // Restoration
  // -------------------------------------------------------------------------

  Future<AuthSession?> _restore() async {
    final active = _session;
    if (active != null) return _revalidate(active);

    // Every step below checks that no other session (sign-in, sign-out...)
    // replaced the one being restored. A sign-in still being validated is
    // waited for: if it fails, it reinstates this restoration's epoch and
    // the restoration goes on as if nothing happened.
    final startEpoch = _epoch;
    bool superseded() => _epoch != startEpoch;

    final storedTokens = await _guardStorage(storage.readTokens);
    if (superseded()) {
      final settled = await _settledSession();
      if (superseded()) return settled;
    }
    if (storedTokens == null) {
      _logger?.debug('No persisted session.');
      return null;
    }
    final storedUser = await _readStoredUser();
    if (superseded()) {
      final settled = await _settledSession();
      if (superseded()) return settled;
    }

    var tokens = storedTokens;
    if (tokens.isExpired(leeway: expiryLeeway, now: _clock())) {
      if (!tokens.canRefresh) {
        return _discard('The persisted session expired and cannot be '
            'refreshed.');
      }
      try {
        tokens = _mergeTokens(tokens, await adapter.refresh(tokens));
        _logger?.debug('Refreshed the expired access token.');
      } on Failure catch (failure) {
        if (superseded()) {
          final settled = await _settledSession();
          if (superseded()) return settled;
        }
        if (_isRejection(failure)) {
          return _discard('The backend rejected the persisted session.');
        }
        if (!_isTransient(failure)) rethrow;
        _logger?.info('Backend unreachable; keeping the persisted session.');
      }
      if (superseded()) {
        final settled = await _settledSession();
        if (superseded()) return settled;
      }
    }

    // Activate the session provisionally so that authenticated adapter calls
    // (profile, business rules) carry its access token.
    _setSession(AuthSession(tokens: tokens, user: storedUser));
    return _completeRestoration(storedUser);
  }

  /// Restoration of the session that is already active (forced restoration):
  /// memory is at least as fresh as the storage, and an expired access token
  /// is refreshed through the shared [refreshTokens] flight.
  Future<AuthSession?> _revalidate(AuthSession active) async {
    if (active.tokens.isExpired(leeway: expiryLeeway, now: _clock())) {
      final epoch = _epoch;
      await refreshTokens();
      if (_epoch != epoch) {
        final settled = await _settledSession();
        if (_epoch != epoch) return settled;
      }
    }
    return _completeRestoration(active.user);
  }

  /// Reloads the profile, applies the business rules and persists the
  /// active session (steps 3 to 5 of the restoration).
  Future<AuthSession?> _completeRestoration(AuthUser? storedUser) async {
    final activeEpoch = _epoch;
    bool replaced() => _epoch != activeEpoch;

    AuthUser? user;
    try {
      user = await adapter.fetchCurrentUser(_session!) ?? storedUser;
    } on Object catch (error, stackTrace) {
      if (replaced()) {
        final settled = await _settledSession();
        if (replaced()) return settled;
      }
      if (error is UnauthorizedFailure || error is AuthFailure) {
        return _discard('The backend rejected the persisted session.');
      }
      _logger?.warning(
        'Unable to reload the user profile; using the stored one.',
        error: error,
        stackTrace: stackTrace,
      );
      user = storedUser;
    }
    if (replaced()) {
      final settled = await _settledSession();
      if (replaced()) return settled;
    }

    try {
      await adapter.validateSession(
        AuthSession(tokens: _session!.tokens, user: user),
      );
    } on Object {
      if (replaced()) {
        final settled = await _settledSession();
        if (replaced()) return settled;
      }
      await _discard('The session was rejected by the business rules.');
      rethrow;
    }
    if (replaced()) {
      final settled = await _settledSession();
      if (replaced()) return settled;
    }

    // The networking layer may have refreshed the tokens in the meantime:
    // always keep the latest ones.
    final session = AuthSession(tokens: _session!.tokens, user: user);
    _session = session;
    try {
      await _writeSession(session, replace: false);
    } on Object catch (error, stackTrace) {
      // The session is valid: keep the user signed in for this run.
      _logger?.error(
        'Unable to persist the restored session.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _logger?.info('Session restored.');
    return _session;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Validates and persists a brand new session (sign-in, registration) and
  /// makes it current. Restores the previous session on failure.
  ///
  /// The new session is current while it is validated (so that the business
  /// rules can make authenticated calls), but it is not settled: a
  /// restoration superseded meanwhile waits for the outcome. A failure
  /// reinstates the previous session together with its epoch, so that the
  /// operations bound to it (a restoration in progress, a refresh...) go on.
  Future<AuthSession> _activate(AuthSession session) async {
    final previous = _session;
    final previousEpoch = _epoch;
    final previousReplaced = List<AuthTokens>.of(_replacedTokens);
    _setSession(session);
    final epoch = _epoch;
    final settled = Completer<void>();
    _activation = settled.future;
    try {
      await adapter.validateSession(session);
      if (_epoch != epoch) throw const CancelledFailure();
      await _writeSession(session, replace: true);
      if (_epoch != epoch) throw const CancelledFailure();
    } on Object {
      if (_epoch == epoch) {
        _epoch = previousEpoch;
        _session = previous;
        _replacedTokens
          ..clear()
          ..addAll(previousReplaced);
      }
      rethrow;
    } finally {
      if (identical(_activation, settled.future)) _activation = null;
      settled.complete();
    }
    _logger?.info('Signed in.');
    return session;
  }

  Future<AuthTokens?> _refresh() async {
    final session = _session;
    if (session == null || !session.tokens.canRefresh) return null;
    final epoch = _epoch;
    final AuthTokens tokens;
    try {
      tokens = _mergeTokens(
        session.tokens,
        await adapter.refresh(session.tokens),
      );
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Token refresh failed.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
    final current = _session;
    if (epoch != _epoch || current == null) {
      _logger?.debug('The session changed during the refresh; discarded.');
      return null;
    }
    _session = current.copyWith(tokens: tokens);
    _rememberReplaced(session.tokens);
    try {
      await _serialize(() async {
        if (epoch != _epoch) return;
        await _guardStorage(() => storage.writeTokens(tokens));
      });
    } on Object catch (error, stackTrace) {
      _logger?.error(
        'Unable to persist the refreshed tokens.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _logger?.debug('Tokens refreshed.');
    return tokens;
  }

  void _setSession(AuthSession? session) {
    _epoch = ++_lastEpoch;
    _session = session;
    _replacedTokens.clear();
  }

  void _rememberReplaced(AuthTokens tokens) {
    _replacedTokens
      ..remove(tokens)
      ..add(tokens);
    if (_replacedTokens.length > _maxReplacedTokens) {
      _replacedTokens.removeAt(0);
    }
  }

  /// Whether [candidate] are tokens of the current session that a refresh
  /// already replaced by [active].
  bool _isReplaced(AuthTokens candidate, AuthTokens active) =>
      candidate != active && _replacedTokens.contains(candidate);

  /// The current session once no sign-in (or registration) is being
  /// activated any more.
  ///
  /// A restoration superseded by a sign-in reports this session, never the
  /// session of a sign-in that is still being validated (and that is
  /// dropped again when the validation fails).
  Future<AuthSession?> _settledSession() async {
    while (true) {
      final pending = _activation;
      if (pending == null) return _session;
      await pending;
    }
  }

  Future<AuthSession?> _discard(String reason) async {
    _logger?.info(reason);
    await clearSession();
    return null;
  }

  /// Persists [session]. With [replace] the previous session is removed
  /// first, so data of another account can never be mixed in. Skipped when
  /// the session is no longer current once the write starts.
  Future<void> _writeSession(AuthSession session, {required bool replace}) {
    final epoch = _epoch;
    return _serialize(() async {
      if (epoch != _epoch) return;
      if (replace) await _guardStorage(storage.clear);
      await _guardStorage(() => storage.writeTokens(session.tokens));
      final user = session.user;
      if (user != null) {
        await _guardStorage(() => storage.writeUser(user.toJson()));
      }
    });
  }

  Future<AuthUser?> _readStoredUser() async {
    try {
      final json = await storage.readUser();
      return json == null ? null : AuthUser.fromJson(json);
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Ignoring an unreadable stored user profile.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<AuthSession?> _readStoredSession() async {
    try {
      final tokens = await storage.readTokens();
      if (tokens == null) return null;
      return AuthSession(tokens: tokens, user: await _readStoredUser());
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'Unable to read the persisted session.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Runs storage mutations one after another.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _storageQueue.then((_) => operation());
    _storageQueue = result.then<void>((_) {}, onError: (Object error) {});
    return result;
  }

  /// Converts unexpected storage errors into a [StorageFailure].
  Future<T> _guardStorage<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Failure {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw StorageFailure(
        'Unable to access the session storage.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  static AuthTokens _mergeTokens(AuthTokens previous, AuthTokens next) {
    return AuthTokens(
      accessToken: next.accessToken,
      refreshToken: next.canRefresh ? next.refreshToken : previous.refreshToken,
      tokenType: next.tokenType ?? previous.tokenType,
      expiresAt: next.expiresAt,
      extra: <String, Object?>{...previous.extra, ...next.extra},
    );
  }

  /// Whether [failure] means the backend refused the session.
  static bool _isRejection(Failure failure) {
    if (failure is UnauthorizedFailure ||
        failure is AuthFailure ||
        failure is ForbiddenFailure ||
        failure is ValidationFailure) {
      return true;
    }
    final status = failure.statusCode;
    return failure is ServerFailure &&
        status != null &&
        status >= 400 &&
        status < 500;
  }

  /// Whether [failure] means the backend could not be reached.
  static bool _isTransient(Failure failure) {
    if (failure is NetworkFailure || failure is TimeoutFailure) return true;
    final status = failure.statusCode;
    return failure is ServerFailure && (status == null || status >= 500);
  }
}
