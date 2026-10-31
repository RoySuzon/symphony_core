import 'dart:async';

import '../../../core/error/failure.dart';
import '../../../core/logging/symphony_logger.dart';
import '../../networking/domain/auth_token_delegate.dart';
import '../domain/entities/auth_session.dart';
import '../domain/repositories/auth_repository.dart';

/// [AuthTokenDelegate] backed by the session of an [AuthRepository].
///
/// It lets the `ApiClient` attach the current access token, refresh expired
/// tokens and end the session once the backend keeps rejecting it, without
/// the networking layer knowing anything about authentication.
///
/// Everything is resolved through callbacks, which keeps provider graphs free
/// of cycles and makes the delegate easy to test:
///
/// ```dart
/// SessionTokenDelegate(
///   repository: () => ref.read(authRepositoryProvider),
///   onSessionRefreshed: (session) =>
///       ref.read(authControllerProvider.notifier).updateSession(session),
///   onExpired: (failure) => ref
///       .read(authControllerProvider.notifier)
///       .handleSessionExpired(failure),
/// );
/// ```
class SessionTokenDelegate extends AuthTokenDelegate {
  /// Creates the delegate.
  ///
  /// * [repository] returns the repository holding the session (called on
  ///   every use, never cached).
  /// * [onSessionRefreshed] is told about the session after a successful
  ///   refresh (typically `AuthController.updateSession`).
  /// * [onExpired] ends the session after the backend rejected it (typically
  ///   `AuthController.handleSessionExpired`). Without it the repository's
  ///   session is cleared.
  SessionTokenDelegate({
    required AuthRepository Function() repository,
    void Function(AuthSession session)? onSessionRefreshed,
    FutureOr<void> Function(Failure reason)? onExpired,
    SymphonyLogger? logger,
  }) : _repository = repository,
       _onSessionRefreshed = onSessionRefreshed,
       _onExpired = onExpired,
       _logger = logger;

  final AuthRepository Function() _repository;
  final void Function(AuthSession session)? _onSessionRefreshed;
  final FutureOr<void> Function(Failure reason)? _onExpired;
  final SymphonyLogger? _logger;

  Future<String?>? _refreshing;

  /// Access token of the session whose last refresh failed.
  String? _failedAccessToken;

  @override
  Future<String?> getAccessToken() async =>
      _repository().currentSession?.tokens.accessToken;

  /// Refreshes the tokens through [AuthRepository.refreshTokens] and returns
  /// the new access token, or `null` when refreshing is impossible.
  ///
  /// Concurrent calls share one refresh.
  @override
  Future<String?> refreshAccessToken() {
    return _refreshing ??= _refresh().whenComplete(() {
      _refreshing = null;
    });
  }

  /// Ends the session with an [UnauthorizedFailure] as reason.
  ///
  /// A session started after a failed refresh (the user signed in again in
  /// the meantime) is left untouched.
  @override
  Future<void> onSessionExpired() async {
    final failed = _failedAccessToken;
    _failedAccessToken = null;
    final repository = _repository();
    final current = repository.currentSession;
    if (failed != null &&
        current != null &&
        current.tokens.accessToken != failed) {
      _logger?.debug('Ignoring the expiry of a replaced session.');
      return;
    }
    const reason = UnauthorizedFailure();
    final handler = _onExpired;
    if (handler != null) {
      await handler(reason);
    } else {
      await repository.clearSession();
    }
  }

  Future<String?> _refresh() async {
    final AuthRepository repository;
    try {
      repository = _repository();
    } on Object catch (error, stackTrace) {
      _logger?.error(
        'Unable to resolve the auth repository.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
    final before = repository.currentSession;
    final tokens = await repository.refreshTokens();
    if (tokens == null) {
      _failedAccessToken = before?.tokens.accessToken;
      return null;
    }
    _failedAccessToken = null;
    final session = repository.currentSession;
    final listener = _onSessionRefreshed;
    if (session != null && listener != null) {
      try {
        listener(session);
      } on Object catch (error, stackTrace) {
        // A failing listener must not break the request being retried.
        _logger?.error(
          'A session listener failed after a token refresh.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return tokens.accessToken;
  }
}
