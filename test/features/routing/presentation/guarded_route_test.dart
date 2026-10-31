import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/src/core/core.dart';
import 'package:symphony_core/src/features/routing/routing.dart';

Widget _page(BuildContext context, GoRouterState state) => const SizedBox();

String? _appRedirect(BuildContext context, GoRouterState state) => null;

List<String> _propertyNames(Diagnosticable route) =>
    route
        .toDiagnosticsNode()
        .getProperties()
        .map((DiagnosticsNode node) => node.name ?? '')
        .toList();

void main() {
  group('GuardedRoute', () {
    test('is a GoRoute with a redirect', () {
      final route = GuardedRoute(path: '/orders', builder: _page);

      expect(route, isA<GoRoute>());
      expect(route.path, '/orders');
      expect(route.redirect, isNotNull);
    });

    test('requires a signed-in user by default', () {
      final route = GuardedRoute(path: '/orders', builder: _page);

      expect(route.access, AccessRequirement.authenticated);
      expect(route.deniedRedirect, isNull);
      expect(route.appRedirect, isNull);
    });

    test('keeps its configuration', () {
      final key = GlobalKey<NavigatorState>();
      final child = GoRoute(path: 'users', builder: _page);
      final route = GuardedRoute(
        path: '/admin',
        name: 'admin',
        parentNavigatorKey: key,
        access: const AccessRequirement(roles: <String>{'admin'}),
        deniedRedirect: '/upgrade',
        redirect: _appRedirect,
        builder: _page,
        routes: <RouteBase>[child],
      );

      expect(route.name, 'admin');
      expect(route.parentNavigatorKey, key);
      expect(route.routes, <RouteBase>[child]);
      expect(route.access.roles, <String>{'admin'});
      expect(route.deniedRedirect, '/upgrade');
      expect(route.appRedirect, _appRedirect);
      expect(route.redirect, isNot(_appRedirect));
      expect(route.builder, _page);
    });

    test('accepts a page builder', () {
      final route = GuardedRoute(
        path: '/orders',
        pageBuilder:
            (context, state) => const MaterialPage<void>(child: SizedBox()),
      );

      expect(route.pageBuilder, isNotNull);
      expect(route.builder, isNull);
    });

    test('asserts that something can be shown or redirected to', () {
      expect(() => GuardedRoute(path: '/orders'), throwsAssertionError);
      expect(
        () => GuardedRoute(path: '/orders', redirect: _appRedirect),
        returnsNormally,
      );
    });

    test('describes its access rule', () {
      final route = GuardedRoute(
        path: '/admin',
        access: const AccessRequirement(roles: <String>{'admin'}),
        deniedRedirect: '/upgrade',
        builder: _page,
      );

      expect(
        _propertyNames(route),
        containsAll(<String>['access', 'deniedRedirect']),
      );
    });
  });

  group('GuestRoute', () {
    test('is a GoRoute with a redirect', () {
      final route = GuestRoute(path: '/login', builder: _page);

      expect(route, isA<GoRoute>());
      expect(route.redirect, isNotNull);
      expect(route.authenticatedRedirect, isNull);
      expect(route.appRedirect, isNull);
    });

    test('keeps its configuration', () {
      final route = GuestRoute(
        path: '/register',
        name: 'register',
        authenticatedRedirect: '/welcome',
        redirect: _appRedirect,
        builder: _page,
      );

      expect(route.name, 'register');
      expect(route.authenticatedRedirect, '/welcome');
      expect(route.appRedirect, _appRedirect);
    });

    test('asserts that something can be shown or redirected to', () {
      expect(() => GuestRoute(path: '/login'), throwsAssertionError);
    });

    test('describes its redirect', () {
      final route = GuestRoute(
        path: '/login',
        authenticatedRedirect: '/welcome',
        builder: _page,
      );

      expect(_propertyNames(route), contains('authenticatedRedirect'));
    });
  });
}
