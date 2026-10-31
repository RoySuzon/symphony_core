import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../data/api_inspector.dart';

/// The shared [ApiInspector], configured from `SymphonyConfig`.
///
/// It always exists (so the UI can be built unconditionally) but only records
/// traffic when `SymphonyConfig.enableInspector` is true: the inspector is
/// created with `enabled: config.enableInspector` (recording can still be
/// paused and resumed at runtime through [ApiInspector.enabled]). Its size and
/// body limits come from `inspectorMaxEntries`, `maxLoggedBodyLength`,
/// `logRequestBodies`, `logResponseBodies` and `sensitiveKeys`.
final apiInspectorProvider = Provider<ApiInspector>(
  (ref) {
    final config = ref.watch(symphonyConfigProvider);
    final inspector = ApiInspector(
      maxEntries: config.inspectorMaxEntries,
      redactor: config.redactor,
      maxBodyLength: config.maxLoggedBodyLength,
      captureRequestBodies: config.logRequestBodies,
      captureResponseBodies: config.logResponseBodies,
      enabled: config.enableInspector,
    );
    ref.onDispose(inspector.dispose);
    return inspector;
  },
  name: 'apiInspectorProvider',
);
