import 'package:flutter/foundation.dart';

import 'access_requirement.dart';
import 'auth_status.dart';

/// Snapshot of who the current user is allowed to be: authentication status,
/// roles and permissions.
///
/// It decouples routing guards and dashboard visibility from the concrete
/// authentication implementation: anything that can produce an
/// [AccessContext] can drive them.
@immutable
class AccessContext {
  /// Creates an access context.
  const AccessContext({
    this.status = AuthStatus.unknown,
    this.roles = const <String>{},
    this.permissions = const <String>{},
    this.attributes = const <String, Object?>{},
  });

  /// Status before the session was restored.
  static const AccessContext unknown = AccessContext();

  /// Context of a signed-out user.
  static const AccessContext unauthenticated =
      AccessContext(status: AuthStatus.unauthenticated);

  /// Authentication status.
  final AuthStatus status;

  /// Roles granted to the user, e.g. `{'admin'}`.
  final Set<String> roles;

  /// Fine grained permissions granted to the user, e.g. `{'orders.read'}`.
  final Set<String> permissions;

  /// Additional project specific attributes usable by custom predicates.
  final Map<String, Object?> attributes;

  /// Whether the user is signed in.
  bool get isAuthenticated => status == AuthStatus.authenticated;

  /// Whether the session is still being restored.
  bool get isUnknown => status == AuthStatus.unknown;

  /// Whether the user has [role].
  bool hasRole(String role) => roles.contains(role);

  /// Whether the user has at least one of [anyOf]. Empty input returns true.
  bool hasAnyRole(Iterable<String> anyOf) =>
      anyOf.isEmpty || anyOf.any(roles.contains);

  /// Whether the user has every role in [allOf].
  bool hasAllRoles(Iterable<String> allOf) => allOf.every(roles.contains);

  /// Whether the user has [permission].
  bool hasPermission(String permission) => permissions.contains(permission);

  /// Whether the user has at least one of [anyOf]. Empty input returns true.
  bool hasAnyPermission(Iterable<String> anyOf) =>
      anyOf.isEmpty || anyOf.any(permissions.contains);

  /// Whether the user has every permission in [allOf].
  bool hasAllPermissions(Iterable<String> allOf) =>
      allOf.every(permissions.contains);

  /// Whether this context satisfies [requirement].
  bool satisfies(AccessRequirement requirement) =>
      requirement.isSatisfiedBy(this);

  /// Returns a copy with the given fields replaced.
  AccessContext copyWith({
    AuthStatus? status,
    Set<String>? roles,
    Set<String>? permissions,
    Map<String, Object?>? attributes,
  }) {
    return AccessContext(
      status: status ?? this.status,
      roles: roles ?? this.roles,
      permissions: permissions ?? this.permissions,
      attributes: attributes ?? this.attributes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AccessContext &&
      other.status == status &&
      setEquals(other.roles, roles) &&
      setEquals(other.permissions, permissions) &&
      mapEquals(other.attributes, attributes);

  @override
  int get hashCode => Object.hash(
        status,
        Object.hashAllUnordered(roles),
        Object.hashAllUnordered(permissions),
        Object.hashAllUnordered(attributes.keys),
      );

  @override
  String toString() => 'AccessContext(status: ${status.name}, '
      'roles: $roles, permissions: $permissions)';
}
