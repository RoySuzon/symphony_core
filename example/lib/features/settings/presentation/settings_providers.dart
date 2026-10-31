import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/backend/demo_backend_providers.dart';
import '../data/settings_repositories.dart';
import '../domain/settings_entities.dart';

/// Preferences storage (the package's `secureStorageProvider`).
final preferencesRepositoryProvider = Provider<PreferencesRepository>(
  (ref) => StoragePreferencesRepository(ref.watch(secureStorageProvider)),
  name: 'preferencesRepositoryProvider',
);

/// Backend health check.
final serverStatusRepositoryProvider = Provider<ServerStatusRepository>(
  (ref) => ApiServerStatusRepository(ref.watch(apiClientProvider)),
  name: 'serverStatusRepositoryProvider',
);

/// User preferences: theme and server environment.
class AppPreferencesController extends Notifier<AppPreferences> {
  @override
  AppPreferences build() => const AppPreferences();

  PreferencesRepository get _repository =>
      ref.read(preferencesRepositoryProvider);

  /// Loads the stored preferences and applies the stored environment to the
  /// `ApiClient`. Called once at start-up by the splash screen.
  Future<void> restore() async {
    final AppPreferences stored;
    try {
      stored = await _repository.load();
    } on Failure catch (failure) {
      ref
          .read(symphonyLoggerProvider)
          .warning('Preferences unavailable: ${failure.message}');
      return;
    }
    final environment = ServerEnvironment.byId(stored.environmentId);
    if (environment != null) {
      ref.read(apiClientProvider).updateBaseUrl(environment.baseUrl);
    }
    state = stored;
  }

  /// Selects [theme].
  Future<void> setTheme(ThemePreference theme) =>
      _update(state.copyWith(theme: theme));

  /// Switches every subsequent request to [environment] at runtime with
  /// `ApiClient.updateBaseUrl` — no repository is recreated.
  Future<void> setEnvironment(ServerEnvironment environment) {
    ref.read(apiClientProvider).updateBaseUrl(environment.baseUrl);
    return _update(state.copyWith(environmentId: environment.id));
  }

  Future<void> _update(AppPreferences next) async {
    state = next;
    try {
      await _repository.save(next);
    } on Failure catch (failure) {
      ref
          .read(symphonyLoggerProvider)
          .warning('Preferences not saved: ${failure.message}');
    }
  }
}

/// User preferences.
final appPreferencesProvider =
    NotifierProvider<AppPreferencesController, AppPreferences>(
      AppPreferencesController.new,
      name: 'appPreferencesProvider',
    );

/// The [ThemeMode] of the app.
final themeModeProvider = Provider<ThemeMode>(
  (ref) => switch (ref.watch(appPreferencesProvider.select((p) => p.theme))) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
  },
  name: 'themeModeProvider',
);

/// The selected server environment.
final selectedEnvironmentProvider = Provider<ServerEnvironment>((ref) {
  final id = ref.watch(appPreferencesProvider.select((p) => p.environmentId));
  return ServerEnvironment.byId(id) ?? serverEnvironments.first;
}, name: 'selectedEnvironmentProvider');

/// Result of the last backend health check (refetched when the environment
/// changes).
final serverStatusProvider = FutureProvider<Result<ServerStatus>>((ref) {
  ref.watch(selectedEnvironmentProvider);
  return ref.watch(serverStatusRepositoryProvider).check();
}, name: 'serverStatusProvider');

/// Developer switch simulating a network outage of the demo backend.
class DemoOfflineController extends Notifier<bool> {
  @override
  bool build() => ref.watch(demoBackendProvider)?.offline ?? false;

  /// Turns the simulated outage on or off.
  void set({required bool offline}) {
    final backend = ref.read(demoBackendProvider);
    if (backend == null) return;
    backend.offline = offline;
    state = offline;
  }
}

/// Whether the demo backend simulates a network outage.
final demoOfflineProvider = NotifierProvider<DemoOfflineController, bool>(
  DemoOfflineController.new,
  name: 'demoOfflineProvider',
);
