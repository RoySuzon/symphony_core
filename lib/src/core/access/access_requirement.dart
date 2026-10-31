import 'package:flutter/foundation.dart';

import 'access_context.dart';

/// How a set of roles or permissions must be matched.
enum MatchMode {
  /// At least one entry must be granted.
  any,

  /// Every entry must be granted.
  all,
}

/// Signature of a custom access rule.
typedef AccessPredicate = bool Function(AccessContext context);

/// Declarative access rule used by route guards and dashboard items.
///
/// ```dart
/// const AccessRequirement.public();                       // anyone
/// const AccessRequirement();                              // signed-in users
/// const AccessRequirement(roles: {'admin'});              // admins only
/// const AccessRequirement(
///   permissions: {'orders.read', 'orders.write'},         // both permissions
/// );
/// ```
@immutable
class AccessRequirement {
  /// Creates a requirement. By default the user must be authenticated.
  const AccessRequirement({
    this.requiresAuth = true,
    this.roles = const <String>{},
    this.permissions = const <String>{},
    this.roleMatch = MatchMode.any,
    this.permissionMatch = MatchMode.all,
    this.predicate,
  });

  /// A requirement satisfied by everyone, signed in or not.
  const AccessRequirement.public()
    : requiresAuth = false,
      roles = const <String>{},
      permissions = const <String>{},
      roleMatch = MatchMode.any,
      permissionMatch = MatchMode.all,
      predicate = null;

  /// Anyone, signed in or not.
  static const AccessRequirement none = AccessRequirement.public();

  /// Any signed-in user.
  static const AccessRequirement authenticated = AccessRequirement();

  /// Whether the user must be signed in.
  final bool requiresAuth;

  /// Roles checked according to [roleMatch]. Empty means no role check.
  final Set<String> roles;

  /// Permissions checked according to [permissionMatch]. Empty means no
  /// permission check.
  final Set<String> permissions;

  /// Matching mode for [roles]. Defaults to [MatchMode.any].
  final MatchMode roleMatch;

  /// Matching mode for [permissions]. Defaults to [MatchMode.all].
  final MatchMode permissionMatch;

  /// Optional custom rule evaluated after the declarative checks.
  final AccessPredicate? predicate;

  /// Whether the requirement does not restrict access at all.
  bool get isPublic =>
      !requiresAuth &&
      roles.isEmpty &&
      permissions.isEmpty &&
      predicate == null;

  /// Evaluates the requirement against [context].
  bool isSatisfiedBy(AccessContext context) {
    if (isPublic) return true;
    if (requiresAuth && !context.isAuthenticated) return false;
    if (roles.isNotEmpty) {
      final ok =
          roleMatch == MatchMode.any
              ? context.hasAnyRole(roles)
              : context.hasAllRoles(roles);
      if (!ok) return false;
    }
    if (permissions.isNotEmpty) {
      final ok =
          permissionMatch == MatchMode.any
              ? context.hasAnyPermission(permissions)
              : context.hasAllPermissions(permissions);
      if (!ok) return false;
    }
    final custom = predicate;
    if (custom != null && !custom(context)) return false;
    return true;
  }

  /// Returns a copy with the given fields replaced.
  AccessRequirement copyWith({
    bool? requiresAuth,
    Set<String>? roles,
    Set<String>? permissions,
    MatchMode? roleMatch,
    MatchMode? permissionMatch,
    AccessPredicate? predicate,
  }) {
    return AccessRequirement(
      requiresAuth: requiresAuth ?? this.requiresAuth,
      roles: roles ?? this.roles,
      permissions: permissions ?? this.permissions,
      roleMatch: roleMatch ?? this.roleMatch,
      permissionMatch: permissionMatch ?? this.permissionMatch,
      predicate: predicate ?? this.predicate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AccessRequirement &&
      other.requiresAuth == requiresAuth &&
      setEquals(other.roles, roles) &&
      setEquals(other.permissions, permissions) &&
      other.roleMatch == roleMatch &&
      other.permissionMatch == permissionMatch &&
      other.predicate == predicate;

  @override
  int get hashCode => Object.hash(
    requiresAuth,
    Object.hashAllUnordered(roles),
    Object.hashAllUnordered(permissions),
    roleMatch,
    permissionMatch,
    predicate,
  );

  @override
  String toString() =>
      'AccessRequirement(requiresAuth: $requiresAuth, '
      'roles: $roles (${roleMatch.name}), '
      'permissions: $permissions (${permissionMatch.name}))';
}
