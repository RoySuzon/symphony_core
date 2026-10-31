import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';

/// The signed-in user: identity, roles, permissions, session and
/// [AccessGate] examples.
class ProfilePage extends ConsumerWidget {
  /// Creates the page.
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final access = ref.watch(accessContextProvider);
    final session = ref.watch(authControllerProvider).session;
    final theme = Theme.of(context);
    if (user == null) {
      return const AppPage(
        title: 'Profile',
        body: SymphonyEmptyState(
          title: 'Not signed in',
          icon: Icons.person_off_outlined,
        ),
      );
    }
    final department = JsonReader.asString(user.data['department']);
    final memberSince =
        JsonReader.asDateTime(user.data['member_since'], isUtc: true);
    final expiresAt = session?.tokens.expiresAt;
    // `ref.watchCanAccess` is the imperative counterpart of AccessGate.
    final canManageUsers = ref.watchCanAccess(
      const AccessRequirement(permissions: <String>{'users.manage'}),
    );

    return AppPage(
      title: 'Profile',
      scrollable: true,
      maxWidth: 720,
      actions: <Widget>[
        IconButton(
          tooltip: 'Reload the profile (GET /auth/me)',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref
              .read(authControllerProvider.notifier)
              .restoreSession(force: true),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(SymphonySpacing.xl),
              child: Row(
                children: <Widget>[
                  UserAvatar(name: user.displayName, radius: 32),
                  const SizedBox(width: SymphonySpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          user.displayName ?? user.id,
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(user.email ?? ''),
                        if (department != null)
                          Text(department, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SymphonySpacing.lg),
          SectionCard(
            title: 'Access',
            subtitle: 'Mapped from the backend response by AuthResponseMapping',
            icon: Icons.verified_user_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Roles', style: theme.textTheme.labelLarge),
                const SizedBox(height: SymphonySpacing.sm),
                _Tags(
                  values: access.roles,
                  icon: Icons.badge_outlined,
                  empty: 'No role',
                ),
                const SizedBox(height: SymphonySpacing.lg),
                Text('Permissions', style: theme.textTheme.labelLarge),
                const SizedBox(height: SymphonySpacing.sm),
                _Tags(
                  values: access.permissions,
                  icon: Icons.key_outlined,
                  empty: 'No permission',
                ),
              ],
            ),
          ),
          const SizedBox(height: SymphonySpacing.lg),
          SectionCard(
            title: 'AccessGate examples',
            subtitle: 'Widgets shown or hidden from the AccessContext',
            icon: Icons.visibility_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _GateExample(
                  rule: 'roles: {"admin"}',
                  requirement: AccessRequirement(roles: <String>{'admin'}),
                ),
                const _GateExample(
                  rule: 'permissions: {"orders.read"}',
                  requirement: AccessRequirement(
                    permissions: <String>{'orders.read'},
                  ),
                ),
                const _GateExample(
                  rule: 'permissions: {"reports.view", "reports.export"}',
                  requirement: AccessRequirement(
                    permissions: <String>{'reports.view', 'reports.export'},
                  ),
                ),
                const _GateExample(
                  rule: 'roles: {"staff", "admin"} (any)',
                  requirement: AccessRequirement(
                    roles: <String>{'staff', 'admin'},
                  ),
                ),
                _GateExample(
                  rule: 'predicate: department == "Operations"',
                  requirement: AccessRequirement(
                    predicate: (context) =>
                        context.attributes['department'] == 'Operations',
                  ),
                ),
                const SizedBox(height: SymphonySpacing.md),
                SymphonyButton(
                  label: canManageUsers
                      ? 'Manage users'
                      : 'Manage users (needs users.manage)',
                  icon: Icons.manage_accounts_outlined,
                  variant: SymphonyButtonVariant.outlined,
                  onPressed: canManageUsers
                      ? () => SymphonySnackbar.info(
                            context,
                            'ref.watchCanAccess enabled this button.',
                          )
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: SymphonySpacing.lg),
          SectionCard(
            title: 'Session',
            icon: Icons.key_outlined,
            child: Column(
              children: <Widget>[
                InfoRow(label: 'User id', value: user.id),
                if (memberSince != null)
                  InfoRow(
                    label: 'Member since',
                    value: Formatters.date(memberSince),
                  ),
                InfoRow(
                  label: 'Token type',
                  value: session?.tokens.tokenType ?? 'Bearer',
                ),
                if (expiresAt != null)
                  InfoRow(
                    label: 'Access token expires',
                    value: '${Formatters.dateTime(expiresAt)} '
                        '(${Formatters.countdown(expiresAt.difference(DateTime.now()))})',
                  ),
                InfoRow(
                  label: 'Refresh token',
                  value: session?.tokens.canRefresh ?? false
                      ? 'Available (masked)'
                      : 'None',
                ),
              ],
            ),
          ),
          const SizedBox(height: SymphonySpacing.xl),
        ],
      ),
    );
  }
}

class _Tags extends StatelessWidget {
  const _Tags({required this.values, required this.icon, required this.empty});

  final Set<String> values;
  final IconData icon;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Text(empty, style: Theme.of(context).textTheme.bodySmall);
    }
    final sorted = values.toList()..sort();
    return Wrap(
      spacing: SymphonySpacing.sm,
      runSpacing: SymphonySpacing.sm,
      children: <Widget>[
        for (final value in sorted) TagChip(label: value, icon: icon),
      ],
    );
  }
}

class _GateExample extends StatelessWidget {
  const _GateExample({required this.rule, required this.requirement});

  final String rule;
  final AccessRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final colors = SymphonyColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(rule),
      trailing: AccessGate(
        requirement: requirement,
        fallback: TagChip(
          label: 'hidden',
          icon: Icons.visibility_off_outlined,
          color: scheme.error,
        ),
        child: TagChip(
          label: 'visible',
          icon: Icons.visibility_outlined,
          color: colors.success,
        ),
      ),
    );
  }
}
