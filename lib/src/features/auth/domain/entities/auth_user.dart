import 'package:flutter/foundation.dart';

import 'json_value_equality.dart';

/// The signed-in user as seen by `symphony_core`.
///
/// Only the fields needed by the package are typed. Everything else returned
/// by the backend is kept in [data] so applications can map it to their own
/// models without changing the API contract.
@immutable
class AuthUser {
  /// Creates a user.
  const AuthUser({
    required this.id,
    this.displayName,
    this.email,
    this.username,
    this.avatarUrl,
    this.roles = const <String>{},
    this.permissions = const <String>{},
    this.data = const <String, Object?>{},
  });

  /// Restores a user serialized with [toJson].
  factory AuthUser.fromJson(Map<String, Object?> json) {
    Set<String> readSet(Object? value) => value is Iterable
        ? value.map((dynamic e) => '$e').toSet()
        : const <String>{};
    final data = json['data'];
    return AuthUser(
      id: '${json['id'] ?? ''}',
      displayName: json['displayName'] as String?,
      email: json['email'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      roles: readSet(json['roles']),
      permissions: readSet(json['permissions']),
      data: data is Map
          ? Map<String, Object?>.from(data)
          : const <String, Object?>{},
    );
  }

  /// Unique identifier of the user.
  final String id;

  /// Name to display in the UI.
  final String? displayName;

  /// E-mail address, if known.
  final String? email;

  /// Login name, if different from the e-mail.
  final String? username;

  /// Avatar image URL.
  final String? avatarUrl;

  /// Roles used by role based route protection and menu visibility.
  final Set<String> roles;

  /// Permissions used by permission based navigation and menu visibility.
  final Set<String> permissions;

  /// Raw, project specific user payload.
  final Map<String, Object?> data;

  /// Serializes the user (for session persistence).
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        if (displayName != null) 'displayName': displayName,
        if (email != null) 'email': email,
        if (username != null) 'username': username,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        'roles': roles.toList(),
        'permissions': permissions.toList(),
        if (data.isNotEmpty) 'data': data,
      };

  /// Returns a copy with the given fields replaced.
  AuthUser copyWith({
    String? id,
    String? displayName,
    String? email,
    String? username,
    String? avatarUrl,
    Set<String>? roles,
    Set<String>? permissions,
    Map<String, Object?>? data,
  }) {
    return AuthUser(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      roles: roles ?? this.roles,
      permissions: permissions ?? this.permissions,
      data: data ?? this.data,
    );
  }

  /// Value equality, [data] included (compared deeply), so that a profile
  /// update changing only project specific fields is seen as a change by
  /// Riverpod listeners.
  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.displayName == displayName &&
      other.email == email &&
      other.username == username &&
      other.avatarUrl == avatarUrl &&
      setEquals(other.roles, roles) &&
      setEquals(other.permissions, permissions) &&
      jsonValueEquals(other.data, data);

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        email,
        username,
        avatarUrl,
        Object.hashAllUnordered(roles),
        Object.hashAllUnordered(permissions),
      );

  @override
  String toString() => 'AuthUser(id: $id, displayName: $displayName, '
      'roles: $roles, permissions: $permissions)';
}
