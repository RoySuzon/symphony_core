import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/src/core/core.dart';
import 'package:symphony_core/src/features/routing/routing.dart';

import '../routing_test_helpers.dart';

/// Application routes shared by the tests.
List<RouteBase> appRoutes({GoRouterRedirect? ordersRedirect}) => <RouteBase>[
  GoRoute(path: '/splash', builder: testPage('splash')),
  GuestRoute(path: '/login', builder: testPage('login')),
  GuestRoute(path: '/register', builder: testPage('register')),
  GoRoute(
    path: '/unauthorized',
    builder: (context, state) => const SymphonyUnauthorizedScreen(),
  ),
  GoRoute(path: '/public', builder: testPage('public')),
  GoRoute(path: '/catalog', builder: testPage('catalog')),
  GoRoute(path: '/maintenance', builder: testPage('maintenance')),
  GuardedRoute(path: '/', builder: testPage('home')),
  GuardedRoute(
    path: '/orders',
    builder: testPage('orders'),
    redirect: ordersRedirect,
  ),
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
      GoRoute(path: 'monthly', builder: testPage('reports-monthly')),
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

void main() {
  group('session restoration (unknown status)', () {
    testWidgets('sends the requested location to the splash route', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialLocation: '/orders?page=2',
      );

      expect(app.location, '/splash?from=%2Forders%3Fpage%3D2');
      expect(findPage('splash'), findsOneWidget);
    });

    testWidgets('returns to the requested location once signed in', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialLocation: '/orders?page=2',
      );

      await app.setAccess(signedIn());

      expect(app.location, '/orders?page=2');
      expect(findPage('orders'), findsOneWidget);
    });

    testWidgets('sends signed-out users to login, then back after sign-in', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialLocation: '/orders',
      );

      await app.setAccess(signedOut);
      expect(app.location, '/login?from=%2Forders');
      expect(findPage('login'), findsOneWidget);

      await app.setAccess(signedIn());
      expect(app.location, '/orders');
      expect(findPage('orders'), findsOneWidget);
    });

    testWidgets('keeps guest-only deep links for signed-out users', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialLocation: '/register',
      );
      expect(app.location, '/splash?from=%2Fregister');

      await app.setAccess(signedOut);
      expect(app.location, '/register');
      expect(findPage('register'), findsOneWidget);

      await app.setAccess(signedIn());
      expect(app.location, '/');
      expect(findPage('home'), findsOneWidget);
    });

    testWidgets('shows unguarded pages to signed-out users', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialLocation: '/catalog',
      );
      expect(app.location, '/splash?from=%2Fcatalog');

      await app.setAccess(signedOut);
      expect(app.location, '/catalog');
      expect(findPage('catalog'), findsOneWidget);
    });

    testWidgets('does not hold public paths behind the splash', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialLocation: '/public',
        publicPaths: const <String>{'/public'},
      );

      expect(app.location, '/public');
      expect(findPage('public'), findsOneWidget);
    });

    testWidgets('restores the session when the router starts', (tester) async {
      final app = await pumpSymphonyRouter(tester, routes: appRoutes());

      expect(app.auth.restoreCalls, 1);
    });

    testWidgets('can leave the session restoration to the app', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        restoreSessionOnStart: false,
      );

      expect(app.auth.restoreCalls, 0);
    });
  });

  group('authentication guards', () {
    testWidgets('redirect signed-out users to login with the location', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialAccess: signedOut,
        initialLocation: '/catalog',
      );

      await app.go('/orders?page=3');

      expect(app.location, '/login?from=%2Forders%3Fpage%3D3');
      expect(findPage('login'), findsOneWidget);
    });

    testWidgets('send signed-in users away from the login page', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialAccess: signedIn(),
        initialLocation: '/catalog',
      );

      await app.go('/login');
      expect(app.location, '/');
      expect(findPage('home'), findsOneWidget);

      await app.go('/login?from=%2Forders');
      expect(app.location, '/orders');

      await app.go('/login?from=https%3A%2F%2Fevil.com');
      expect(app.location, '/');

      await app.go('/register');
      expect(app.location, '/');
    });

    testWidgets('react to a sign-out on a guarded page', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialAccess: signedIn(),
        initialLocation: '/orders',
      );
      expect(findPage('orders'), findsOneWidget);

      await app.setAccess(signedOut);

      expect(app.location, '/login?from=%2Forders');
      expect(findPage('login'), findsOneWidget);
    });
  });

  group('role and permission guards', () {
    testWidgets('deny signed-in users lacking the role', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialAccess: signedIn(),
        initialLocation: '/catalog',
      );

      await app.go('/admin');

      expect(app.location, '/unauthorized');
      expect(find.byType(SymphonyUnauthorizedScreen), findsOneWidget);
      expect(findPage('admin'), findsNothing);
    });

    testWidgets('grant access with the role', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialAccess: signedIn(roles: <String>{'admin'}),
        initialLocation: '/admin',
      );

      expect(app.location, '/admin');
      expect(findPage('admin'), findsOneWidget);
    });

    testWidgets('protect nested routes with the parent guard', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialAccess: signedIn(),
        initialLocation: '/catalog',
      );

      await app.go('/admin/users');
      expect(app.location, '/unauthorized');
      expect(findPage('admin-users'), findsNothing);

      await app.setAccess(signedOut);
      await app.go('/admin/users');
      expect(app.location, '/login?from=%2Fadmin%2Fusers');

      await app.setAccess(signedIn(roles: <String>{'admin'}));
      expect(app.location, '/admin/users');
      expect(findPage('admin-users'), findsOneWidget);
    });

    testWidgets('apply permission guards to nested routes', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialAccess: signedIn(permissions: <String>{'reports.read'}),
        initialLocation: '/reports/monthly',
      );
      expect(findPage('reports-monthly'), findsOneWidget);

      // The child requirement is stricter: its deniedRedirect applies.
      await app.go('/reports/export');
      expect(app.location, '/reports');
      expect(findPage('reports'), findsOneWidget);

      await app.setAccess(
        signedIn(permissions: <String>{'reports.read', 'reports.export'}),
      );
      await app.go('/reports/export');
      expect(findPage('reports-export'), findsOneWidget);

      // Losing the parent permission also closes the nested pages.
      await app.setAccess(signedIn());
      expect(app.location, '/unauthorized');
    });

    testWidgets('re-evaluate the guards when roles change', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialAccess: signedIn(roles: <String>{'admin'}),
        initialLocation: '/admin',
      );
      expect(findPage('admin'), findsOneWidget);

      await app.setAccess(signedIn());

      expect(app.location, '/unauthorized');
    });
  });

  group('application redirects', () {
    testWidgets('compose the global redirect after the built-in rules', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialAccess: signedIn(),
        initialLocation: '/catalog',
        redirect:
            (context, state) =>
                state.uri.path == '/legacy-orders' ? '/orders' : null,
      );

      await app.go('/legacy-orders');

      expect(app.location, '/orders');
      expect(findPage('orders'), findsOneWidget);
    });

    testWidgets('evaluate route redirects only once the guard passed', (
      tester,
    ) async {
      var calls = 0;
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(
          ordersRedirect: (context, state) {
            calls++;
            return state.uri.queryParameters['legacy'] == '1'
                ? '/orders?page=1'
                : null;
          },
        ),
        initialAccess: signedOut,
        initialLocation: '/catalog',
      );

      await app.go('/orders?legacy=1');
      expect(app.location, '/login?from=%2Forders%3Flegacy%3D1');
      expect(calls, 0);

      await app.setAccess(signedIn());
      expect(app.location, '/orders?page=1');
      expect(calls, greaterThan(0));
    });

    testWidgets('refresh on the extra refreshListenable', (tester) async {
      final maintenance = ValueNotifier<bool>(false);
      addTearDown(maintenance.dispose);
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialAccess: signedIn(),
        initialLocation: '/orders',
        refreshListenable: maintenance,
        redirect:
            (context, state) =>
                maintenance.value && state.uri.path != '/maintenance'
                    ? '/maintenance'
                    : null,
      );
      expect(findPage('orders'), findsOneWidget);

      maintenance.value = true;
      await tester.pumpAndSettle();

      expect(app.location, '/maintenance');
    });
  });

  group('defaultAccess (secure by default)', () {
    const paths = SymphonyRoutePaths(guestOnlyPaths: <String>{'/register'});
    const publicPaths = <String>{'/public'};

    testWidgets('protects plain routes and returns to them after sign-in', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        paths: paths,
        publicPaths: publicPaths,
        defaultAccess: AccessRequirement.authenticated,
        initialAccess: signedOut,
        initialLocation: '/catalog?page=2',
      );

      expect(app.location, '/login?from=%2Fcatalog%3Fpage%3D2');
      expect(findPage('login'), findsOneWidget);

      await app.setAccess(signedIn());
      expect(app.location, '/catalog?page=2');
      expect(findPage('catalog'), findsOneWidget);

      await app.setAccess(signedOut);
      expect(app.location, '/login?from=%2Fcatalog%3Fpage%3D2');
    });

    testWidgets('leaves the guest-only and public pages open', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        paths: paths,
        publicPaths: publicPaths,
        defaultAccess: AccessRequirement.authenticated,
        initialAccess: signedOut,
        initialLocation: '/public',
      );
      expect(findPage('public'), findsOneWidget);

      await app.go('/register');
      expect(app.location, '/register');
      expect(findPage('register'), findsOneWidget);

      await app.go('/maintenance');
      expect(app.location, '/login?from=%2Fmaintenance');
    });

    testWidgets('resolves the splash straight to the sign-in page', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        paths: paths,
        defaultAccess: AccessRequirement.authenticated,
        initialLocation: '/catalog',
      );
      expect(app.location, '/splash?from=%2Fcatalog');

      await app.setAccess(signedOut);
      expect(app.location, '/login?from=%2Fcatalog');
      expect(findPage('catalog'), findsNothing);
    });

    testWidgets('sends users lacking a required role to unauthorized', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        defaultAccess: const AccessRequirement(roles: <String>{'staff'}),
        initialAccess: signedIn(),
        initialLocation: '/catalog',
      );
      expect(app.location, '/unauthorized');
      expect(find.byType(SymphonyUnauthorizedScreen), findsOneWidget);

      await app.setAccess(signedIn(roles: <String>{'staff'}));
      await app.go('/catalog');
      expect(findPage('catalog'), findsOneWidget);

      // Route guards still apply on top of the default requirement.
      await app.go('/admin');
      expect(app.location, '/unauthorized');
    });

    testWidgets('applies to the location returned by the app redirect', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        paths: paths,
        publicPaths: publicPaths,
        defaultAccess: AccessRequirement.authenticated,
        initialAccess: signedOut,
        initialLocation: '/public',
        redirect:
            (context, state) =>
                state.uri.queryParameters['legacy'] == '1' ? '/catalog' : null,
      );

      await app.go('/public?legacy=1');

      expect(app.location, '/login?from=%2Fcatalog');
      expect(findPage('catalog'), findsNothing);
    });
  });

  group('errors', () {
    testWidgets('show the error screen for unknown locations', (tester) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: appRoutes(),
        initialAccess: signedIn(),
        initialLocation: '/catalog',
      );

      await app.go('/does-not-exist');

      expect(find.byType(SymphonyRouteErrorScreen), findsOneWidget);
      expect(find.text('/does-not-exist'), findsOneWidget);

      await tester.tap(find.text('Go to home'));
      await tester.pumpAndSettle();

      expect(app.location, '/');
      expect(findPage('home'), findsOneWidget);
    });

    testWidgets('use the configured home for the error screen button', (
      tester,
    ) async {
      final app = await pumpSymphonyRouter(
        tester,
        routes: <RouteBase>[
          ...appRoutes(),
          GoRoute(path: '/dashboard', builder: testPage('dashboard')),
        ],
        paths: const SymphonyRoutePaths(home: '/dashboard'),
        initialAccess: signedIn(),
        initialLocation: '/nowhere',
      );
      expect(find.byType(SymphonyRouteErrorScreen), findsOneWidget);

      await tester.tap(find.text('Go to home'));
      await tester.pumpAndSettle();

      expect(app.location, '/dashboard');
    });
  });

  group('lifecycle', () {
    testWidgets('disposes the router with its provider', (tester) async {
      final routerProvider = Provider<GoRouter>(
        (ref) => SymphonyRouter.create(ref, routes: appRoutes()),
      );
      final container = routingTestContainer();
      final router = container.read(routerProvider);

      container.dispose();
      // Lets the scheduled session restoration run: it must notice the
      // disposal instead of using the disposed ref.
      await tester.pump();

      expect(
        () => router.routerDelegate.addListener(() {}),
        throwsFlutterError,
      );
    });

    testWidgets('creates the router once and refreshes it on access changes', (
      tester,
    ) async {
      var builds = 0;
      final routerProvider = Provider<GoRouter>((ref) {
        builds++;
        return SymphonyRouter.create(
          ref,
          routes: appRoutes(),
          initialLocation: '/orders',
        );
      });
      await tester.pumpWidget(
        routingTestScope(
          child: Consumer(
            builder:
                (context, ref, child) =>
                    MaterialApp.router(routerConfig: ref.watch(routerProvider)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
        listen: false,
      );

      container.read(testAccessProvider.notifier).set(signedIn());
      await tester.pumpAndSettle();
      container.read(testAccessProvider.notifier).set(signedOut);
      await tester.pumpAndSettle();

      expect(builds, 1);
      expect(
        locationOf(container.read(routerProvider)),
        '/login?from=%2Forders',
      );
    });
  });
}
