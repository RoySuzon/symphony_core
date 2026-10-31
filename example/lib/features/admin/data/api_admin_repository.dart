import 'package:symphony_core/symphony_core.dart';

import '../../../core/network/api_envelope.dart';
import '../domain/admin_entities.dart';

/// [AdminRepository] backed by the package's [ApiClient].
class ApiAdminRepository implements AdminRepository {
  /// Creates the repository.
  const ApiAdminRepository(this._client);

  final ApiClient _client;

  @override
  Future<Result<List<ManagedUser>>> fetchUsers() => guardResult(
        () async {
          final response = await _client.get<List<ManagedUser>>(
            '/admin/users',
            decoder: (body) => <ManagedUser>[
              for (final item in ApiEnvelope.list(body, 'items'))
                _user(JsonReader.asMap(item) ?? const <String, Object?>{}),
            ],
          );
          return response.data;
        },
        mapError: _client.mapError,
      );

  @override
  Future<Result<List<AuditEntry>>> fetchAuditLog() => guardResult(
        () async {
          final response = await _client.get<List<AuditEntry>>(
            '/admin/audit-log',
            decoder: (body) => <AuditEntry>[
              for (final item in ApiEnvelope.list(body, 'items'))
                _entry(JsonReader.asMap(item) ?? const <String, Object?>{}),
            ],
          );
          return response.data;
        },
        mapError: _client.mapError,
      );

  static ManagedUser _user(Map<String, Object?> json) => ManagedUser(
        id: ApiEnvelope.requireString(json, 'id'),
        name: JsonReader.asString(json['name']) ?? '',
        email: ApiEnvelope.requireString(json, 'email'),
        roles: (JsonReader.asStringSet(json['roles']) ?? const <String>{})
            .toList(),
        permissions:
            (JsonReader.asStringSet(json['permissions']) ?? const <String>{})
                .toList(),
        department: JsonReader.asString(json['department']) ?? '',
        isActive: JsonReader.asString(json['status']) == 'active',
        lastLoginAt: JsonReader.asDateTime(json['last_login_at'], isUtc: true)
            ?.toLocal(),
      );

  static AuditEntry _entry(Map<String, Object?> json) => AuditEntry(
        id: ApiEnvelope.requireString(json, 'id'),
        at: ApiEnvelope.requireDate(json, 'at'),
        actor: JsonReader.asString(json['actor']) ?? 'unknown',
        action: JsonReader.asString(json['action']) ?? 'unknown',
        summary: JsonReader.asString(json['summary']) ?? '',
      );
}
