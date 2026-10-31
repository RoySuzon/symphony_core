import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../data/api_admin_repository.dart';
import '../domain/admin_entities.dart';

/// The administration repository, built on the shared `ApiClient`.
final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => ApiAdminRepository(ref.watch(apiClientProvider)),
  name: 'adminRepositoryProvider',
);

/// Every account (administrators only).
final managedUsersProvider = FutureProvider<Result<List<ManagedUser>>>((ref) {
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  if (userId == null) {
    return const Result<List<ManagedUser>>.failure(UnauthorizedFailure());
  }
  return ref.watch(adminRepositoryProvider).fetchUsers();
}, name: 'managedUsersProvider');

/// The audit log (administrators only).
final auditLogProvider = FutureProvider<Result<List<AuditEntry>>>((ref) {
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  if (userId == null) {
    return const Result<List<AuditEntry>>.failure(UnauthorizedFailure());
  }
  return ref.watch(adminRepositoryProvider).fetchAuditLog();
}, name: 'auditLogProvider');
