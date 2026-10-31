import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

import '../helpers/core_test_helpers.dart';

void main() {
  group('LogLevel', () {
    test('is ordered from most to least verbose', () {
      expect(LogLevel.values, <LogLevel>[
        LogLevel.verbose,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
        LogLevel.none,
      ]);
      expect(LogLevel.error.isAtLeast(LogLevel.warning), isTrue);
      expect(LogLevel.info.isAtLeast(LogLevel.info), isTrue);
      expect(LogLevel.debug.isAtLeast(LogLevel.info), isFalse);
    });
  });

  group('SymphonyLogger', () {
    late RecordingLogSink sink;

    setUp(() => sink = RecordingLogSink());

    test('writes entries at or above minLevel to every sink', () {
      final second = RecordingLogSink();
      final logger = SymphonyLogger(
        minLevel: LogLevel.info,
        tag: 'App',
        sinks: <LogSink>[sink, second],
      );

      logger
        ..verbose('v')
        ..debug('d')
        ..info('i')
        ..warning('w')
        ..error('e');

      expect(sink.entries.map((e) => e.message), <String>['i', 'w', 'e']);
      expect(
        sink.entries.map((e) => e.level),
        <LogLevel>[LogLevel.info, LogLevel.warning, LogLevel.error],
      );
      expect(second.entries, hasLength(3));
    });

    test('isEnabledFor reflects enabled, minLevel and LogLevel.none', () {
      final logger = SymphonyLogger(sinks: <LogSink>[sink]);

      expect(logger.isEnabledFor(LogLevel.verbose), isFalse);
      expect(logger.isEnabledFor(LogLevel.debug), isTrue);
      expect(logger.isEnabledFor(LogLevel.error), isTrue);
      expect(logger.isEnabledFor(LogLevel.none), isFalse);

      logger.log(LogLevel.none, 'never written');
      expect(sink.entries, isEmpty);
    });

    test('minLevel none and enabled false discard everything', () {
      final silent = SymphonyLogger(
        minLevel: LogLevel.none,
        sinks: <LogSink>[sink],
      );
      final disabled = SymphonyLogger(enabled: false, sinks: <LogSink>[sink]);

      silent.error('nope');
      disabled.error('nope');

      expect(sink.entries, isEmpty);
      expect(disabled.isEnabledFor(LogLevel.error), isFalse);
    });

    test('SymphonyLogger.disabled writes nothing and has no sinks', () {
      final logger = SymphonyLogger.disabled();

      logger.error('ignored');

      expect(logger.enabled, isFalse);
      expect(logger.minLevel, LogLevel.none);
      expect(logger.sinks, isEmpty);
      expect(logger.isEnabledFor(LogLevel.error), isFalse);
    });

    test('applies the default tag and lets callers override it', () {
      final logger = SymphonyLogger(tag: 'Default', sinks: <LogSink>[sink]);

      logger
        ..info('a')
        ..info('b', tag: 'Custom');

      expect(sink.entries.map((e) => e.tag), <String?>['Default', 'Custom']);
    });

    test('keeps error and stack trace of warnings and errors', () {
      final logger = SymphonyLogger(sinks: <LogSink>[sink]);
      final error = StateError('boom');
      final stackTrace = StackTrace.current;

      logger
        ..warning('w', error: error, stackTrace: stackTrace)
        ..error('e', error: error, stackTrace: stackTrace);

      for (final entry in sink.entries) {
        expect(entry.error, same(error));
        expect(entry.stackTrace, same(stackTrace));
        expect(entry.time, isA<DateTime>());
      }
    });

    test('a failing sink is swallowed and does not stop other sinks', () {
      final printed = <String?>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => printed.add(message);
      try {
        final logger = SymphonyLogger(
          sinks: <LogSink>[const ThrowingLogSink(), sink],
        );

        expect(() => logger.error('still logged'), returnsNormally);
        expect(sink.entries.single.message, 'still logged');
        expect(printed.single, contains('sink failure'));
      } finally {
        debugPrint = originalDebugPrint;
      }
    });

    test('withTag shares the configuration and sinks', () {
      final logger = SymphonyLogger(
        minLevel: LogLevel.warning,
        tag: 'Root',
        sinks: <LogSink>[sink],
      );

      final child = logger.withTag('Child');
      child
        ..info('dropped')
        ..warning('kept');

      expect(child.tag, 'Child');
      expect(child.minLevel, LogLevel.warning);
      expect(child.enabled, isTrue);
      expect(child.sinks, logger.sinks);
      expect(sink.entries.single.tag, 'Child');
    });

    test('sinks are unmodifiable and default to the console sink', () {
      final logger = SymphonyLogger();

      expect(logger.sinks.single, isA<DebugPrintLogSink>());
      expect(
        () => logger.sinks.add(RecordingLogSink()),
        throwsUnsupportedError,
      );
    });

    test('DebugPrintLogSink prints the formatted entry', () {
      final printed = <String?>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => printed.add(message);
      try {
        SymphonyLogger(tag: 'Net').info('hello');
      } finally {
        debugPrint = originalDebugPrint;
      }

      expect(printed.single, '[INFO][Net] hello');
    });
  });

  group('LogEntry.toString', () {
    test('includes level, tag, message, error and stack trace', () {
      final entry = LogEntry(
        level: LogLevel.error,
        message: 'failed',
        time: DateTime(2024),
        tag: 'HTTP',
        error: 'timeout',
        stackTrace: StackTrace.fromString('#0 main'),
      );

      expect(
          entry.toString(), '[ERROR][HTTP] failed\n  error: timeout\n#0 main');
    });

    test('omits missing parts', () {
      final entry = LogEntry(
        level: LogLevel.debug,
        message: 'plain',
        time: DateTime(2024),
      );

      expect(entry.toString(), '[DEBUG] plain');
    });
  });
}
