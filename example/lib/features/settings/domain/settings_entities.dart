import 'package:flutter/foundation.dart';
import 'package:symphony_core/symphony_core.dart';

/// A backend environment the app can switch to at runtime.
@immutable
class ServerEnvironment {
  /// Creates an environment.
  const ServerEnvironment({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.description,
  });

  /// Stable id (persisted in the preferences).
  final String id;

  /// Display name.
  final String label;

  /// Base URL passed to `ApiClient.updateBaseUrl`.
  final String baseUrl;

  /// Short description.
  final String description;

  /// The environment with [id], if any.
  static ServerEnvironment? byId(String? id) {
    for (final environment in serverEnvironments) {
      if (environment.id == id) return environment;
    }
    return null;
  }
}

/// Environments offered by the settings screen. The demo backend answers on
/// every host, so all of them work offline.
const List<ServerEnvironment> serverEnvironments = <ServerEnvironment>[
  ServerEnvironment(
    id: 'production',
    label: 'Production',
    baseUrl: 'https://api.example.com',
    description: 'Default base URL from SymphonyConfig',
  ),
  ServerEnvironment(
    id: 'staging',
    label: 'Staging',
    baseUrl: 'https://staging.api.example.com',
    description: 'Pre-release servers',
  ),
  ServerEnvironment(
    id: 'local',
    label: 'Local',
    baseUrl: 'http://localhost:8080',
    description: 'A backend running on your machine',
  ),
];

/// Theme selected by the user.
enum ThemePreference {
  /// Follow the platform.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// User preferences of the example app.
@immutable
class AppPreferences {
  /// Creates preferences.
  const AppPreferences({
    this.theme = ThemePreference.system,
    this.environmentId,
  });

  /// Selected theme.
  final ThemePreference theme;

  /// Selected [ServerEnvironment] id (`null`: the configured base URL).
  final String? environmentId;

  /// A copy with the given fields replaced.
  AppPreferences copyWith({ThemePreference? theme, String? environmentId}) =>
      AppPreferences(
        theme: theme ?? this.theme,
        environmentId: environmentId ?? this.environmentId,
      );

  @override
  bool operator ==(Object other) =>
      other is AppPreferences &&
      other.theme == theme &&
      other.environmentId == environmentId;

  @override
  int get hashCode => Object.hash(theme, environmentId);
}

/// Persists [AppPreferences].
abstract interface class PreferencesRepository {
  /// The stored preferences (defaults when nothing is stored).
  Future<AppPreferences> load();

  /// Stores [preferences].
  Future<void> save(AppPreferences preferences);
}

/// Health information returned by the backend.
@immutable
class ServerStatus {
  /// Creates a status.
  const ServerStatus({
    required this.service,
    required this.version,
    required this.host,
    required this.environment,
    required this.serverTime,
  });

  /// Service name.
  final String service;

  /// Service version.
  final String version;

  /// Host that answered (follows `ApiClient.updateBaseUrl`).
  final String host;

  /// Environment reported by the server.
  final String environment;

  /// Server clock.
  final DateTime serverTime;
}

/// Checks that the backend is reachable.
abstract interface class ServerStatusRepository {
  /// Calls the public status endpoint.
  Future<Result<ServerStatus>> check();
}
