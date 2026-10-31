import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/symphony_config.dart';
import '../error/error_reporter.dart';
import '../logging/log_redactor.dart';
import '../logging/symphony_logger.dart';

/// The active [SymphonyConfig].
///
/// It has no default value: it is provided by `SymphonyCore.initialize` or by
/// adding `symphonyOverrides(config: ...)` to a `ProviderScope`.
final symphonyConfigProvider = Provider<SymphonyConfig>(
  (ref) => throw StateError(
    'symphonyConfigProvider is not configured. Call '
    'SymphonyCore.initialize(config: ...) before runApp, or add '
    'symphonyOverrides(config: ...) to your ProviderScope overrides.',
  ),
  name: 'symphonyConfigProvider',
);

/// Shared [SymphonyLogger] configured from [symphonyConfigProvider].
final symphonyLoggerProvider = Provider<SymphonyLogger>(
  (ref) {
    final config = ref.watch(symphonyConfigProvider);
    return SymphonyLogger(
      enabled: config.enableLogging,
      minLevel: config.logLevel,
      tag: 'Symphony',
    );
  },
  name: 'symphonyLoggerProvider',
);

/// Shared [LogRedactor] configured from [symphonyConfigProvider].
final logRedactorProvider = Provider<LogRedactor>(
  (ref) => ref.watch(symphonyConfigProvider).redactor,
  name: 'logRedactorProvider',
);

/// Destination of unexpected errors. Override it to plug a crash reporter.
final errorReporterProvider = Provider<ErrorReporter>(
  (ref) => LoggerErrorReporter(ref.watch(symphonyLoggerProvider)),
  name: 'errorReporterProvider',
);
