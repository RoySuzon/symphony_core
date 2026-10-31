/// Locations of the example's routes (app routes, not backend endpoints).
abstract final class AppRoutes {
  /// Session restoration screen.
  static const String splash = '/splash';

  /// Sign-in screen.
  static const String login = '/login';

  /// Registration screen.
  static const String register = '/register';

  /// Password recovery screen.
  static const String forgotPassword = '/forgot-password';

  /// Shown when a signed-in user lacks a role or permission.
  static const String unauthorized = '/unauthorized';

  /// Dashboard (home).
  static const String home = '/';

  /// Orders list (permission `orders.read`).
  static const String orders = '/orders';

  /// Reports (permission `reports.view`).
  static const String reports = '/reports';

  /// Administration (role `admin`).
  static const String admin = '/admin';

  /// Administration › users.
  static const String adminUsers = '/admin/users';

  /// Administration › audit log.
  static const String auditLog = '/admin/audit-log';

  /// File transfers.
  static const String files = '/files';

  /// Settings.
  static const String settings = '/settings';

  /// Profile of the signed-in user.
  static const String profile = '/profile';

  /// UI components showcase.
  static const String components = '/components';

  /// Order [id] (nested in [orders]).
  static String orderDetail(String id) => '$orders/${Uri.encodeComponent(id)}';
}
