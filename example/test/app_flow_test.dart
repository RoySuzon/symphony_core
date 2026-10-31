import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/symphony_core.dart';
import 'package:symphony_core_example/core/routing/app_routes.dart';
import 'package:symphony_core_example/features/orders/presentation/widgets/order_widgets.dart';
import 'package:symphony_core_example/features/settings/presentation/settings_page.dart';

import 'support/example_harness.dart';

const List<String> _allModules = <String>[
  'Orders',
  'Reports',
  'Admin',
  'Files',
  'Components',
  'API inspector',
  'Profile',
  'Settings',
];

void main() {
  testWidgets('starts on the splash screen, then shows the login screen', (
    tester,
  ) async {
    final app = await pumpExampleApp(tester);

    expect(find.byType(SymphonySplashScreen), findsOneWidget);
    expect(find.byType(SymphonyLoginScreen), findsNothing);

    await app.pumpUntilFound(find.byType(SymphonyLoginScreen));
    // Let the page transition finish (the splash animates out).
    await app.settle(const Duration(milliseconds: 600));
    expect(find.byType(SymphonySplashScreen), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Demo accounts'), findsOneWidget);
    expect(find.textContaining('admin@example.com'), findsOneWidget);
    // The start-up health check went through the ApiClient.
    expect(app.requests, contains('GET /status 200'));

    await app.dispose();
  });

  testWidgets('admin signs in with the form and sees every module', (
    tester,
  ) async {
    final app = await pumpExampleApp(tester);

    await app.signInAndOpenDashboard('admin@example.com');

    expect(find.text('Hello, Alice Admin'), findsOneWidget);
    for (final module in _allModules) {
      expect(find.text(module), findsOneWidget, reason: module);
    }
    // Live badge of the Orders module: 3 pending orders on the backend.
    await app.pumpUntilFound(find.text('3'));
    expect(
      app.requests,
      containsAllInOrder(<String>['POST /auth/login 200', 'GET /orders 200']),
    );

    // Admin is a group: it opens a nested submenu.
    await tester.tap(find.text('Admin'));
    await app.settle(const Duration(milliseconds: 500));
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Audit log'), findsOneWidget);
    expect(find.text('Orders'), findsNothing);

    await tester.tap(find.text('Users'));
    await app.pumpUntilFound(find.text('Victor Viewer'));
    expect(app.requests, contains('GET /admin/users 200'));

    await app.dispose();
  });

  testWidgets('viewer does not see permission-gated modules', (tester) async {
    final app = await pumpExampleApp(tester);

    await app.signInAndOpenDashboard('viewer@example.com');

    for (final module in <String>['Files', 'Components', 'Profile']) {
      expect(find.text(module), findsOneWidget, reason: module);
    }
    for (final module in <String>['Orders', 'Reports', 'Admin']) {
      expect(find.text(module), findsNothing, reason: module);
    }
    // No orders request is made for a user without orders.read.
    expect(app.requests.where((r) => r.startsWith('GET /orders')), isEmpty);

    await app.dispose();
  });

  testWidgets('staff opening /admin lands on the unauthorized screen', (
    tester,
  ) async {
    final app = await pumpExampleApp(tester);

    await app.signInAndOpenDashboard('staff@example.com');
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);

    app.router.go(AppRoutes.admin);
    await app.pumpUntilFound(find.byType(SymphonyUnauthorizedScreen));
    expect(find.text('Access denied'), findsOneWidget);
    expect(app.requests.where((r) => r.contains('/admin/')), isEmpty);

    // The home button goes back to the dashboard.
    await tester.tap(find.text('Back to the dashboard'));
    await app.pumpUntilFound(find.byType(SymphonyDashboard));

    await app.dispose();
  });

  testWidgets('a signed-out deep link goes to the login screen and resumes', (
    tester,
  ) async {
    final app = await pumpExampleApp(tester);
    await app.pumpUntilFound(find.byType(SymphonyLoginScreen));

    app.router.go(AppRoutes.reports);
    await app.settle(const Duration(milliseconds: 300));
    expect(find.byType(SymphonyLoginScreen), findsOneWidget);

    await app.signIn('admin@example.com');
    await app.pumpUntilFound(find.text('Weekly revenue'));
    expect(app.requests, contains('GET /reports/summary 200'));

    await app.dispose();
  });

  testWidgets('orders load from the demo backend and open their details', (
    tester,
  ) async {
    final app = await pumpExampleApp(tester);
    await app.signInAndOpenDashboard('staff@example.com');

    await tester.tap(find.text('Orders'));
    await app.pumpUntilFound(find.byType(OrderTile));
    await app.settle(const Duration(milliseconds: 600));
    expect(find.textContaining('SO-1018'), findsOneWidget);
    expect(find.byType(SymphonyErrorView), findsNothing);

    // Status filter → new request with ?status=shipped.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Shipped'));
    await app.pumpUntil(
      () => find.textContaining('SO-1018').evaluate().isEmpty,
    );
    expect(find.textContaining('SO-1018'), findsNothing);
    expect(find.byType(OrderTile), findsNWidgets(4));
    expect(find.textContaining('SO-1013'), findsOneWidget);

    // Nested route /orders/:orderId.
    await tester.tap(find.textContaining('SO-1013'));
    await app.pumpUntilFound(find.text('Items'));
    expect(find.text('Order details'), findsOneWidget);
    expect(app.requests, contains('GET /orders/ord_1013 200'));
    // Staff has no orders.write permission: the refund button is hidden.
    expect(find.text('Refund order'), findsNothing);

    await app.dispose();
  });

  testWidgets('expired tokens refresh silently; a revoked session signs out', (
    tester,
  ) async {
    final app = await pumpExampleApp(tester);
    await app.signInAndOpenDashboard('staff@example.com');
    await tester.tap(find.text('Orders'));
    await app.pumpUntilFound(find.byType(OrderTile));

    // 1. Expired access token: 401 → refresh → replay, invisible to the UI.
    app.backend.expireAccessTokens();
    await app.tapTooltip('Refresh');
    await app.pumpUntil(
      () => app.requests.contains('POST /auth/token/refresh 200'),
    );
    await app.settle(const Duration(milliseconds: 500));
    expect(find.byType(OrderTile), findsWidgets);
    expect(find.byType(SymphonyLoginScreen), findsNothing);
    expect(
      app.requests,
      containsAllInOrder(<String>[
        'GET /orders 401',
        'POST /auth/token/refresh 200',
        'GET /orders 200',
      ]),
    );

    // 2. Revoked session: the refresh fails and the user is signed out.
    app.backend
      ..revokeSessions()
      ..expireAccessTokens();
    await app.tapTooltip('Refresh');
    await app.pumpUntilFound(find.text('Your session has expired'));
    expect(find.byType(SymphonyLoginScreen), findsOneWidget);
    expect(app.requests, contains('POST /auth/token/refresh 401'));

    // 3. Signing in again resumes on the orders page (?from=/orders).
    await app.signIn('staff@example.com');
    await app.pumpUntilFound(find.byType(OrderTile));

    await app.dispose();
  });

  testWidgets('signing out from the settings returns to the login screen', (
    tester,
  ) async {
    final app = await pumpExampleApp(tester);
    await app.signInAndOpenDashboard('viewer@example.com');

    await tester.tap(find.text('Settings'));
    await app.pumpUntilFound(find.byKey(SettingsPage.signOutButtonKey));
    await tester.ensureVisible(find.byKey(SettingsPage.signOutButtonKey));
    await tester.tap(find.byKey(SettingsPage.signOutButtonKey));
    await app.pumpUntilFound(find.text('Sign out?'));
    await tester.tap(find.widgetWithText(SymphonyButton, 'Sign out').last);

    await app.pumpUntilFound(find.byType(SymphonyLoginScreen));
    expect(app.requests, contains('POST /auth/logout 204'));

    await app.dispose();
  });
}
