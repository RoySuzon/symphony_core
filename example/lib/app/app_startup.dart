import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/presentation/settings_providers.dart';

/// Start-up tasks, run by the splash screen before the session is restored
/// (`SymphonySplashScreen.onInitialize`):
///
/// 1. restore the user preferences — theme and server environment, applied
///    to the `ApiClient` with `updateBaseUrl` before any other request;
/// 2. check that the backend is reachable (public `GET /status`).
///
/// A thrown `Failure` makes the splash screen display it with a retry
/// button (try it with "Simulate a network outage" in the settings, then
/// restart the app... or simply trust the tests).
Future<void> initializeExampleApp(WidgetRef ref) async {
  await ref.read(appPreferencesProvider.notifier).restore();
  final status = await ref.read(serverStatusRepositoryProvider).check();
  status.getOrThrow();
}
