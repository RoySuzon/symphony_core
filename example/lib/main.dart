import 'package:flutter/widgets.dart';
import 'package:symphony_core/symphony_core.dart';

import 'app/example_app.dart';
import 'core/backend/demo_backend.dart';
import 'core/storage/resilient_key_value_storage.dart';
import 'features/auth/data/example_auth_adapter.dart';

Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(
      baseUrl: 'https://api.example.com',
      appName: 'Symphony Example',
      enableInspector: true,
      enableLogging: true,
      connectTimeout: Duration(seconds: 30),
    ),
    // A RestAuthAdapter configured for the demo backend's endpoints, request
    // bodies and response format (features/auth/data).
    authAdapterBuilder: createExampleAuthAdapter,
    // flutter_secure_storage, with an in-memory fallback on platforms where
    // it is not available out of the box (e.g. macOS without entitlements).
    secureStorage: ResilientKeyValueStorage(
      primary: const SecureKeyValueStorage(),
      fallback: InMemoryKeyValueStorage(),
      onFallback:
          (failure) => debugPrint(
            'Secure storage unavailable (${failure.message}); '
            'the session is kept in memory.',
          ),
    ),
    overrides: [
      // Every request of the ApiClient is answered in-process by the demo
      // backend: no server is needed. Remove this line to use a real API.
      httpClientAdapterProvider.overrideWithValue(DemoBackend()),
    ],
  );
  runApp(const SymphonyScope(child: ExampleApp()));
}
