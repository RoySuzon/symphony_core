import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import 'demo_backend.dart';

/// The [DemoBackend] answering the `ApiClient`'s requests, or `null` when
/// the app talks to a real server.
///
/// It is derived from `httpClientAdapterProvider` (the single override made
/// in `main.dart`), so the developer tools of the settings page disappear
/// automatically once a real backend is used.
final demoBackendProvider = Provider<DemoBackend?>((ref) {
  final adapter = ref.watch(httpClientAdapterProvider);
  return adapter is DemoBackend ? adapter : null;
}, name: 'demoBackendProvider');
