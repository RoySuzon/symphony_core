import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

import '../helpers/core_test_helpers.dart';

void main() {
  group('NoopErrorReporter', () {
    test('accepts reports without doing anything', () {
      const reporter = NoopErrorReporter();

      expect(
        () => reporter.report(StateError('x'), null, fatal: true),
        returnsNormally,
      );
    });
  });

  group('LoggerErrorReporter', () {
    test('logs errors with reason, error and stack trace', () {
      final sink = RecordingLogSink();
      final reporter = LoggerErrorReporter(
        SymphonyLogger(sinks: <LogSink>[sink]),
      );
      final error = StateError('boom');
      final stackTrace = StackTrace.current;

      reporter
        ..report(error, stackTrace, reason: 'While saving')
        ..report(error, null, fatal: true)
        ..report(error, null, reason: 'Crash', fatal: true);

      expect(sink.entries.map((e) => e.message), <String>[
        'While saving',
        'FATAL Unhandled error',
        'FATAL Crash',
      ]);
      expect(sink.entries.first.level, LogLevel.error);
      expect(sink.entries.first.tag, 'Error');
      expect(sink.entries.first.error, same(error));
      expect(sink.entries.first.stackTrace, same(stackTrace));
    });
  });

  group('CompositeErrorReporter', () {
    test('forwards every report with all its details', () async {
      final first = RecordingErrorReporter();
      final second = RecordingErrorReporter();
      final reporter = CompositeErrorReporter(<ErrorReporter>[first, second]);
      final error = StateError('boom');
      final stackTrace = StackTrace.current;

      await reporter.report(
        error,
        stackTrace,
        reason: 'reason',
        fatal: true,
        context: const <String, Object?>{'screen': 'home'},
      );

      for (final recorder in <RecordingErrorReporter>[first, second]) {
        final report = recorder.reports.single;
        expect(report.error, same(error));
        expect(report.stackTrace, same(stackTrace));
        expect(report.reason, 'reason');
        expect(report.fatal, isTrue);
        expect(report.context, <String, Object?>{'screen': 'home'});
      }
    });

    test('swallows synchronous and asynchronous reporter failures', () async {
      final last = RecordingErrorReporter();
      final reporter = CompositeErrorReporter(<ErrorReporter>[
        const ThrowingErrorReporter(),
        const AsyncFailingErrorReporter(),
        last,
      ]);

      await expectLater(reporter.report(StateError('x'), null), completes);
      expect(last.reports, hasLength(1));
    });

    test('an empty composite does nothing', () async {
      await expectLater(
        const CompositeErrorReporter(<ErrorReporter>[]).report('x', null),
        completes,
      );
    });
  });
}
