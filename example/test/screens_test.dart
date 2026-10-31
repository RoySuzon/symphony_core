import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/symphony_core.dart';
import 'package:symphony_core_example/core/routing/app_routes.dart';
import 'package:symphony_core_example/features/auth/presentation/auth_pages.dart';

import 'support/example_harness.dart';

const Map<String, String> _screens = <String, String>{
  AppRoutes.home: 'Hello, Alice Admin',
  AppRoutes.orders: 'SO-1018',
  '/orders/ord_1018': 'History',
  AppRoutes.reports: 'Weekly revenue',
  AppRoutes.files: 'orders-export.csv',
  AppRoutes.admin: '4 accounts',
  AppRoutes.adminUsers: 'Sam Staff',
  AppRoutes.auditLog: 'Signed in',
  AppRoutes.profile: 'AccessGate examples',
  AppRoutes.settings: 'Server environment',
  AppRoutes.components: 'Responsive layout',
};

void main() {
  for (final size in <Size>[const Size(1280, 2000), const Size(360, 780)]) {
    testWidgets('every screen renders without layout errors '
        '(${size.width.round()}×${size.height.round()})', (tester) async {
      final app = await pumpExampleApp(tester, size: size);
      await app.pumpUntilFound(find.byType(LoginPage));
      expect(tester.takeException(), isNull, reason: 'login');
      final admin = find.byKey(DemoAccountsCard.tileKey('admin@example.com'));
      await tester.ensureVisible(admin);
      await tester.pump();
      await tester.tap(admin);
      await app.pumpUntilFound(find.byType(SymphonyDashboard));

      for (final entry in _screens.entries) {
        app.router.go(entry.key);
        await app.pumpUntilFound(find.textContaining(entry.value));
        await app.settle(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: entry.key);
      }

      await app.dispose();
    });
  }

  testWidgets('the profile shows roles, permissions and AccessGate results', (
    tester,
  ) async {
    final app = await pumpExampleApp(tester);
    await app.signInAndOpenDashboard('staff@example.com');

    app.router.go(AppRoutes.profile);
    await app.pumpUntilFound(find.text('AccessGate examples'));
    // Let the page transition finish: the dashboard below shows roles too.
    await app.settle(const Duration(milliseconds: 600));

    expect(find.text('Sam Staff'), findsOneWidget);
    expect(find.text('orders.read'), findsOneWidget);
    expect(find.text('staff'), findsOneWidget);
    // admin, reports, predicate: hidden — orders.read, staff-or-admin: shown.
    expect(find.text('visible'), findsNWidgets(2));
    expect(find.text('hidden'), findsNWidgets(3));

    await app.dispose();
  });

  testWidgets('settings switch the environment and the theme at runtime', (
    tester,
  ) async {
    final app = await pumpExampleApp(tester);
    await app.signInAndOpenDashboard('viewer@example.com');

    app.router.go(AppRoutes.settings);
    await app.pumpUntilFound(find.textContaining('api.example.com ('));

    await tester.tap(find.text('Staging'));
    await app.pumpUntilFound(
      find.textContaining('staging.api.example.com (staging)'),
    );
    expect(app.core.apiClient.baseUrl, 'https://staging.api.example.com');

    await tester.tap(find.text('Dark'));
    await app.settle(const Duration(milliseconds: 500));
    final context = tester.element(find.text('Server environment'));
    expect(Theme.of(context).brightness, Brightness.dark);

    await app.dispose();
  });

  testWidgets('files: upload sample files and download one', (tester) async {
    final app = await pumpExampleApp(tester);
    await app.signInAndOpenDashboard('viewer@example.com');

    app.router.go(AppRoutes.files);
    await app.pumpUntilFound(find.text('brochure-2026.pdf'));

    await app.tapTooltip('Download orders-export.csv');
    await app.pumpUntilFound(find.textContaining('Downloaded orders-export'));
    // Text files are previewed.
    expect(find.textContaining('number,customer,status'), findsOneWidget);
    expect(app.requests, contains('GET /files/file_orders_csv/content 200'));

    await tester.tap(find.textContaining('Upload 768'));
    await app.pumpUntilFound(find.textContaining('Uploaded 3 files'));
    await app.pumpUntilFound(find.text('sample-3.txt'));
    expect(app.requests, contains('POST /files 201'));
    // Both transfers are in the local history (LocalDatabase).
    expect(find.text('3 files'), findsOneWidget);

    await app.dispose();
  });

  testWidgets('guest pages: register, password recovery and unknown routes', (
    tester,
  ) async {
    final app = await pumpExampleApp(tester);
    await app.pumpUntilFound(find.byType(LoginPage));

    await tester.tap(find.text('Create one'));
    await app.pumpUntilFound(find.byType(SymphonyRegisterForm));
    expect(find.text('Create your account'), findsOneWidget);

    app.router.go(AppRoutes.forgotPassword);
    await app.pumpUntilFound(find.byType(SymphonyForgotPasswordForm));
    expect(find.textContaining('123456'), findsOneWidget);

    app.router.go('/does-not-exist');
    await app.pumpUntilFound(find.byType(SymphonyRouteErrorScreen));

    await app.dispose();
  });

  testWidgets(
    'quick sign-in shows the validator failure for unverified users',
    (tester) async {
      final app = await pumpExampleApp(tester);
      await app.pumpUntilFound(find.byType(LoginPage));

      await tester.tap(
        find.byKey(DemoAccountsCard.tileKey('unverified@example.com')),
      );
      await app.pumpUntilFound(
        find.text('Please verify your e-mail address before signing in.'),
      );
      expect(find.byType(LoginPage), findsOneWidget);

      await tester.tap(
        find.byKey(DemoAccountsCard.tileKey('admin@example.com')),
      );
      await app.pumpUntilFound(find.byType(SymphonyDashboard));

      await app.dispose();
    },
  );
}
