import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/src/core/access/access_context.dart';
import 'package:symphony_core/src/core/access/access_requirement.dart';
import 'package:symphony_core/src/features/auth/presentation/providers/auth_providers.dart';
import 'package:symphony_core/src/features/dashboard/dashboard.dart';
import 'package:symphony_core/src/features/routing/routing.dart';

import '../dashboard_test_utils.dart';

Widget _destination(BuildContext context, GoRouterState state) {
  return Scaffold(
    body: Column(
      children: <Widget>[
        Text('location: ${state.uri}'),
        Text('extra: ${state.extra}'),
      ],
    ),
  );
}

/// Pumps [dashboard] as the `/` route of a real GoRouter.
Future<GoRouter> pumpWithRouter(
  WidgetTester tester,
  Widget dashboard, {
  AccessContext? access,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(body: dashboard),
      ),
      GoRoute(path: '/orders', name: 'orders', builder: _destination),
      GoRoute(path: '/orders/:orderId', name: 'order', builder: _destination),
      GoRoute(path: '/invoices', name: 'invoices', builder: _destination),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accessContextProvider.overrideWithValue(
          access ?? AccessContext.unauthenticated,
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('with GoRouter', () {
    testWidgets('go replaces the location (default)', (tester) async {
      final router = await pumpWithRouter(
        tester,
        const SymphonyDashboard(
          items: <DashboardItem>[
            DashboardItem(id: 'orders', label: 'Orders', route: '/orders'),
          ],
        ),
      );

      await tapAndSettle(tester, tile('Orders'));

      expect(find.text('location: /orders'), findsOneWidget);
      expect(router.canPop(), isFalse);
    });

    testWidgets('push stacks the destination over the dashboard',
        (tester) async {
      final router = await pumpWithRouter(
        tester,
        const SymphonyDashboard(
          items: <DashboardItem>[
            DashboardItem(
              id: 'orders',
              label: 'Orders',
              route: '/orders',
              extra: 'from-dashboard',
              navigation: DashboardNavigation.push,
            ),
          ],
        ),
      );

      await tapAndSettle(tester, tile('Orders'));
      expect(find.text('location: /orders'), findsOneWidget);
      expect(find.text('extra: from-dashboard'), findsOneWidget);
      expect(router.canPop(), isTrue);

      router.pop();
      await tester.pumpAndSettle();
      expect(tile('Orders'), findsOneWidget);
    });

    testWidgets('goNamed builds the location from path and query parameters',
        (tester) async {
      final router = await pumpWithRouter(
        tester,
        const SymphonyDashboard(
          items: <DashboardItem>[
            DashboardItem(
              id: 'order',
              label: 'Order 42',
              routeName: 'order',
              pathParameters: <String, String>{'orderId': '42'},
              queryParameters: <String, dynamic>{'tab': 'items', 'page': 2},
              extra: 'payload',
            ),
          ],
        ),
      );

      await tapAndSettle(tester, tile('Order 42'));

      expect(
          find.text('location: /orders/42?tab=items&page=2'), findsOneWidget);
      expect(find.text('extra: payload'), findsOneWidget);
      expect(router.canPop(), isFalse);
    });

    testWidgets('pushNamed keeps the dashboard below', (tester) async {
      final router = await pumpWithRouter(
        tester,
        const SymphonyDashboard(
          items: <DashboardItem>[
            DashboardItem(
              id: 'order',
              label: 'Order 7',
              routeName: 'order',
              pathParameters: <String, String>{'orderId': '7'},
              navigation: DashboardNavigation.push,
            ),
          ],
        ),
      );

      await tapAndSettle(tester, tile('Order 7'));
      expect(find.text('location: /orders/7'), findsOneWidget);
      expect(router.canPop(), isTrue);

      router.pop();
      await tester.pumpAndSettle();
      expect(tile('Order 7'), findsOneWidget);
    });

    testWidgets('routeName takes precedence over route', (tester) async {
      await pumpWithRouter(
        tester,
        const SymphonyDashboard(
          items: <DashboardItem>[
            DashboardItem(
              id: 'both',
              label: 'Both',
              routeName: 'invoices',
              route: '/orders',
            ),
          ],
        ),
      );

      await tapAndSettle(tester, tile('Both'));
      expect(find.text('location: /invoices'), findsOneWidget);
    });

    testWidgets('route query parameters are merged into the location',
        (tester) async {
      await pumpWithRouter(
        tester,
        const SymphonyDashboard(
          items: <DashboardItem>[
            DashboardItem(
              id: 'query',
              label: 'Query',
              route: '/orders?status=open',
              queryParameters: <String, dynamic>{'page': '1'},
            ),
          ],
        ),
      );

      await tapAndSettle(tester, tile('Query'));
      expect(find.text('location: /orders?status=open&page=1'), findsOneWidget);
    });

    testWidgets('leaves of inline submenus navigate too', (tester) async {
      await pumpWithRouter(
        tester,
        const SymphonyDashboard(items: sampleMenu),
        access: salesUser,
      );

      await tapAndSettle(tester, tile('Sales'));
      await tapAndSettle(tester, tile('Invoices'));

      expect(find.text('location: /invoices'), findsOneWidget);
    });

    testWidgets('onItemSelected prevents the navigation', (tester) async {
      DashboardItem? selected;
      final router = await pumpWithRouter(
        tester,
        SymphonyDashboard(
          items: const <DashboardItem>[
            DashboardItem(id: 'orders', label: 'Orders', route: '/orders'),
          ],
          onItemSelected: (item) => selected = item,
        ),
      );

      await tapAndSettle(tester, tile('Orders'));

      expect(selected?.id, 'orders');
      expect(find.text('location: /orders'), findsNothing);
      expect(router.canPop(), isFalse);
      expect(tile('Orders'), findsOneWidget);
    });

    testWidgets('pushed modules close when the user loses access to them',
        (tester) async {
      final container = createAccessContainer(
        access: signedIn(roles: <String>{'admin'}),
      );
      final routerProvider = Provider<GoRouter>(
        (ref) => SymphonyRouter.create(
          ref,
          restoreSessionOnStart: false,
          routes: <RouteBase>[
            GoRoute(path: '/splash', builder: _destination),
            GuestRoute(path: '/login', builder: _destination),
            GoRoute(path: '/unauthorized', builder: _destination),
            GuardedRoute(
              path: '/',
              builder: (context, state) => const Scaffold(
                body: SymphonyDashboard(
                  items: <DashboardItem>[
                    DashboardItem(
                      id: 'admin',
                      label: 'Admin',
                      route: '/admin',
                      navigation: DashboardNavigation.push,
                      access: AccessRequirement(roles: <String>{'admin'}),
                    ),
                  ],
                ),
              ),
            ),
            GuardedRoute(
              path: '/admin',
              access: const AccessRequirement(roles: <String>{'admin'}),
              builder: _destination,
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, child) =>
                MaterialApp.router(routerConfig: ref.watch(routerProvider)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tapAndSettle(tester, tile('Admin'));
      expect(find.text('location: /admin'), findsOneWidget);

      changeAccess(container, signedIn());
      await tester.pumpAndSettle();

      expect(
        find.text('location: /admin', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('location: /unauthorized'), findsOneWidget);
    });

    testWidgets('pages pushed for submenus support go and push',
        (tester) async {
      final router = await pumpWithRouter(
        tester,
        const SymphonyDashboard(
          submenuPresentation: DashboardSubmenuPresentation.page,
          items: <DashboardItem>[
            DashboardItem(
              id: 'sales',
              label: 'Sales',
              children: <DashboardItem>[
                DashboardItem(
                  id: 'sales.order',
                  label: 'Order 9',
                  routeName: 'order',
                  pathParameters: <String, String>{'orderId': '9'},
                  navigation: DashboardNavigation.push,
                ),
                DashboardItem(
                  id: 'sales.invoices',
                  label: 'Invoices',
                  route: '/invoices',
                ),
              ],
            ),
          ],
        ),
      );

      await tapAndSettle(tester, tile('Sales'));
      expect(find.widgetWithText(AppBar, 'Sales'), findsOneWidget);

      // push: popping returns to the submenu page.
      await tapAndSettle(tester, tile('Order 9'));
      expect(find.text('location: /orders/9'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Sales'), findsOneWidget);

      // go: the destination replaces the dashboard and its pages.
      await tapAndSettle(tester, tile('Invoices'));
      expect(find.text('location: /invoices'), findsOneWidget);
      expect(
        find.byType(SymphonyDashboardSubmenuPage, skipOffstage: false),
        findsNothing,
      );
      expect(router.canPop(), isFalse);
    });
  });

  group('without GoRouter', () {
    testWidgets('falls back to Navigator named routes', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accessContextProvider.overrideWithValue(
              AccessContext.unauthenticated,
            ),
          ],
          child: MaterialApp(
            home: const Scaffold(
              body: SymphonyDashboard(
                items: <DashboardItem>[
                  DashboardItem(
                    id: 'orders',
                    label: 'Orders',
                    route: '/orders',
                    queryParameters: <String, dynamic>{'page': '2'},
                    extra: 'args',
                  ),
                ],
              ),
            ),
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (context) => Text(
                'route ${settings.name} with ${settings.arguments}',
              ),
            ),
          ),
        ),
      );

      await tapAndSettle(tester, tile('Orders'));

      expect(find.text('route /orders?page=2 with args'), findsOneWidget);
    });

    testWidgets('reports items that cannot be opened instead of crashing',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accessContextProvider.overrideWithValue(
              AccessContext.unauthenticated,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SymphonyDashboard(
                items: <DashboardItem>[
                  DashboardItem(id: 'named', label: 'Named', routeName: 'x'),
                ],
              ),
            ),
          ),
        ),
      );

      await tapAndSettle(tester, tile('Named'));

      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect('$error', contains('Cannot open the destination'));
      expect('$error', contains('routeName requires GoRouter'));
      expect(tile('Named'), findsOneWidget);
    });

    testWidgets('reports a route the Navigator cannot open instead of throwing',
        (tester) async {
      const item = DashboardItem(
        id: 'orders',
        label: 'Orders',
        route: '/orders',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accessContextProvider.overrideWithValue(
              AccessContext.unauthenticated,
            ),
          ],
          // No routes, onGenerateRoute or onUnknownRoute handle '/orders'.
          child: const MaterialApp(
            home: Scaffold(
              body: SymphonyDashboard(items: <DashboardItem>[item]),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(SymphonyDashboard));

      expect(navigateToDashboardItem(context, item), isFalse);
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect('$error', contains('Cannot open the destination'));
      expect('$error', contains('"/orders"'));

      await tapAndSettle(tester, tile('Orders'));
      expect('${tester.takeException()}', contains('Cannot open'));
      expect(tile('Orders'), findsOneWidget);
    });

    testWidgets('reports a missing Navigator', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accessContextProvider.overrideWithValue(
              AccessContext.unauthenticated,
            ),
          ],
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(),
              child: SymphonyDashboard(
                items: <DashboardItem>[
                  DashboardItem(id: 'orders', label: 'Orders', route: '/o'),
                ],
              ),
            ),
          ),
        ),
      );

      await tapAndSettle(tester, tile('Orders'));

      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect('$error', contains('No GoRouter and no Navigator'));
    });

    testWidgets('navigateToDashboardItem ignores items without destination',
        (tester) async {
      await pumpInApp(
        tester,
        createAccessContainer(),
        const SymphonyDashboard(items: sampleMenu),
      );
      final context = tester.element(find.byType(SymphonyDashboard));

      expect(
        navigateToDashboardItem(
          context,
          const DashboardItem(id: 'none', label: 'None'),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
