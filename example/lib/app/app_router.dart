import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/symphony_core.dart';

import '../core/routing/app_routes.dart';
import '../features/admin/presentation/admin_pages.dart';
import '../features/auth/presentation/auth_pages.dart';
import '../features/components/presentation/components_page.dart';
import '../features/files/presentation/files_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/orders/presentation/pages/order_detail_page.dart';
import '../features/orders/presentation/pages/orders_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/reports/presentation/reports_page.dart';
import '../features/settings/presentation/settings_page.dart';
import 'app_startup.dart';

/// The application router.
///
/// [SymphonyRouter.create] wires GoRouter to the authentication state:
/// while the session is restored every location waits on the splash
/// screen; signed-out users opening a protected page go to the login screen
/// and come back after signing in; signed-in users never see the guest
/// pages; users lacking a role or permission land on the unauthorized page.
///
/// Module routes are nested below the dashboard (`/`), so each module page
/// has a back button, and the guard of `/` (signed-in users) covers them
/// all; nested [GuardedRoute]s add stricter rules.
final routerProvider = Provider<GoRouter>(
  (ref) => SymphonyRouter.create(
    ref,
    // The splash screen restores the session itself, after the start-up
    // tasks (preferences, base URL, health check).
    restoreSessionOnStart: false,
    paths: const SymphonyRoutePaths(
      splash: AppRoutes.splash,
      login: AppRoutes.login,
      home: AppRoutes.home,
      unauthorized: AppRoutes.unauthorized,
      guestOnlyPaths: <String>{AppRoutes.register, AppRoutes.forgotPassword},
    ),
    errorBuilder:
        (context, state) => SymphonyRouteErrorScreen(
          error: state.error,
          location: state.uri.toString(),
          homeLocation: AppRoutes.home,
          message:
              'This page does not exist. The router shows '
              'SymphonyRouteErrorScreen for unknown locations.',
        ),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder:
            (context, state) =>
                const SplashPage(onInitialize: initializeExampleApp),
      ),
      GuestRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GuestRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterPage(),
      ),
      GuestRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.unauthorized,
        builder: (context, state) => const UnauthorizedPage(),
      ),
      GuardedRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomePage(),
        routes: <RouteBase>[
          GuardedRoute(
            path: 'orders',
            access: const AccessRequirement(
              permissions: <String>{'orders.read'},
            ),
            builder: (context, state) => const OrdersPage(),
            routes: <RouteBase>[
              GoRoute(
                path: ':orderId',
                builder:
                    (context, state) => OrderDetailPage(
                      orderId: state.pathParameters['orderId'] ?? '',
                    ),
              ),
            ],
          ),
          GuardedRoute(
            path: 'reports',
            access: const AccessRequirement(
              permissions: <String>{'reports.view'},
            ),
            builder: (context, state) => const ReportsPage(),
          ),
          GuardedRoute(
            path: 'admin',
            access: const AccessRequirement(roles: <String>{'admin'}),
            builder: (context, state) => const AdminPage(),
            routes: <RouteBase>[
              GoRoute(
                path: 'users',
                builder: (context, state) => const AdminUsersPage(),
              ),
              GoRoute(
                path: 'audit-log',
                builder: (context, state) => const AuditLogPage(),
              ),
            ],
          ),
          GoRoute(
            path: 'files',
            builder: (context, state) => const FilesPage(),
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: 'profile',
            builder: (context, state) => const ProfilePage(),
          ),
          GoRoute(
            path: 'components',
            builder: (context, state) => const ComponentsPage(),
          ),
        ],
      ),
    ],
  ),
  name: 'routerProvider',
);

/// Shown when a signed-in user opens a page their role or permissions do
/// not allow ([SymphonyUnauthorizedScreen]).
class UnauthorizedPage extends ConsumerWidget {
  /// Creates the page.
  const UnauthorizedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SymphonyUnauthorizedScreen(
      message:
          "Your account doesn't have the role or permission this page "
          'requires.',
      homeLocation: AppRoutes.home,
      homeLabel: 'Back to the dashboard',
      actions: <Widget>[
        SymphonyButton(
          label: 'Use another account',
          icon: Icons.switch_account_outlined,
          variant: SymphonyButtonVariant.text,
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
        ),
      ],
    );
  }
}
