import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/auth_state.dart';
import '../../domain/entities/auth_credentials.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../providers/auth_providers.dart';

/// Owns the global [AuthState] and exposes every authentication action.
///
/// Widgets call these methods; they never talk to repositories or adapters
/// directly. Actions never throw: they return a [Result] (or complete
/// normally) and failures are reported through the result or through
/// [AuthUnauthenticated.failure].
///
/// ```dart
/// final controller = ref.read(authControllerProvider.notifier);
/// final result = await controller.login(
///   AuthCredentials.emailPassword(email: email, password: password),
/// );
/// ```
///
/// [build] only returns [AuthState.unknown]; call [restoreSession] once at
/// start-up (the `SymphonySplashScreen` does it for you).
class AuthController extends Notifier<AuthState> {
  Future<void>? _restoring;

  /// Incremented by [build] and by every state change, so that a slow
  /// session restoration never overrides a newer state.
  int _version = 0;

  bool _disposed = false;

  @override
  AuthState build() {
    _version++;
    _restoring = null;
    _disposed = false;
    ref.onDispose(_markDisposed);
    return const AuthState.unknown();
  }

  void _markDisposed() {
    _disposed = true;
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  /// The active session, if any.
  AuthSession? get session => state.session;

  /// Whether the configured adapter supports registration.
  bool get supportsRegistration => _repository.supportsRegistration;

  /// Whether the configured adapter supports password recovery.
  bool get supportsPasswordRecovery => _repository.supportsPasswordRecovery;

  /// Restores the persisted session (idempotent; concurrent calls share one
  /// restoration). Moves the state out of [AuthUnknown].
  ///
  /// Once the state is no longer [AuthUnknown] this is a no-op, unless
  /// [force] is `true`: the persisted session is then restored again (for
  /// example to retry after a failure), or the active session is revalidated
  /// (profile reloaded, business rules applied again). Failures end in
  /// [AuthUnauthenticated] with the failure attached.
  Future<void> restoreSession({bool force = false}) {
    if (_disposed) return Future<void>.value();
    final pending = _restoring;
    if (pending != null) return pending;
    if (!force && state is! AuthUnknown) return Future<void>.value();
    final future = _restore();
    _restoring = future;
    void release() {
      if (identical(_restoring, future)) _restoring = null;
    }

    unawaited(
      future.then<void>((_) => release(), onError: (Object error) => release()),
    );
    return future;
  }

  /// Signs in. On success the state becomes [AuthAuthenticated]; on failure
  /// the state is unchanged and the failure is returned.
  Future<Result<AuthSession>> login(AuthCredentials credentials) async {
    final result = await _run(() => _repository.login(credentials));
    if (result case ResultSuccess<AuthSession>(:final value)) {
      _emit(AuthState.authenticated(value));
    }
    return result;
  }

  /// Signs out. The state always ends as [AuthUnauthenticated].
  Future<void> logout() async {
    try {
      await _repository.logout();
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, 'Sign-out failed');
    }
    _emit(const AuthState.unauthenticated());
  }

  /// Registers an account (when supported by the adapter).
  ///
  /// When the backend signs the new user in, the state becomes
  /// [AuthAuthenticated]; otherwise (for example e-mail verification is
  /// required) the result holds `null` and the state is unchanged.
  Future<Result<AuthSession?>> register(AuthCredentials data) async {
    final result = await _run(() => _repository.register(data));
    if (result case ResultSuccess<AuthSession?>(value: final session?)) {
      _emit(AuthState.authenticated(session));
    }
    return result;
  }

  /// Starts password recovery (when supported by the adapter).
  Future<Result<void>> requestPasswordReset(AuthCredentials data) =>
      _run(() => _repository.requestPasswordReset(data));

  /// Completes password recovery (when supported by the adapter).
  Future<Result<void>> confirmPasswordReset(AuthCredentials data) =>
      _run(() => _repository.confirmPasswordReset(data));

  /// Clears the local session after the server rejected the credentials.
  ///
  /// The state becomes [AuthUnauthenticated] with [failure] (an
  /// [UnauthorizedFailure] by default) as reason. Does not change an already
  /// unauthenticated state.
  Future<void> handleSessionExpired([Failure? failure]) async {
    try {
      await _repository.clearSession();
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, 'Clearing the expired session failed');
    }
    if (_disposed || state is AuthUnauthenticated) return;
    _emit(
      AuthState.unauthenticated(failure: failure ?? const UnauthorizedFailure()),
    );
  }

  /// Replaces the active session (for example after a token refresh or a
  /// profile update) without changing the authentication status.
  ///
  /// Ignored unless the state is [AuthAuthenticated]. The repository is
  /// updated (and the session persisted) when it does not hold [session]
  /// yet.
  void updateSession(AuthSession session) {
    if (_disposed) return;
    final current = state;
    if (current is! AuthAuthenticated || identical(current.session, session)) {
      return;
    }
    _emit(AuthState.authenticated(session));
    unawaited(_syncRepository(session));
  }

  Future<void> _restore() async {
    final version = _version;
    final result = await _run(() => _repository.restoreSession());
    if (_disposed || version != _version) return;
    _emit(
      switch (result) {
        ResultSuccess<AuthSession?>(value: final session?) =>
          AuthState.authenticated(session),
        ResultSuccess<AuthSession?>() => const AuthState.unauthenticated(),
        ResultFailure<AuthSession?>(:final failure) =>
          AuthState.unauthenticated(failure: failure),
      },
    );
  }

  Future<void> _syncRepository(AuthSession session) async {
    try {
      final repository = _repository;
      if (identical(repository.currentSession, session)) return;
      final result = await repository.updateSession(session);
      if (result case ResultFailure<void>(:final failure)) {
        _report(failure, failure.stackTrace, 'Persisting the session failed');
      }
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, 'Persisting the session failed');
    }
  }

  void _emit(AuthState next) {
    if (_disposed) return;
    _version++;
    state = next;
  }

  /// Runs a repository action, converting unexpected errors (for example a
  /// missing adapter configuration) into failures.
  Future<Result<T>> _run<T>(Future<Result<T>> Function() action) async {
    try {
      return await action();
    } on Failure catch (failure) {
      return Result<T>.failure(failure);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, 'Authentication action failed');
      return Result<T>.failure(UnexpectedFailure.fromError(error, stackTrace));
    }
  }

  /// Forwards an unexpected error to the configured `ErrorReporter`.
  void _report(Object error, StackTrace? stackTrace, String reason) {
    if (_disposed) return;
    try {
      final pending = ref
          .read(errorReporterProvider)
          .report(error, stackTrace, reason: reason);
      if (pending is Future<void>) {
        unawaited(pending.then<void>((_) {}, onError: (Object error) {}));
      }
    } on Object {
      // Reporting is best effort (the configuration may be missing).
    }
  }
}
