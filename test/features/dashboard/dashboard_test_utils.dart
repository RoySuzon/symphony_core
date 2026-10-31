import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/access/access_context.dart';
import 'package:symphony_core/src/core/access/access_requirement.dart';
import 'package:symphony_core/src/core/access/auth_status.dart';
import 'package:symphony_core/src/features/auth/presentation/providers/auth_providers.dart';
import 'package:symphony_core/src/features/dashboard/dashboard.dart';

/// Access of a signed-in user.
AccessContext signedIn({
  Set<String> roles = const <String>{},
  Set<String> permissions = const <String>{},
}) {
  return AccessContext(
    status: AuthStatus.authenticated,
    roles: roles,
    permissions: permissions,
  );
}

/// Mutable access used to simulate sign-in, sign-out and permission changes.
class TestAccessNotifier extends Notifier<AccessContext> {
  @override
  AccessContext build() => AccessContext.unauthenticated;

  /// Replaces the current access.
  void change(AccessContext value) => state = value;
}

/// Source of truth for `accessContextProvider` in tests.
final testAccessProvider = NotifierProvider<TestAccessNotifier, AccessContext>(
  TestAccessNotifier.new,
);

/// Creates a container whose `accessContextProvider` follows
/// [testAccessProvider], starting with [access]. [menu] overrides
/// `dashboardItemsProvider` when given.
///
/// The override list type is inferred on purpose: the `Override` type is not
/// exported by `flutter_riverpod.dart` in Riverpod 3.
ProviderContainer createAccessContainer({
  AccessContext access = AccessContext.unauthenticated,
  List<DashboardItem>? menu,
}) {
  final container = ProviderContainer(
    overrides: [
      accessContextProvider.overrideWith(
        (ref) => ref.watch(testAccessProvider),
      ),
      if (menu != null) dashboardItemsProvider.overrideWithValue(menu),
    ],
  );
  addTearDown(container.dispose);
  container.read(testAccessProvider.notifier).change(access);
  return container;
}

/// Changes the access of [container] (see [createAccessContainer]).
void changeAccess(ProviderContainer container, AccessContext access) {
  container.read(testAccessProvider.notifier).change(access);
}

/// Pumps [child] inside a `MaterialApp` scaffold bound to [container].
Future<void> pumpInApp(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Finds the dashboard tile displaying [label].
Finder tile(String label) => find.widgetWithText(SymphonyDashboardTile, label);

/// A three level menu exercising roles, permissions and nested groups.
///
/// * `orders`, `help`: public leaves.
/// * `sales` (roles sales|admin) > `sales.invoices`, `sales.reports`
///   (permission reports.read) > `sales.reports.daily`,
///   `sales.reports.monthly` (permission reports.monthly).
/// * `admin` (role admin): leaf.
const List<DashboardItem> sampleMenu = <DashboardItem>[
  DashboardItem(
    id: 'orders',
    label: 'Orders',
    icon: Icons.receipt_long,
    route: '/orders',
  ),
  DashboardItem(
    id: 'sales',
    label: 'Sales',
    icon: Icons.point_of_sale,
    access: AccessRequirement(roles: <String>{'sales', 'admin'}),
    children: <DashboardItem>[
      DashboardItem(
        id: 'sales.invoices',
        label: 'Invoices',
        icon: Icons.request_quote,
        route: '/invoices',
      ),
      DashboardItem(
        id: 'sales.reports',
        label: 'Reports',
        icon: Icons.bar_chart,
        access: AccessRequirement(permissions: <String>{'reports.read'}),
        children: <DashboardItem>[
          DashboardItem(
            id: 'sales.reports.daily',
            label: 'Daily',
            route: '/reports/daily',
          ),
          DashboardItem(
            id: 'sales.reports.monthly',
            label: 'Monthly',
            route: '/reports/monthly',
            access: AccessRequirement(permissions: <String>{'reports.monthly'}),
          ),
        ],
      ),
    ],
  ),
  DashboardItem(
    id: 'admin',
    label: 'Admin',
    icon: Icons.admin_panel_settings,
    route: '/admin',
    access: AccessRequirement(roles: <String>{'admin'}),
  ),
  DashboardItem(
    id: 'help',
    label: 'Help',
    icon: Icons.help_outline,
    route: '/help',
  ),
];

/// A sales user allowed to read reports (but not monthly ones).
final AccessContext salesUser = signedIn(
  roles: <String>{'sales'},
  permissions: <String>{'reports.read'},
);
