import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/async_result_view.dart';
import '../domain/admin_entities.dart';
import 'admin_providers.dart';

/// Administration overview (role `admin`). Its sub-pages are nested routes
/// (`/admin/users`, `/admin/audit-log`) protected by the same guard.
class AdminPage extends ConsumerWidget {
  /// Creates the page.
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(managedUsersProvider);
    final audit = ref.watch(auditLogProvider);
    String count<T>(AsyncValue<Result<List<T>>> value, String noun) =>
        value.when(
          data:
              (result) => result.when(
                success: (items) => '${items.length} $noun',
                failure: (failure) => failure.message,
              ),
          loading: () => 'Loading…',
          error: (error, stackTrace) => 'Unavailable',
        );

    return AppPage(
      title: 'Administration',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _AdminBanner(),
          const SizedBox(height: SymphonySpacing.lg),
          _AdminLinkCard(
            icon: Icons.manage_accounts_outlined,
            title: 'Users',
            subtitle: count(users, 'accounts'),
            onTap: () => context.go(AppRoutes.adminUsers),
          ),
          const SizedBox(height: SymphonySpacing.md),
          _AdminLinkCard(
            icon: Icons.policy_outlined,
            title: 'Audit log',
            subtitle: count(audit, 'events'),
            onTap: () => context.go(AppRoutes.auditLog),
          ),
        ],
      ),
    );
  }
}

class _AdminBanner extends StatelessWidget {
  const _AdminBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(SymphonySpacing.lg),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: SymphonyRadius.of(context).mediumBorderRadius,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.shield_outlined, color: scheme.onTertiaryContainer),
          const SizedBox(width: SymphonySpacing.md),
          Expanded(
            child: Text(
              'This area is protected by GuardedRoute(access: '
              'AccessRequirement(roles: {"admin"})). Staff and viewers who '
              'open /admin are redirected to the unauthorized page.',
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminLinkCard extends StatelessWidget {
  const _AdminLinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.all(SymphonySpacing.md),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Accounts list (nested route `/admin/users`).
class AdminUsersPage extends ConsumerWidget {
  /// Creates the page.
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: 'Users',
      body: AsyncResultView<List<ManagedUser>>(
        value: ref.watch(managedUsersProvider),
        onRetry: () => ref.invalidate(managedUsersProvider),
        isEmpty: (users) => users.isEmpty,
        emptyBuilder:
            (context) => const SymphonyEmptyState(
              title: 'No users',
              icon: Icons.person_off_outlined,
            ),
        builder:
            (context, users) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(managedUsersProvider);
                await ref.read(managedUsersProvider.future);
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: users.length,
                separatorBuilder:
                    (context, index) =>
                        const SizedBox(height: SymphonySpacing.sm),
                itemBuilder: (context, index) => _UserCard(user: users[index]),
              ),
            ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final ManagedUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastLogin = user.lastLoginAt;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(SymphonySpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            UserAvatar(name: user.name),
            const SizedBox(width: SymphonySpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(user.name, style: theme.textTheme.titleSmall),
                  Text('${user.email} · ${user.department}'),
                  const SizedBox(height: SymphonySpacing.sm),
                  Wrap(
                    spacing: SymphonySpacing.xs,
                    runSpacing: SymphonySpacing.xs,
                    children: <Widget>[
                      for (final role in user.roles)
                        TagChip(label: role, icon: Icons.badge_outlined),
                      if (!user.isActive)
                        TagChip(
                          label: 'unverified',
                          color: theme.colorScheme.error,
                        ),
                      TagChip(
                        label: '${user.permissions.length} permissions',
                        icon: Icons.key_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: SymphonySpacing.xs),
                  Text(
                    lastLogin == null
                        ? 'Never signed in'
                        : 'Last sign-in ${Formatters.dateTime(lastLogin)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Audit log (nested route `/admin/audit-log`). The demo backend records
/// real events: sign-ins, token refreshes, uploads, exports...
class AuditLogPage extends ConsumerWidget {
  /// Creates the page.
  const AuditLogPage({super.key});

  static IconData _iconFor(AuditEntry entry) => switch (entry.category) {
    'auth' => Icons.login,
    'files' => Icons.upload_file,
    'orders' => Icons.receipt_long_outlined,
    'reports' => Icons.bar_chart,
    'users' => Icons.manage_accounts_outlined,
    _ => Icons.info_outline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: 'Audit log',
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(auditLogProvider),
        ),
      ],
      body: AsyncResultView<List<AuditEntry>>(
        value: ref.watch(auditLogProvider),
        onRetry: () => ref.invalidate(auditLogProvider),
        isEmpty: (entries) => entries.isEmpty,
        emptyBuilder:
            (context) => const SymphonyEmptyState(
              title: 'Nothing happened yet',
              icon: Icons.history_toggle_off,
            ),
        builder:
            (context, entries) => ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return ListTile(
                  leading: Icon(_iconFor(entry)),
                  title: Text(entry.summary),
                  subtitle: Text('${entry.actor} · ${entry.action}'),
                  trailing: Text(Formatters.dateTime(entry.at)),
                );
              },
            ),
      ),
    );
  }
}
