/// Dashboard: permission-aware, nested module grid.
///
/// * [DashboardItem] describes a module (icon, label, route, access, nested
///   children) and [DashboardMenu] holds the pure menu logic (filtering,
///   lookups, breadcrumbs).
/// * [SymphonyDashboard] renders the menu for the current user, with inline
///   or page submenus and GoRouter navigation.
/// * [dashboardItemsProvider] supplies the app's menu and
///   [visibleDashboardItemsProvider] filters it for the current user.
library;

export 'domain/dashboard_item.dart';
export 'domain/dashboard_menu.dart';
export 'presentation/dashboard_grid.dart';
export 'presentation/dashboard_navigation.dart';
export 'presentation/dashboard_providers.dart';
export 'presentation/dashboard_tile.dart';
export 'presentation/symphony_dashboard.dart';
export 'presentation/symphony_dashboard_controller.dart';
export 'presentation/symphony_dashboard_submenu_page.dart';
