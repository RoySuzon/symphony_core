/// Supplies credentials to the networking layer without coupling it to a
/// specific authentication implementation.
///
/// The authentication module provides an implementation backed by the
/// current session. Applications that manage tokens themselves can implement
/// this interface and override `authTokenDelegateProvider`.
abstract class AuthTokenDelegate {
  /// Allows subclasses to have const constructors.
  const AuthTokenDelegate();

  /// Returns the current access token, or `null` when signed out.
  Future<String?> getAccessToken();

  /// Refreshes the session and returns the new access token, or `null` when
  /// refreshing is impossible. Concurrent calls should share one refresh.
  Future<String?> refreshAccessToken();

  /// Called when the server keeps rejecting the credentials (refresh failed
  /// or the refreshed token was rejected). Typically signs the user out.
  Future<void> onSessionExpired();
}
