import '../../../../core/error/failure.dart';
import '../entities/auth_credentials.dart';
import '../entities/auth_session.dart';
import '../entities/auth_tokens.dart';
import '../entities/auth_user.dart';

/// Project specific bridge between `symphony_core` and a backend's
/// authentication API.
///
/// Every application supplies its own adapter, so endpoints, request bodies,
/// response formats and business rules stay owned by the application. Use the
/// configurable `RestAuthAdapter` for typical REST/JSON backends, or extend
/// this class for anything else (GraphQL, Firebase, OAuth SDKs, mocks...).
///
/// Implementations must throw a [Failure] (for example [AuthFailure],
/// [UnauthorizedFailure] or [NetworkFailure]) when an operation fails.
abstract class AuthAdapter {
  /// Allows subclasses to have const constructors.
  const AuthAdapter();

  /// Signs in with [credentials] and returns the new session.
  Future<AuthSession> login(AuthCredentials credentials);

  /// Exchanges the refresh token of [current] for new tokens.
  ///
  /// Throw [UnauthorizedFailure] when the refresh token is invalid or expired.
  /// The default implementation does not support refreshing.
  Future<AuthTokens> refresh(AuthTokens current) async {
    throw const UnauthorizedFailure();
  }

  /// Invalidates [session] on the backend. Local data is always cleared by
  /// the repository, even when this throws. Defaults to a no-op.
  Future<void> logout(AuthSession session) async {}

  /// Loads the profile of the session owner (used during session
  /// restoration). Defaults to the user stored in the session.
  Future<AuthUser?> fetchCurrentUser(AuthSession session) async =>
      session.user;

  /// Business rule hook executed after login and session restoration.
  ///
  /// Throw a [Failure] to reject a session (disabled account, missing
  /// subscription, wrong tenant...). Defaults to accepting every session.
  Future<void> validateSession(AuthSession session) async {}

  /// Whether [register] is supported.
  bool get supportsRegistration => false;

  /// Creates an account. Returns a session when the backend signs the user in
  /// immediately, otherwise `null`.
  Future<AuthSession?> register(AuthCredentials data) async {
    throw const UnsupportedFailure('Registration is not supported.');
  }

  /// Whether [requestPasswordReset] and [confirmPasswordReset] are supported.
  bool get supportsPasswordRecovery => false;

  /// Starts password recovery (for example sends an e-mail or an OTP).
  Future<void> requestPasswordReset(AuthCredentials data) async {
    throw const UnsupportedFailure('Password recovery is not supported.');
  }

  /// Completes password recovery (for example code + new password).
  Future<void> confirmPasswordReset(AuthCredentials data) async {
    throw const UnsupportedFailure('Password recovery is not supported.');
  }
}
