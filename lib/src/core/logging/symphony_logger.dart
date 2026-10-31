import 'package:flutter/foundation.dart';

import 'log_level.dart';

/// A single log entry.
@immutable
class LogEntry {
  /// Creates a log entry.
  const LogEntry({
    required this.level,
    required this.message,
    required this.time,
    this.tag,
    this.error,
    this.stackTrace,
  });

  /// Severity of the entry.
  final LogLevel level;

  /// Already redacted message.
  final String message;

  /// When the entry was created.
  final DateTime time;

  /// Optional category, e.g. `HTTP` or `Auth`.
  final String? tag;

  /// Optional error object.
  final Object? error;

  /// Optional stack trace.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('[${level.name.toUpperCase()}]');
    if (tag != null) buffer.write('[$tag]');
    buffer.write(' $message');
    if (error != null) buffer.write('\n  error: $error');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    return buffer.toString();
  }
}

/// Destination for log entries (console, file, crash reporter...).
abstract class LogSink {
  /// Allows subclasses to have const constructors.
  const LogSink();

  /// Writes [entry].
  void write(LogEntry entry);
}

/// Writes log entries to the console using [debugPrint].
class DebugPrintLogSink extends LogSink {
  /// Creates a console sink.
  const DebugPrintLogSink();

  @override
  void write(LogEntry entry) => debugPrint(entry.toString());
}

/// Lightweight, dependency free logger used across `symphony_core`.
///
/// Callers are responsible for redacting secrets (see `LogRedactor`) before
/// passing messages to the logger.
class SymphonyLogger {
  /// Creates a logger.
  SymphonyLogger({
    this.enabled = true,
    this.minLevel = LogLevel.debug,
    this.tag,
    List<LogSink>? sinks,
  }) : sinks = List<LogSink>.unmodifiable(
          sinks ?? const <LogSink>[DebugPrintLogSink()],
        );

  /// A logger that discards everything.
  SymphonyLogger.disabled()
      : enabled = false,
        minLevel = LogLevel.none,
        tag = null,
        sinks = const <LogSink>[];

  /// Whether the logger writes anything at all.
  final bool enabled;

  /// Entries below this level are discarded.
  final LogLevel minLevel;

  /// Default tag applied to entries without an explicit tag.
  final String? tag;

  /// Destinations receiving the entries.
  final List<LogSink> sinks;

  /// Returns a logger sharing this configuration with a different [tag].
  SymphonyLogger withTag(String tag) => SymphonyLogger(
        enabled: enabled,
        minLevel: minLevel,
        tag: tag,
        sinks: sinks,
      );

  /// Whether an entry at [level] would be written.
  bool isEnabledFor(LogLevel level) =>
      enabled &&
      level != LogLevel.none &&
      minLevel != LogLevel.none &&
      level.isAtLeast(minLevel);

  /// Writes a message at [level].
  void log(
    LogLevel level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!isEnabledFor(level)) return;
    final entry = LogEntry(
      level: level,
      message: message,
      time: DateTime.now(),
      tag: tag ?? this.tag,
      error: error,
      stackTrace: stackTrace,
    );
    for (final sink in sinks) {
      try {
        sink.write(entry);
      } on Object catch (e) {
        // A failing sink must never crash the app.
        debugPrint('SymphonyLogger sink failure: $e');
      }
    }
  }

  /// Logs at [LogLevel.verbose].
  void verbose(String message, {String? tag}) =>
      log(LogLevel.verbose, message, tag: tag);

  /// Logs at [LogLevel.debug].
  void debug(String message, {String? tag}) =>
      log(LogLevel.debug, message, tag: tag);

  /// Logs at [LogLevel.info].
  void info(String message, {String? tag}) =>
      log(LogLevel.info, message, tag: tag);

  /// Logs at [LogLevel.warning].
  void warning(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        LogLevel.warning,
        message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );

  /// Logs at [LogLevel.error].
  void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        LogLevel.error,
        message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
}
