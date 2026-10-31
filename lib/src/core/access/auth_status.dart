/// Coarse authentication status shared by routing, dashboard and UI.
enum AuthStatus {
  /// The session has not been restored yet (app start).
  unknown,

  /// A valid session exists.
  authenticated,

  /// No session exists or it was cleared.
  unauthenticated,
}
