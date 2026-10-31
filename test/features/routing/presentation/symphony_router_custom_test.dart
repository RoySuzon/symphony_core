import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/src/core/core.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/features/routing/presentation/symphony_route_scope.dart';
import 'package:symphony_core/src/features/routing/routing.dart';

import '../routing_test_helpers.dart';

/// Non-default paths: the guards must use them, not the defaults.
const SymphonyRoutePaths customPaths = SymphonyRoutePaths(
  splash: '/boot',
  login: '/auth/sign-in',
  home: '/dashboard',
  unauthorized: '/forbidden',
  redirectParameter: 'next',
  guestOnlyPaths: <String>{'/auth/register'},
);

List<RouteBase> customRoutes() => <RouteBase>[
      GoRoute(path: '/boot', builder: testPage('boot')),
      GoRoute(path: '/auth/sign-in', builder: testPage('sign-in')),
      GoRoute(path: '/auth/register', builder: testPage('register')),
      GoRoute(path: '/forbidden', builder: testPage('forbidden')),
      GuardedRoute(path: '/dashboard', builder: testPage('dashboard')),
      GuardedRoute(
        path: '/admin',
        access: const AccessRequirement(roles: <String>{'admin'}),
        builder: testPage('admin'),
        routes: <RouteBase>[
          GoRoute(path: 'users', builder: testPage('admin-users')),
        ],
      ),
    ];

/// Unmounts the app so the router can be disposed safely.
Future<void> unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

void main() {
  group('SymphonyRouter.custom (no Riverpod)', () {
    testWidgets('drives the guards from readAccess and the custom paths',
        (tester) async {
      final access = ValueNotifier<AccessContext>(AccessContext.unknown);
      addTearDown(access.dispose);
      final router = SymphonyRouter.custom(
        readAccess: () => access.value,
        refreshListenable: access,
        routes: customRoutes(),
        paths: customPaths,
        initialLocation: '/admin/users',
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(locationOf(router), '/boot?next=%2Fadmin%2Fusers');
      expect(findPage('boot'), findsOneWidget);

      access.value = signedOut;
      await tester.pumpAndSettle();
      expect(locationOf(router), '/auth/sign-in?next=%2Fadmin%2Fusers');

      access.value = signedIn(roles: <String>{'admin'});
      await tester.pumpAndSettle();
      expect(locationOf(router), '/admin/users');
      expect(findPage('admin-users'), findsOneWidget);

      access.value = signedIn();
      await tester.pumpAndSettle();
      expect(locationOf(router), '/forbidden');

      router.go('/auth/register');
      await tester.pumpAndSettle();
      expect(locationOf(router), '/dashboard');

      await unmount(tester);
      router.dispose();
    });

    testWidgets('composes the application redirect', (tester) async {
      final access = ValueNotifier<AccessContext>(signedIn());
      addTearDown(access.dispose);
      final router = SymphonyRouter.custom(
        readAccess: () => access.value,
        refreshListenable: access,
        routes: customRoutes(),
        paths: customPaths,
        initialLocation: '/home',
        redirect: (context, state) =>
            state.uri.path == '/home' ? '/dashboard' : null,
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(locationOf(router), '/dashboard');
      expect(findPage('dashboard'), findsOneWidget);

      await unmount(tester);
      router.dispose();
    });

    testWidgets('uses the custom error builder', (tester) async {
      final access = ValueNotifier<AccessContext>(signedIn());
      addTearDown(access.dispose);
      final router = SymphonyRouter.custom(
        readAccess: () => access.value,
        refreshListenable: access,
        routes: customRoutes(),
        paths: customPaths,
        initialLocation: '/missing',
        errorBuilder: (context, state) => Scaffold(
          body: Text('custom error: ${state.uri.path}'),
        ),
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('custom error: /missing'), findsOneWidget);
      expect(find.byType(SymphonyRouteErrorScreen), findsNothing);

      await unmount(tester);
      router.dispose();
    });
  });

  group('SymphonyRouter.buildRedirect configuration checks', () {
    AccessContext readUnknown() => AccessContext.unknown;

    test('accept valid paths', () {
      expect(
        () => SymphonyRouter.buildRedirect(
          readAccess: readUnknown,
          paths: customPaths,
          publicPaths: const <String>{'/legal'},
        ),
        returnsNormally,
      );
    });

    test('reject paths without a leading slash', () {
      expect(
        () => SymphonyRouter.buildRedirect(
          readAccess: readUnknown,
          paths: const SymphonyRoutePaths(login: 'login'),
        ),
        throwsAssertionError,
      );
      expect(
        () => SymphonyRouter.buildRedirect(
          readAccess: readUnknown,
          publicPaths: const <String>{'legal'},
        ),
        throwsAssertionError,
      );
      expect(
        () => SymphonyRouter.buildRedirect(
          readAccess: readUnknown,
          paths: const SymphonyRoutePaths(guestOnlyPaths: <String>{'signup'}),
        ),
        throwsAssertionError,
      );
    });

    test('reject an empty redirect parameter', () {
      expect(
        () => SymphonyRouter.buildRedirect(
          readAccess: readUnknown,
          paths: const SymphonyRoutePaths(redirectParameter: ''),
        ),
        throwsAssertionError,
      );
    });
  });

  group('SymphonyRouter.buildRedirect with a hand-made GoRouter', () {
    testWidgets('provides the access source and paths to the guards',
        (tester) async {
      final routerProvider = Provider<GoRouter>((ref) {
        final router = GoRouter(
          routes: customRoutes(),
          initialLocation: '/admin',
          redirect: SymphonyRouter.buildRedirect(
            readAccess: () => ref.read(accessContextProvider),
            paths: customPaths,
          ),
          refreshListenable: SymphonyRouter.accessRefreshListenable(ref),
          errorBuilder: SymphonyRouter.defaultErrorBuilder(
            homeLocation: customPaths.home,
          ),
        );
        ref.onDispose(router.dispose);
        return router;
      });
      await tester.pumpWidget(
        routingTestScope(
          initialAccess: signedOut,
          child: Consumer(
            builder: (context, ref, child) =>
                MaterialApp.router(routerConfig: ref.watch(routerProvider)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
        listen: false,
      );
      final router = container.read(routerProvider);
      expect(locationOf(router), '/auth/sign-in?next=%2Fadmin');

      container.read(testAccessProvider.notifier).set(signedIn());
      await tester.pumpAndSettle();
      expect(locationOf(router), '/forbidden');
    });
  });

  group('guards in a router not built by SymphonyRouter', () {
    testWidgets('fall back to accessContextProvider and the default paths',
        (tester) async {
      final routerProvider = Provider<GoRouter>((ref) {
        final router = GoRouter(
          initialLocation: '/orders',
          routes: <RouteBase>[
            GoRoute(path: '/login', builder: testPage('login')),
            GoRoute(path: '/unauthorized', builder: testPage('unauthorized')),
            GuardedRoute(path: '/orders', builder: testPage('orders')),
            GuardedRoute(
              path: '/admin',
              access: const AccessRequirement(roles: <String>{'admin'}),
              builder: testPage('admin'),
            ),
          ],
        );
        ref.onDispose(router.dispose);
        return router;
      });
      await tester.pumpWidget(
        routingTestScope(
          initialAccess: signedOut,
          child: Consumer(
            builder: (context, ref, child) =>
                MaterialApp.router(routerConfig: ref.watch(routerProvider)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
        listen: false,
      );
      final router = container.read(routerProvider);
      expect(locationOf(router), '/login?from=%2Forders');

      container.read(testAccessProvider.notifier).set(signedIn());
      router.go('/admin');
      await tester.pumpAndSettle();
      expect(locationOf(router), '/unauthorized');
    });

    testWidgets('report a missing access source', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final context = tester.element(find.byType(SizedBox));

      expect(
        () => SymphonyRouteScope.of(context),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('SymphonyRouter'),
          ),
        ),
      );
    });

    testWidgets('prefer the scope bound to the router context', (tester) async {
      await tester.pumpWidget(
        routingTestScope(
          initialAccess: signedOut,
          child: const SizedBox.shrink(),
        ),
      );
      final context = tester.element(find.byType(SizedBox));

      final fallback = SymphonyRouteScope.of(context);
      expect(fallback.readAccess(), signedOut);
      expect(fallback.resolver, const SymphonyRedirectResolver());

      const resolver = SymphonyRedirectResolver(paths: customPaths);
      SymphonyRouteScope.bind(
        context,
        const SymphonyRouteScope(readAccess: signedIn, resolver: resolver),
      );
      final bound = SymphonyRouteScope.of(context);
      expect(bound.readAccess(), signedIn());
      expect(bound.resolver, resolver);
    });
  });
}
