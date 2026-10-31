import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

/// Matches the error thrown when reading an unconfigured provider. Riverpod 3
/// wraps it in a `ProviderException`, Riverpod 2 rethrows it as is.
Matcher throwsMentioning(String text) =>
    throwsA(predicate((Object? error) => '$error'.contains(text)));

void main() {
  test('symphonyConfigProvider must be configured', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      () => container.read(symphonyConfigProvider),
      throwsMentioning('symphonyConfigProvider is not configured'),
    );
  });

  test('the logger and the redactor are derived from the configuration', () {
    final container = ProviderContainer(
      overrides: [
        symphonyConfigProvider.overrideWithValue(
          const SymphonyConfig(
            baseUrl: 'https://api.example.com',
            enableLogging: true,
            logLevel: LogLevel.warning,
            sensitiveKeys: <String>{'pin'},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final logger = container.read(symphonyLoggerProvider);
    expect(logger.enabled, isTrue);
    expect(logger.minLevel, LogLevel.warning);
    expect(logger.tag, 'Symphony');
    expect(container.read(logRedactorProvider).sensitiveKeys, <String>{'pin'});
  });

  test('logging is disabled unless enabled in the configuration', () {
    final container = ProviderContainer(
      overrides: [
        symphonyConfigProvider.overrideWithValue(
          const SymphonyConfig(baseUrl: 'https://api.example.com'),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(symphonyLoggerProvider).enabled, isFalse);
  });

  test('the default error reporter logs through the shared logger', () {
    final container = ProviderContainer(
      overrides: [
        symphonyConfigProvider.overrideWithValue(
          const SymphonyConfig(baseUrl: 'https://api.example.com'),
        ),
      ],
    );
    addTearDown(container.dispose);

    final reporter = container.read(errorReporterProvider);
    expect(reporter, isA<LoggerErrorReporter>());
    expect(
      (reporter as LoggerErrorReporter).logger,
      same(container.read(symphonyLoggerProvider)),
    );
  });
}
