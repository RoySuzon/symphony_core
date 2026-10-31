import 'package:flutter/foundation.dart';

/// Paths (relative to the `ApiClient` base URL, or absolute URLs) and HTTP
/// methods of a backend's authentication endpoints, used by
/// `RestAuthAdapter`.
///
/// Only [login] is required: there are no default paths, every application
/// declares its own. Leaving an optional endpoint `null` disables the
/// matching feature:
///
/// * no [refresh] — tokens are never refreshed (an expired session signs the
///   user out);
/// * no [logout] — signing out only clears the local session;
/// * no [currentUser] — the user returned by the sign-in response is used;
/// * no [register] — `supportsRegistration` is `false`;
/// * no [requestPasswordReset] — `supportsPasswordRecovery` is `false`;
/// * no [confirmPasswordReset] — recovery is completed outside the app (for
///   example through a link sent by e-mail).
///
/// ```dart
/// const endpoints = RestAuthEndpoints(
///   login: '/auth/login',
///   refresh: '/auth/refresh',
///   logout: '/auth/logout',
///   currentUser: '/me',
/// );
/// ```
@immutable
class RestAuthEndpoints {
  /// Creates the endpoint configuration.
  const RestAuthEndpoints({
    required this.login,
    this.refresh,
    this.logout,
    this.currentUser,
    this.register,
    this.requestPasswordReset,
    this.confirmPasswordReset,
    this.loginMethod = 'POST',
    this.refreshMethod = 'POST',
    this.logoutMethod = 'POST',
    this.currentUserMethod = 'GET',
    this.registerMethod = 'POST',
    this.requestPasswordResetMethod = 'POST',
    this.confirmPasswordResetMethod = 'POST',
  });

  /// Signs in and returns tokens (and optionally the user).
  final String login;

  /// Exchanges a refresh token for new tokens.
  final String? refresh;

  /// Invalidates the session on the backend.
  final String? logout;

  /// Returns the profile of the signed-in user.
  final String? currentUser;

  /// Creates an account.
  final String? register;

  /// Starts password recovery (sends an e-mail, an SMS code...).
  final String? requestPasswordReset;

  /// Completes password recovery (code + new password...).
  final String? confirmPasswordReset;

  /// HTTP method of [login].
  final String loginMethod;

  /// HTTP method of [refresh].
  final String refreshMethod;

  /// HTTP method of [logout].
  final String logoutMethod;

  /// HTTP method of [currentUser].
  final String currentUserMethod;

  /// HTTP method of [register].
  final String registerMethod;

  /// HTTP method of [requestPasswordReset].
  final String requestPasswordResetMethod;

  /// HTTP method of [confirmPasswordReset].
  final String confirmPasswordResetMethod;

  @override
  bool operator ==(Object other) =>
      other is RestAuthEndpoints &&
      other.login == login &&
      other.refresh == refresh &&
      other.logout == logout &&
      other.currentUser == currentUser &&
      other.register == register &&
      other.requestPasswordReset == requestPasswordReset &&
      other.confirmPasswordReset == confirmPasswordReset &&
      other.loginMethod == loginMethod &&
      other.refreshMethod == refreshMethod &&
      other.logoutMethod == logoutMethod &&
      other.currentUserMethod == currentUserMethod &&
      other.registerMethod == registerMethod &&
      other.requestPasswordResetMethod == requestPasswordResetMethod &&
      other.confirmPasswordResetMethod == confirmPasswordResetMethod;

  @override
  int get hashCode => Object.hash(
    login,
    refresh,
    logout,
    currentUser,
    register,
    requestPasswordReset,
    confirmPasswordReset,
    loginMethod,
    refreshMethod,
    logoutMethod,
    currentUserMethod,
    registerMethod,
    requestPasswordResetMethod,
    confirmPasswordResetMethod,
  );

  @override
  String toString() =>
      'RestAuthEndpoints(login: $login, refresh: $refresh, '
      'logout: $logout, currentUser: $currentUser, register: $register, '
      'requestPasswordReset: $requestPasswordReset, '
      'confirmPasswordReset: $confirmPasswordReset)';
}
