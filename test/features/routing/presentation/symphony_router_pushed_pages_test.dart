import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/src/core/core.dart';
import 'package:symphony_core/src/features/routing/routing.dart';

import '../routing_test_helpers.dart';

/// Routes whose pages are opened with `GoRouter.push` in these tests.
List<RouteBase> pushRoutes() => <RouteBase>[
  GoRoute(path: '/splash', builder: testPage('splash')),
  GuestRoute(path: '/login', builder: testPage('login')),
  GoRoute(path: '/unauthorized', builder: testPage('unauthorized')),
  GoRoute(path: '/catalog', builder: testPage('catalog')),
  GuardedRoute(path: '/', builder: testPage('home')),
  GuardedRoute(path: '/orders', builder: testPage('orders')),
  GuardedRoute(
    path: '/admin',
    access: const AccessRequirement(roles: <String>{'admin'}),
    builder: testPage('admin'),
    routes: <RouteBase>[
      GoRoute(path: 'users', builder: testPage('admin-users')),
    ],
  ),
  GuardedRoute(
    path: '/reports',
    access: const AccessRequirement(permissions: <String>{'reports.read'}),
    builder: testPage('reports'),
    routes: <RouteBase>[
      GuardedRoute(
        path: 'export',
        access: const AccessRequirement(
          permissions: <String>{'reports.read', 'reports.export'},
        ),
        deniedRedirect: '/reports',
        builder: testPage('reports-export'),
      ),
    ],
  ),
];

/// Finds the test page [name], including pages covered by other routes.
Finder anyPage(String name) => find.text('page:$name', skipOffstage: false);

/// Opens [location] with `GoRouter.push` and settles the navigation.
Future<void> push(RouterHarness app, String location) async {
  unawaited(app.router.push<Object?>(location));
  await app.tester.pumpAndSettle();
}

void main() {
  // go_router 13 and later only re-evaluate the redirects of the location
  // below the pushed pages when the router refreshes: without the check of
  // the pushed pages, they stayed displayed after the user lost access.
  group('pages opened with push', () {
    testWidgets('are closed by a sign-out, which remembers them', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: pushRoutes(),
        initialAccess: signedIn(),
        initialLocation: '/catalog',
      );
      await push(app, '/orders?page=2');
      expect(findPage('orders'), findsOneWidget);

      await app.setAccess(signedOut);

      expect(app.location, '/login?from=%2Forders%3Fpage%3D2');
      expect(findPage('login'), findsOneWidget);
      expect(anyPage('orders'), findsNothing);
      expect(app.router.canPop(), isFalse);

      await app.setAccess(signedIn());
      expect(app.location, '/orders?page=2');
      expect(findPage('orders'), findsOneWidget);
    });

    testWidgets('are closed when a role of a parent guard is revoked', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: pushRoutes(),
        initialAccess: signedIn(roles: <String>{'admin'}),
        initialLocation: '/orders',
      );
      await push(app, '/admin/users');
      expect(findPage('admin-users'), findsOneWidget);

      await app.setAccess(signedIn());

      expect(app.location, '/unauthorized');
      expect(findPage('unauthorized'), findsOneWidget);
      expect(anyPage('admin-users'), findsNothing);
      expect(anyPage('orders'), findsNothing);
    });

    testWidgets('are closed when the denied redirect is the page below', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: pushRoutes(),
        initialAccess: signedIn(
          permissions: <String>{'reports.read', 'reports.export'},
        ),
        initialLocation: '/reports',
      );
      await push(app, '/reports/export');
      expect(findPage('reports-export'), findsOneWidget);

      await app.setAccess(signedIn(permissions: <String>{'reports.read'}));

      expect(app.location, '/reports');
      expect(findPage('reports'), findsOneWidget);
      expect(anyPage('reports-export'), findsNothing);
      expect(app.router.canPop(), isFalse);
    });

    testWidgets('close a pushed sign-in page once signed in', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: pushRoutes(),
        initialAccess: signedOut,
        initialLocation: '/catalog',
      );
      await push(app, '/login?from=%2Fcatalog');
      expect(findPage('login'), findsOneWidget);

      await app.setAccess(signedIn());

      expect(app.location, '/catalog');
      expect(findPage('catalog'), findsOneWidget);
      expect(anyPage('login'), findsNothing);
      expect(app.router.canPop(), isFalse);
    });

    testWidgets('are closed inside a shell route as well', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: <RouteBase>[
          GoRoute(path: '/splash', builder: testPage('splash')),
          GuestRoute(path: '/login', builder: testPage('login')),
          ShellRoute(
            builder:
                (context, state, child) => Scaffold(
                  appBar: AppBar(title: const Text('shell')),
                  body: child,
                ),
            routes: <RouteBase>[
              GoRoute(path: '/catalog', builder: testPage('catalog')),
              GuardedRoute(path: '/orders', builder: testPage('orders')),
            ],
          ),
        ],
        initialAccess: signedIn(),
        initialLocation: '/catalog',
      );
      await push(app, '/orders');
      expect(findPage('orders'), findsOneWidget);

      await app.setAccess(signedOut);

      expect(app.location, '/login?from=%2Forders');
      expect(anyPage('orders'), findsNothing);
    });

    testWidgets('stay open while the user may still see them', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: pushRoutes(),
        initialAccess: signedIn(),
        initialLocation: '/catalog',
      );
      await push(app, '/orders');
      expect(findPage('orders'), findsOneWidget);

      await app.setAccess(signedIn(roles: <String>{'admin'}));

      expect(findPage('orders'), findsOneWidget);
      expect(app.router.canPop(), isTrue);
      app.router.pop();
      await tester.pumpAndSettle();
      expect(findPage('catalog'), findsOneWidget);
    });
  });
}
