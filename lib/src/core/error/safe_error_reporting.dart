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
/// either. Synchronous exceptions, failed futures returned by
/// [ErrorReporter.report] and asynchronous errors the reporter leaks (for
/// example an unawaited upload that fails while offline) are caught and
/// written to [logger] (or to the console with [debugPrint] when no logger
/// is given).
///
/// The reporter runs in its own error zone: an error it leaks must not reach
/// `PlatformDispatcher.onError` or a guarded zone, which would report it
/// again — and again, forever, when every report leaks a new error.
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

  FutureOr<void> result;
  runZonedGuarded<void>(
    () {
      result = reporter.report(
        error,
        stackTrace,
        reason: reason,
        fatal: fatal,
        context: context,
      );
    },
    // Synchronous exceptions and errors leaked in the reporter's zone.
    onReporterFailure,
  );
  final pending = result;
  if (pending is Future<void>) {
    // Registered in the caller's zone on purpose. The error of a future
    // created by the reporter in its own zone does not cross the zone
    // boundary: it is handled by `onReporterFailure` above. The error of a
    // future created elsewhere (a shared upload queue...) is handled here.
    unawaited(pending.then<void>((_) {}, onError: onReporterFailure));
  }
}
