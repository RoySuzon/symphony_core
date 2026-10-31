import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../entities/auth_credentials.dart';
import '../entities/auth_session.dart';
import '../entities/auth_tokens.dart';

/// Domain boundary of the authentication feature.
///
/// Coordinates the project's `AuthAdapter` (remote) with `SessionStorage`
/// (local). Presentation code talks to this interface only.
abstract class AuthRepository {
  /// Allows subclasses to have const constructors.
  const AuthRepository();

  /// The in-memory session, if any (no I/O).
  AuthSession? get currentSession;

  /// Restores the persisted session.
  ///
  /// Refreshes expired tokens when possible and validates the session with
  /// the adapter. Returns `Result.success(null)` when no usable session
  /// exists (local data is cleared in that case).
  Future<Result<AuthSession?>> restoreSession();

  /// Signs in and persists the resulting session.
  Future<Result<AuthSession>> login(AuthCredentials credentials);

  /// Signs out. The local session is always cleared, even if the remote call
  /// fails.
  Future<void> logout();

  /// Refreshes the tokens of the current session and persists them.
  ///
  /// Concurrent calls share one refresh. Returns `null` when refreshing is
  /// impossible (no session, no refresh token, rejected by the backend).
  Future<AuthTokens?> refreshTokens();

  /// Removes the local session without contacting the backend.
  Future<void> clearSession();

  /// Replaces the active session, in memory and in storage, without changing
  /// the authentication status (for example after a profile update).
  ///
  /// Fails when no session is active. The default implementation reports
  /// [UnsupportedFailure]; `AuthRepositoryImpl` implements it.
  Future<Result<void>> updateSession(AuthSession session) async =>
      const Result<void>.failure(
        UnsupportedFailure('Updating the session is not supported.'),
      );

  /// Whether the adapter supports registration.
  bool get supportsRegistration;

  /// Registers a new account. When the backend returns a session it is
  /// persisted and returned.
  Future<Result<AuthSession?>> register(AuthCredentials data);

  /// Whether the adapter supports password recovery.
  bool get supportsPasswordRecovery;

  /// Starts password recovery.
  Future<Result<void>> requestPasswordReset(AuthCredentials data);

  /// Completes password recovery.
  Future<Result<void>> confirmPasswordReset(AuthCredentials data);
}
