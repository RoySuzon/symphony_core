import 'package:symphony_core/symphony_core.dart';

import '../../../core/network/api_envelope.dart';
import '../domain/settings_entities.dart';

/// [PreferencesRepository] on top of the package's [KeyValueStorage]
/// (`secureStorageProvider`), namespaced with [PrefixedKeyValueStorage] and
/// encoded with the JSON helpers of `JsonKeyValueStorageX`.
class StoragePreferencesRepository implements PreferencesRepository {
  /// Creates the repository.
  StoragePreferencesRepository(KeyValueStorage storage)
      : _storage = PrefixedKeyValueStorage(storage, 'symphony_example.prefs.');

  static const String _key = 'app';

  final KeyValueStorage _storage;

  @override
  Future<AppPreferences> load() async {
    final json = await _storage.readJson(_key);
    if (json == null) return const AppPreferences();
    final theme = JsonReader.asString(json['theme']);
    return AppPreferences(
      theme: ThemePreference.values.firstWhere(
        (value) => value.name == theme,
        orElse: () => ThemePreference.system,
      ),
      environmentId: JsonReader.asString(json['environment']),
    );
  }

  @override
  Future<void> save(AppPreferences preferences) {
    return _storage.writeJson(_key, <String, Object?>{
      'theme': preferences.theme.name,
      'environment': preferences.environmentId,
    });
  }
}

/// [ServerStatusRepository] calling `GET /status` without credentials.
class ApiServerStatusRepository implements ServerStatusRepository {
  /// Creates the repository.
  const ApiServerStatusRepository(this._client);

  final ApiClient _client;

  @override
  Future<Result<ServerStatus>> check() => guardResult(
        () async {
          final response = await _client.get<ServerStatus>(
            '/status',
            // Public endpoint: no token, no refresh on 401.
            options: ApiRequestOptions.unauthenticated,
            decoder: (body) {
              final json = ApiEnvelope.result(body);
              return ServerStatus(
                service: JsonReader.asString(json['service']) ?? 'unknown',
                version: JsonReader.asString(json['version']) ?? '?',
                host: JsonReader.asString(json['host']) ?? '',
                environment: JsonReader.asString(json['environment']) ?? '',
                serverTime: ApiEnvelope.requireDate(json, 'server_time'),
              );
            },
          );
          return response.data;
        },
        mapError: _client.mapError,
      );
}
