import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../settings/presentation/settings_providers.dart';
import 'dashboard_modules.dart';

/// Home screen: the permission-aware [SymphonyDashboard].
class HomePage extends ConsumerWidget {
  /// Creates the page.
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: <Widget>[
          IconButton(
            tooltip: 'API inspector',
            icon: const Icon(Icons.manage_search_rounded),
            onPressed: () => showApiInspector(context),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SymphonySpacing.sm),
            child: Tooltip(
              message: 'Profile',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.go(AppRoutes.profile),
                child: UserAvatar(name: user?.displayName, radius: 18),
              ),
            ),
          ),
        ],
      ),
      drawer: const AppNavigationDrawer(),
      body: SafeArea(
        child: SymphonyContentConstraint(
          maxWidth: 1100,
          child: SymphonyDashboard(
            items: ref.watch(dashboardModulesProvider),
            header: const WelcomeHeader(),
            title: const Text('Modules'),
            maxCrossAxisExtent: 200,
            emptyTitle: 'No module available',
            emptyMessage: 'Your account has no access to any module.',
          ),
        ),
      ),
    );
  }
}

/// Greeting, roles and current environment, above the dashboard grid.
class WelcomeHeader extends ConsumerWidget {
  /// Creates the header.
  const WelcomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final environment = ref.watch(selectedEnvironmentProvider);
    final theme = Theme.of(context);
    final roles = user?.roles.toList() ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(SymphonySpacing.lg),
          child: Row(
            children: <Widget>[
              UserAvatar(name: user?.displayName, radius: 26),
              const SizedBox(width: SymphonySpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Hello, ${user?.displayName ?? 'there'}',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: SymphonySpacing.xs),
                    Wrap(
                      spacing: SymphonySpacing.xs,
                      runSpacing: SymphonySpacing.xs,
                      children: <Widget>[
                        for (final role in roles)
                          TagChip(label: role, icon: Icons.badge_outlined),
                        TagChip(
                          label: '${user?.permissions.length ?? 0} permissions',
                          icon: Icons.key_outlined,
                        ),
                        TagChip(
                          label: environment.label,
                          icon: Icons.dns_outlined,
                          color: theme.colorScheme.tertiary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A navigation drawer built from the same permission-filtered menu as the
/// dashboard (`watchVisibleDashboardItems`).
class AppNavigationDrawer extends ConsumerWidget {
  /// Creates the drawer.
  const AppNavigationDrawer({super.key});

  void _open(BuildContext context, DashboardItem item) {
    Navigator.of(context).pop();
    final onTap = item.onTap;
    if (onTap != null) {
      onTap(context);
    } else {
      navigateToDashboardItem(context, item);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = watchVisibleDashboardItems(
      ref,
      items: ref.watch(dashboardModulesProvider),
    );
    final entries =
        DashboardMenu.flatten(
          visible,
        ).where((item) => item.isLeaf && item.hasAction).toList();
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(SymphonySpacing.lg),
              child: Row(
                children: <Widget>[
                  const AppLogo(size: 40),
                  const SizedBox(width: SymphonySpacing.md),
                  Text('Symphony', style: theme.textTheme.titleLarge),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Dashboard'),
              onTap: () {
                Navigator.of(context).pop();
                context.go(AppRoutes.home);
              },
            ),
            const Divider(),
            for (final item in entries)
              ListTile(
                leading:
                    item.icon == null
                        ? const Icon(Icons.extension_outlined)
                        : Icon(item.icon),
                title: Text(item.label),
                subtitle:
                    item.description == null ? null : Text(item.description!),
                onTap: () => _open(context, item),
              ),
          ],
        ),
      ),
    );
  }
}
