// Internal helper shared by the global error handlers and SymphonyCore. Not
// exported from the core barrel.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/symphony_logger.dart';
import 'error_reporter.dart';

/// Forwards an error to [reporter] without ever throwing.
///
/// [ErrorReporter] implementations must not throw, but a crash reporter that
/// fails while handling an uncaught error must not crash the application
/// either. Synchronous exceptions and failed futures returned by
/// [ErrorReporter.report] are caught and written to [logger] (or to the
/// console with [debugPrint] when no logger is given).
void reportErrorSafely(
  ErrorReporter reporter,
  Object error,
  StackTrace? stackTrace, {
  String? reason,
  bool fatal = false,
  Map<String, Object?> context = const <String, Object?>{},
  SymphonyLogger? logger,
}) {
  void onReporterFailure(Object failure, StackTrace failureStackTrace) {
    if (logger != null) {
      logger.warning(
        'ErrorReporter.report failed while reporting ${error.runtimeType}',
        tag: 'Error',
        error: failure,
        stackTrace: failureStackTrace,
      );
    } else {
      debugPrint('symphony_core: ErrorReporter.report failed: $failure');
    }
  }

  try {
    final result = reporter.report(
      error,
      stackTrace,
      reason: reason,
      fatal: fatal,
      context: context,
    );
    if (result is Future<void>) {
      unawaited(result.then<void>((_) {}, onError: onReporterFailure));
    }
  } on Object catch (failure, failureStackTrace) {
    onReporterFailure(failure, failureStackTrace);
  }
}
