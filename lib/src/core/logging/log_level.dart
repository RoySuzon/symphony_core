/// Severity of a log entry, ordered from most to least verbose.
enum LogLevel {
  /// Very detailed diagnostic output.
  verbose,

  /// Debugging information.
  debug,

  /// Informational messages.
  info,

  /// Something unexpected that the app can recover from.
  warning,

  /// An error that needs attention.
  error,

  /// Disables logging entirely when used as a minimum level.
  none;

  /// Whether this level is at least as severe as [other].
  bool isAtLeast(LogLevel other) => index >= other.index;
}
