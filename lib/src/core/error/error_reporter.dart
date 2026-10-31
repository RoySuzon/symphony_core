import 'dart:async';

import '../logging/symphony_logger.dart';

/// Receives unexpected errors so they can be forwarded to a crash reporting
/// service (Sentry, Crashlytics, ...).
///
/// Implement this interface in the application and pass it to
/// `SymphonyCore.initialize(errorReporter: ...)`. The package never depends on
/// a specific crash reporting SDK.
abstract class ErrorReporter {
  /// Allows subclasses to have const constructors.
  const ErrorReporter();

  /// Reports [error]. Implementations must never throw.
  FutureOr<void> report(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  });
}

/// Reporter that ignores every error.
class NoopErrorReporter extends ErrorReporter {
  /// Creates a reporter that does nothing.
  const NoopErrorReporter();

  @override
  void report(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  }) {}
}

/// Reporter that writes errors to a [SymphonyLogger].
class LoggerErrorReporter extends ErrorReporter {
  /// Creates a reporter that logs through [logger].
  const LoggerErrorReporter(this.logger);

  /// Destination logger.
  final SymphonyLogger logger;

  @override
  void report(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    logger.error(
      '${fatal ? 'FATAL ' : ''}${reason ?? 'Unhandled error'}',
      tag: 'Error',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Forwards every report to several reporters.
class CompositeErrorReporter extends ErrorReporter {
  /// Creates a reporter that fans out to [reporters].
  const CompositeErrorReporter(this.reporters);

  /// Destination reporters.
  final List<ErrorReporter> reporters;

  @override
  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    for (final reporter in reporters) {
      try {
        await reporter.report(
          error,
          stackTrace,
          reason: reason,
          fatal: fatal,
          context: context,
        );
      } on Object {
        // Reporting must never throw.
      }
    }
  }
}
