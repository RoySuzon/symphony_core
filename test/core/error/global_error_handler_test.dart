import 'dart:async';
import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

import '../helpers/core_test_helpers.dart';

void main() {
  late FlutterExceptionHandler? originalOnError;
  late FlutterExceptionHandler originalPresentError;
  late ErrorCallback? originalPlatformOnError;
  late List<FlutterErrorDetails> previousCalls;
  late FlutterExceptionHandler previousHandler;
  late RecordingErrorReporter reporter;
  late List<GlobalErrorHandlerRegistration> registrations;

  setUp(() {
    originalOnError = FlutterError.onError;
    originalPresentError = FlutterError.presentError;
    originalPlatformOnError = PlatformDispatcher.instance.onError;
    previousCalls = <FlutterErrorDetails>[];
    previousHandler = previousCalls.add;
    FlutterError.onError = previousHandler;
    PlatformDispatcher.instance.onError = null;
    reporter = RecordingErrorReporter();
    registrations = <GlobalErrorHandlerRegistration>[];
  });

  tearDown(() {
    for (final registration in registrations) {
      registration.uninstall();
    }
    FlutterError.onError = originalOnError;
    FlutterError.presentError = originalPresentError;
    PlatformDispatcher.instance.onError = originalPlatformOnError;
  });

  GlobalErrorHandlerRegistration install({
    ErrorReporter? errorReporter,
    SymphonyLogger? logger,
    bool handleFlutterErrors = true,
    bool handlePlatformErrors = true,
    bool present = false,
  }) {
    final registration = GlobalErrorHandler.install(
      reporter: errorReporter ?? reporter,
      logger: logger,
      handleFlutterErrors: handleFlutterErrors,
      handlePlatformErrors: handlePlatformErrors,
      presentFlutterErrorsInDebug: present,
    );
    registrations.add(registration);
    return registration;
  }

  FlutterErrorDetails details([Object? exception]) => FlutterErrorDetails(
        exception: exception ?? StateError('build failed'),
        stack: StackTrace.current,
        library: 'widgets library',
        context: ErrorDescription('while building MyWidget'),
      );

  group('GlobalErrorHandler.install', () {
    test(
        'reports framework errors as non-fatal and chains to the previous '
        'handler', () {
      final registration = install();
      final error = details();

      FlutterError.reportError(error);

      final report = reporter.reports.single;
      expect(report.error, same(error.exception));
      expect(report.stackTrace, same(error.stack));
      expect(report.fatal, isFalse);
      expect(
        report.reason,
        'Flutter error (widgets library) while building MyWidget',
      );
      expect(report.context['handler'], 'FlutterError.onError');
      expect(report.context['library'], 'widgets library');
      expect(report.context['silent'], isFalse);
      expect(previousCalls.single, same(error));
      expect(registration.isActive, isTrue);
      expect(registration.handlesFlutterErrors, isTrue);
      expect(registration.handlesPlatformErrors, isTrue);
    });

    test('reports platform errors as fatal and marks them handled', () {
      final previousErrors = <Object>[];
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        previousErrors.add(error);
        return false;
      };
      install();
      final error = StateError('unawaited future');

      final handled =
          PlatformDispatcher.instance.onError!(error, StackTrace.current);

      expect(handled, isTrue);
      final report = reporter.reports.single;
      expect(report.error, same(error));
      expect(report.fatal, isTrue);
      expect(report.context['handler'], 'PlatformDispatcher.onError');
      expect(previousErrors.single, same(error));
    });

    test('contains a throwing previous platform handler', () {
      final sink = RecordingLogSink();
      PlatformDispatcher.instance.onError =
          (error, stackTrace) => throw StateError('previous exploded');
      install(logger: SymphonyLogger(sinks: <LogSink>[sink]));

      final handled =
          PlatformDispatcher.instance.onError!('error', StackTrace.current);

      expect(handled, isTrue);
      expect(reporter.reports, hasLength(1));
      expect(
        sink.entries.where((e) => e.level == LogLevel.warning).single.message,
        contains('previous PlatformDispatcher.onError'),
      );
    });

    test('uninstall restores the previous handlers and is idempotent', () {
      bool previousPlatform(Object error, StackTrace stackTrace) => false;
      final ErrorCallback platformHandler = previousPlatform;
      PlatformDispatcher.instance.onError = platformHandler;
      final registration = install();

      expect(identical(FlutterError.onError, previousHandler), isFalse);
      expect(
        identical(PlatformDispatcher.instance.onError, platformHandler),
        isFalse,
      );

      registration.uninstall();
      registration.uninstall();

      expect(registration.isActive, isFalse);
      expect(identical(FlutterError.onError, previousHandler), isTrue);
      expect(
        identical(PlatformDispatcher.instance.onError, platformHandler),
        isTrue,
      );
      FlutterError.reportError(details());
      expect(reporter.reports, isEmpty);
      expect(previousCalls, hasLength(1));
    });

    test('restores a null platform handler', () {
      final registration = install();
      expect(PlatformDispatcher.instance.onError, isNotNull);

      registration.uninstall();

      expect(PlatformDispatcher.instance.onError, isNull);
    });

    test('installs only the requested handlers', () {
      final onlyPlatform = install(handleFlutterErrors: false);
      expect(identical(FlutterError.onError, previousHandler), isTrue);
      expect(onlyPlatform.handlesFlutterErrors, isFalse);
      expect(onlyPlatform.handlesPlatformErrors, isTrue);
      onlyPlatform.uninstall();

      final onlyFlutter = install(handlePlatformErrors: false);
      expect(PlatformDispatcher.instance.onError, isNull);
      expect(onlyFlutter.handlesFlutterErrors, isTrue);
      expect(onlyFlutter.handlesPlatformErrors, isFalse);
    });

    test('uninstalling registrations in any order restores the originals', () {
      final first = install();
      final firstPlatform = PlatformDispatcher.instance.onError;
      final second = install();

      first.uninstall();

      expect(identical(FlutterError.onError, previousHandler), isFalse);
      FlutterError.reportError(details());
      expect(reporter.reports, hasLength(1), reason: 'only `second` reports');
      expect(previousCalls, hasLength(1));
      expect(
        identical(PlatformDispatcher.instance.onError, firstPlatform),
        isFalse,
      );

      second.uninstall();

      expect(identical(FlutterError.onError, previousHandler), isTrue);
      expect(PlatformDispatcher.instance.onError, isNull);
    });

    test('uninstalling the top registration re-activates the one below', () {
      final first = install();
      final firstHandler = FlutterError.onError;
      final second = install();

      second.uninstall();

      expect(identical(FlutterError.onError, firstHandler), isTrue);
      FlutterError.reportError(details());
      expect(reporter.reports, hasLength(1));

      first.uninstall();
      expect(identical(FlutterError.onError, previousHandler), isTrue);
    });

    test(
        'presents framework errors in debug unless the previous handler '
        'already presents them', () {
      final presented = <FlutterErrorDetails>[];
      FlutterError.presentError = presented.add;

      final withCustomPrevious = install(present: true);
      FlutterError.reportError(details());
      expect(presented, hasLength(1));
      expect(previousCalls, hasLength(1));
      withCustomPrevious.uninstall();

      presented.clear();
      FlutterError.onError = FlutterError.presentError;
      install(present: true);
      FlutterError.reportError(details());
      expect(presented, hasLength(1), reason: 'no duplicated output');
      expect(reporter.reports, hasLength(2));
    });

    test('does not present errors when disabled', () {
      final presented = <FlutterErrorDetails>[];
      FlutterError.presentError = presented.add;
      install();

      FlutterError.reportError(details());
      PlatformDispatcher.instance.onError!('async', StackTrace.current);

      expect(presented, isEmpty);
      expect(reporter.reports, hasLength(2));
    });

    test('presents platform errors in debug when enabled', () {
      final presented = <FlutterErrorDetails>[];
      FlutterError.presentError = presented.add;
      install(present: true);

      PlatformDispatcher.instance.onError!('async', StackTrace.current);

      expect(presented.single.exception, 'async');
      expect(presented.single.library, 'symphony_core');
    });

    test('contains synchronous reporter failures and logs them', () {
      final sink = RecordingLogSink();
      install(
        errorReporter: const ThrowingErrorReporter(),
        logger: SymphonyLogger(sinks: <LogSink>[sink]),
      );

      expect(() => FlutterError.reportError(details()), returnsNormally);
      expect(
        PlatformDispatcher.instance.onError!('async', StackTrace.current),
        isTrue,
      );

      expect(previousCalls, hasLength(1));
      final warnings = sink.entries.where((e) => e.level == LogLevel.warning);
      expect(warnings, hasLength(2));
      expect(warnings.first.message, contains('ErrorReporter.report failed'));
      expect(warnings.first.error, isA<StateError>());
    });

    test('contains asynchronous reporter failures and logs them', () async {
      final sink = RecordingLogSink();
      install(
        errorReporter: const AsyncFailingErrorReporter(),
        logger: SymphonyLogger(sinks: <LogSink>[sink]),
      );

      FlutterError.reportError(details());
      await flushAsync();

      final warning =
          sink.entries.where((e) => e.level == LogLevel.warning).single;
      expect(warning.message, contains('ErrorReporter.report failed'));
    });

    test('ignores errors raised while reporting (no infinite loop)', () {
      install();
      reporter.onReport = (error) {
        if (error is StateError) {
          FlutterError.reportError(details(ArgumentError('nested')));
        }
      };

      FlutterError.reportError(details());

      expect(reporter.reports, hasLength(1));
      expect(
        previousCalls.map((d) => d.exception.runtimeType),
        <Type>[ArgumentError, StateError],
      );
    });

    test('logs installation and removal at debug level', () {
      final sink = RecordingLogSink();
      final registration = install(
        logger: SymphonyLogger(sinks: <LogSink>[sink]),
      );
      registration.uninstall();

      expect(
        sink.entries.map((e) => e.message),
        <Matcher>[contains('installed'), contains('removed')],
      );
      expect(sink.entries.every((e) => e.level == LogLevel.debug), isTrue);
    });
  });

  group('GlobalErrorHandler.runGuarded', () {
    test('completes once the body has completed', () async {
      var ran = false;

      await GlobalErrorHandler.runGuarded(
        () async {
          await Future<void>.delayed(Duration.zero);
          ran = true;
        },
        reporter: reporter,
        presentErrorsInDebug: false,
      );

      expect(ran, isTrue);
      expect(reporter.reports, isEmpty);
    });

    test('reports a failing body as fatal and still completes', () async {
      await GlobalErrorHandler.runGuarded(
        () => throw StateError('main failed'),
        reporter: reporter,
        presentErrorsInDebug: false,
      );

      final report = reporter.reports.single;
      expect(report.error, isA<StateError>());
      expect(report.fatal, isTrue);
      expect(report.context['handler'], 'runZonedGuarded');
    });

    test('reports uncaught asynchronous errors of the zone', () async {
      await GlobalErrorHandler.runGuarded(
        () {
          unawaited(Future<void>.error(ArgumentError('late failure')));
        },
        reporter: reporter,
        presentErrorsInDebug: false,
      );
      await flushAsync();

      expect(reporter.reports.single.error, isA<ArgumentError>());
      expect(reporter.reports.single.fatal, isTrue);
    });

    test('presents reported errors in debug by default', () async {
      final presented = <FlutterErrorDetails>[];
      FlutterError.presentError = presented.add;

      await GlobalErrorHandler.runGuarded(
        () => throw StateError('visible'),
        reporter: reporter,
      );

      expect(presented.single.exception, isA<StateError>());
      expect(presented.single.library, 'symphony_core');
    });

    test('survives a throwing reporter', () async {
      await expectLater(
        GlobalErrorHandler.runGuarded(
          () => throw StateError('x'),
          reporter: const ThrowingErrorReporter(),
          presentErrorsInDebug: false,
        ),
        completes,
      );
    });
  });
}
