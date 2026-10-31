import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/access_context.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/dashboard_item.dart';
import '../domain/dashboard_menu.dart';

/// The complete, unfiltered dashboard menu of the application.
///
/// Defaults to an empty menu. Applications supply their modules by
/// overriding it, either with a fixed list:
///
/// ```dart
/// ProviderScope(
///   overrides: [dashboardItemsProvider.overrideWithValue(appModules)],
///   child: const MyApp(),
/// );
/// ```
///
/// or with a function that watches other providers (feature flags, counters
/// displayed as badges...):
///
/// ```dart
/// dashboardItemsProvider.overrideWith((ref) => buildModules(ref.watch(flagsProvider)));
/// ```
///
/// Override it in the root `ProviderScope` (or the container created by
/// `SymphonyCore`) so that [visibleDashboardItemsProvider] sees the value.
final dashboardItemsProvider = Provider<List<DashboardItem>>(
  (ref) => const <DashboardItem>[],
  name: 'dashboardItemsProvider',
);

/// [dashboardItemsProvider] filtered for the current user, as described by
/// [accessContextProvider] (see [DashboardMenu.filterVisibleItems]).
///
/// It updates automatically when the user signs in or out, or when their
/// roles or permissions change.
final visibleDashboardItemsProvider = Provider<List<DashboardItem>>((ref) {
  final items = ref.watch(dashboardItemsProvider);
  assert(DashboardMenu.debugAssertUniqueIds(items));
  return DashboardMenu.filterVisibleItems(
    items,
    ref.watch(accessContextProvider),
  );
}, name: 'visibleDashboardItemsProvider');

/// Watches the menu items that the current user may see, from inside a
/// widget's `build` method.
///
/// [items] replaces [dashboardItemsProvider] and [accessContext] replaces
/// [accessContextProvider] when given. When both are `null` the shared
/// [visibleDashboardItemsProvider] is used. The widget rebuilds whenever a
/// watched provider changes.
///
/// Useful to build additional menus (a drawer, a search) that must show
/// exactly the same entries as the dashboard.
List<DashboardItem> watchVisibleDashboardItems(
  WidgetRef ref, {
  List<DashboardItem>? items,
  AccessContext? accessContext,
}) {
  if (items == null && accessContext == null) {
    return ref.watch(visibleDashboardItemsProvider);
  }
  // Explicit types keep `ref.watch` from inferring a nullable result from the
  // `??` context.
  final List<DashboardItem> menu = items ?? ref.watch(dashboardItemsProvider);
  assert(DashboardMenu.debugAssertUniqueIds(menu));
  final AccessContext access =
      accessContext ?? ref.watch(accessContextProvider);
  return DashboardMenu.filterVisibleItems(menu, access);
}
