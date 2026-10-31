import 'dart:async';
import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import '../logging/symphony_logger.dart';
import 'error_reporter.dart';
import 'safe_error_reporting.dart';

/// Forwards uncaught errors of the whole application to an [ErrorReporter].
///
/// `SymphonyCore.initialize` installs these handlers automatically when
/// `SymphonyConfig.handleGlobalErrors` is `true`. Use this class directly
/// when the handlers must be installed earlier or configured differently:
///
/// ```dart
/// final registration = GlobalErrorHandler.install(
///   reporter: MyCrashReporter(),
/// );
/// // ...
/// registration.uninstall(); // restores the previous handlers
/// ```
///
/// Two sources are covered:
/// * framework errors reported through [FlutterError.onError] (build,
///   layout, paint, gesture callbacks...) — reported as **non-fatal**;
/// * uncaught errors of the root isolate reported through
///   [PlatformDispatcher.onError] (unawaited futures, timers, platform
///   channel callbacks...) — reported as **fatal** and marked as handled.
///
/// Previously installed handlers (for example from another SDK or from the
/// test framework) keep being called: the new handlers chain to them.
abstract final class GlobalErrorHandler {
  /// Installs the global error handlers and returns a registration that can
  /// [GlobalErrorHandlerRegistration.uninstall] them again.
  ///
  /// * [reporter] receives every captured error. Failures of the reporter
  ///   itself are caught and logged.
  /// * [logger] receives diagnostics (installation, reporter failures).
  /// * [handleFlutterErrors] replaces [FlutterError.onError]. The previous
  ///   handler is still called for every error.
  /// * [handlePlatformErrors] replaces [PlatformDispatcher.onError]. The
  ///   previous handler is still called; the error is always marked as
  ///   handled (the handler returns `true`).
  /// * [presentFlutterErrorsInDebug] keeps errors visible in debug builds:
  ///   captured errors are printed with [FlutterError.presentError], unless
  ///   the previous framework handler is Flutter's default presenter, which
  ///   already prints them. Set it to `false` when a previous handler prints
  ///   errors itself, to avoid duplicated console output. It has no effect in
  ///   profile and release builds.
  static GlobalErrorHandlerRegistration install({
    required ErrorReporter reporter,
    SymphonyLogger? logger,
    bool handleFlutterErrors = true,
    bool handlePlatformErrors = true,
    bool presentFlutterErrorsInDebug = true,
  }) {
    final registration = GlobalErrorHandlerRegistration._(
      reporter: reporter,
      logger: logger,
      presentInDebug: presentFlutterErrorsInDebug,
    );
    if (handleFlutterErrors) registration._installFlutterHandler();
    if (handlePlatformErrors) registration._installPlatformHandler();
    logger?.debug(
      'Global error handlers installed '
      '(flutter: $handleFlutterErrors, platform: $handlePlatformErrors)',
      tag: GlobalErrorHandlerRegistration._tag,
    );
    return registration;
  }

  /// Runs [body] in a guarded zone (see [runZonedGuarded]) that reports every
  /// uncaught error of that zone to [reporter] as **fatal**.
  ///
  /// Use it for applications that prefer zone based error handling, and
  /// initialize the bindings and call `runApp` **inside** [body] so that they
  /// run in the same zone:
  ///
  /// ```dart
  /// Future<void> main() => GlobalErrorHandler.runGuarded(
  ///       () async {
  ///         final core = await SymphonyCore.initialize(config: config);
  ///         runApp(core.wrap(const MyApp()));
  ///       },
  ///       reporter: MyCrashReporter(),
  ///     );
  /// ```
  ///
  /// The returned future completes once [body] has completed. When [body]
  /// throws (synchronously or asynchronously), the error is reported and the
  /// future still completes normally, so `main` never fails because of it.
  ///
  /// In debug builds reported errors are also printed with
  /// [FlutterError.presentError], unless [presentErrorsInDebug] is `false`.
  static Future<void> runGuarded(
    FutureOr<void> Function() body, {
    required ErrorReporter reporter,
    SymphonyLogger? logger,
    bool presentErrorsInDebug = true,
  }) {
    final done = Completer<void>();

    void report(Object error, StackTrace stackTrace) {
      reportErrorSafely(
        reporter,
        error,
        stackTrace,
        reason: 'Uncaught error in guarded zone',
        fatal: true,
        context: const <String, Object?>{'handler': 'runZonedGuarded'},
        logger: logger,
      );
      if (presentErrorsInDebug && kDebugMode) {
        _presentUncaughtError(
            error, stackTrace, 'while running a guarded zone');
      }
    }

    runZonedGuarded<void>(
      () {
        unawaited(
          Future<void>.sync(body).then<void>(
            (_) => done.complete(),
            onError: (Object error, StackTrace stackTrace) {
              report(error, stackTrace);
              done.complete();
            },
          ),
        );
      },
      report,
    );
    return done.future;
  }

  static void _presentUncaughtError(
    Object error,
    StackTrace stackTrace,
    String description,
  ) {
    FlutterError.presentError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'symphony_core',
        context: ErrorDescription(description),
      ),
    );
  }
}

/// Handle returned by [GlobalErrorHandler.install].
///
/// Call [uninstall] to restore the handlers that were active before the
/// installation (for example when disposing `SymphonyCore` or at the end of
/// a test).
final class GlobalErrorHandlerRegistration {
  GlobalErrorHandlerRegistration._({
    required ErrorReporter reporter,
    required SymphonyLogger? logger,
    required bool presentInDebug,
  })  : _reporter = reporter,
        _logger = logger,
        _presentInDebug = presentInDebug;

  static const String _tag = 'GlobalErrorHandler';

  /// Maps the handlers installed by registrations to their registration, so
  /// [uninstall] can skip handlers of registrations that are no longer
  /// active.
  static final Expando<GlobalErrorHandlerRegistration> _owners =
      Expando<GlobalErrorHandlerRegistration>('GlobalErrorHandlerRegistration');

  final ErrorReporter _reporter;
  final SymphonyLogger? _logger;
  final bool _presentInDebug;

  FlutterExceptionHandler? _flutterHandler;
  FlutterExceptionHandler? _previousFlutterHandler;
  ErrorCallback? _platformHandler;
  ErrorCallback? _previousPlatformHandler;
  bool _active = true;
  bool _reporting = false;

  /// Whether the handlers are installed, i.e. [uninstall] has not been
  /// called yet.
  bool get isActive => _active;

  /// Whether this registration replaced [FlutterError.onError].
  bool get handlesFlutterErrors => _flutterHandler != null;

  /// Whether this registration replaced [PlatformDispatcher.onError].
  bool get handlesPlatformErrors => _platformHandler != null;

  /// Restores the previous [FlutterError.onError] and
  /// [PlatformDispatcher.onError] handlers. Calling it again does nothing.
  ///
  /// When another handler was installed on top of these ones in the meantime
  /// (and still chains to them), it is left in place: these handlers then
  /// stop reporting and only forward errors to the handlers that were active
  /// before them. Handlers of other registrations that were already
  /// uninstalled that way are skipped when restoring, so uninstalling
  /// registrations in any order eventually restores the original handlers.
  void uninstall() {
    if (!_active) return;
    _active = false;
    final flutterHandler = _flutterHandler;
    if (flutterHandler != null &&
        identical(FlutterError.onError, flutterHandler)) {
      FlutterError.onError = _firstActive<FlutterExceptionHandler>(
        _previousFlutterHandler,
        (owner) => owner._previousFlutterHandler,
      );
    }
    final platformHandler = _platformHandler;
    final dispatcher = PlatformDispatcher.instance;
    if (platformHandler != null &&
        identical(dispatcher.onError, platformHandler)) {
      dispatcher.onError = _firstActive<ErrorCallback>(
        _previousPlatformHandler,
        (owner) => owner._previousPlatformHandler,
      );
    }
    _logger?.debug('Global error handlers removed', tag: _tag);
  }

  /// Follows the chain starting at [handler], skipping handlers that belong
  /// to uninstalled registrations.
  static T? _firstActive<T extends Function>(
    T? handler,
    T? Function(GlobalErrorHandlerRegistration owner) previousOf,
  ) {
    var current = handler;
    while (current != null) {
      final owner = _owners[current];
      if (owner == null || owner._active) return current;
      current = previousOf(owner);
    }
    return null;
  }

  void _installFlutterHandler() {
    final previous = FlutterError.onError;
    final previousPresents = previous != null &&
        (previous == FlutterError.presentError ||
            previous == FlutterError.dumpErrorToConsole);

    void handler(FlutterErrorDetails details) {
      if (_active) {
        _report(
          details.exception,
          details.stack,
          reason: _describeFlutterError(details),
          fatal: false,
          context: <String, Object?>{
            'handler': 'FlutterError.onError',
            'library': details.library,
            'silent': details.silent,
          },
        );
        if (_presentInDebug && kDebugMode && !previousPresents) {
          FlutterError.presentError(details);
        }
      }
      previous?.call(details);
    }

    _previousFlutterHandler = previous;
    _flutterHandler = handler;
    _owners[handler] = this;
    FlutterError.onError = handler;
  }

  void _installPlatformHandler() {
    final dispatcher = PlatformDispatcher.instance;
    final previous = dispatcher.onError;

    bool handler(Object error, StackTrace stackTrace) {
      if (!_active) return previous?.call(error, stackTrace) ?? false;
      _report(
        error,
        stackTrace,
        reason: 'Uncaught asynchronous error',
        fatal: true,
        context: const <String, Object?>{
          'handler': 'PlatformDispatcher.onError',
        },
      );
      if (_presentInDebug && kDebugMode) {
        GlobalErrorHandler._presentUncaughtError(
          error,
          stackTrace,
          'while handling an uncaught asynchronous error',
        );
      }
      if (previous != null) {
        try {
          previous(error, stackTrace);
        } on Object catch (failure, failureStackTrace) {
          _logger?.warning(
            'The previous PlatformDispatcher.onError handler threw',
            tag: _tag,
            error: failure,
            stackTrace: failureStackTrace,
          );
        }
      }
      return true;
    }

    _previousPlatformHandler = previous;
    _platformHandler = handler;
    _owners[handler] = this;
    dispatcher.onError = handler;
  }

  void _report(
    Object error,
    StackTrace? stackTrace, {
    required String reason,
    required bool fatal,
    required Map<String, Object?> context,
  }) {
    // A reporter that itself triggers a global error must not loop forever.
    if (_reporting) return;
    _reporting = true;
    try {
      reportErrorSafely(
        _reporter,
        error,
        stackTrace,
        reason: reason,
        fatal: fatal,
        context: context,
        logger: _logger,
      );
    } finally {
      _reporting = false;
    }
  }

  static String _describeFlutterError(FlutterErrorDetails details) {
    final context = details.context?.toDescription();
    final library = details.library;
    final buffer = StringBuffer('Flutter error');
    if (library != null && library.isNotEmpty) buffer.write(' ($library)');
    if (context != null && context.isNotEmpty) buffer.write(' $context');
    return buffer.toString();
  }
}
