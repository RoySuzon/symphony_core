import 'package:flutter/foundation.dart';
import 'package:symphony_core/symphony_core.dart';

/// A user account as seen by administrators.
@immutable
class ManagedUser {
  /// Creates a user.
  const ManagedUser({
    required this.id,
    required this.name,
    required this.email,
    required this.roles,
    required this.permissions,
    required this.department,
    required this.isActive,
    this.lastLoginAt,
  });

  /// Account id.
  final String id;

  /// Full name.
  final String name;

  /// E-mail.
  final String email;

  /// Roles.
  final List<String> roles;

  /// Permissions.
  final List<String> permissions;

  /// Department.
  final String department;

  /// Whether the account is active (verified).
  final bool isActive;

  /// Last sign-in, if any.
  final DateTime? lastLoginAt;
}

/// An entry of the audit log.
@immutable
class AuditEntry {
  /// Creates an entry.
  const AuditEntry({
    required this.id,
    required this.at,
    required this.actor,
    required this.action,
    required this.summary,
  });

  /// Entry id.
  final String id;

  /// When it happened.
  final DateTime at;

  /// Who did it.
  final String actor;

  /// Dotted action name (`auth.login`, `files.upload`...).
  final String action;

  /// Description.
  final String summary;

  /// First segment of [action] (`auth`, `files`...).
  String get category => action.split('.').first;
}

/// Administration data (role `admin`).
abstract interface class AdminRepository {
  /// Every account.
  Future<Result<List<ManagedUser>>> fetchUsers();

  /// The audit log, newest first.
  Future<Result<List<AuditEntry>>> fetchAuditLog();
}
