import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/src/features/routing/routing.dart';

import '../../routing_test_helpers.dart';

Future<void> pumpScreen(WidgetTester tester, Widget screen) =>
    tester.pumpWidget(MaterialApp(home: screen));

/// Pumps [screen] as the initial page of a real router with a `/` route.
Future<GoRouter> pumpInRouter(WidgetTester tester, Widget screen) async {
  final router = GoRouter(
    initialLocation: '/screen',
    routes: <RouteBase>[
      GoRoute(path: '/', builder: testPage('home')),
      GoRoute(path: '/start', builder: testPage('start')),
      GoRoute(path: '/screen', builder: (context, state) => screen),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('SymphonyRouteErrorScreen', () {
    testWidgets('shows the default texts and the location', (tester) async {
      await pumpScreen(
        tester,
        const SymphonyRouteErrorScreen(location: '/missing?x=1'),
      );

      expect(find.text('Page not found'), findsOneWidget);
      expect(
        find.text(
          'The page you are looking for does not exist or has been moved.',
        ),
        findsOneWidget,
      );
      expect(find.text('Requested location'), findsOneWidget);
      expect(find.text('/missing?x=1'), findsOneWidget);
    });

    testWidgets('accepts custom texts', (tester) async {
      var tapped = 0;
      await pumpScreen(
        tester,
        SymphonyRouteErrorScreen(
          location: '/missing',
          title: 'Introuvable',
          message: "Cette page n'existe pas.",
          locationLabel: 'Adresse',
          homeLabel: 'Accueil',
          onGoHome: () => tapped++,
        ),
      );

      expect(find.text('Introuvable'), findsOneWidget);
      expect(find.text("Cette page n'existe pas."), findsOneWidget);
      expect(find.text('Adresse'), findsOneWidget);

      await tester.tap(find.text('Accueil'));
      expect(tapped, 1);
    });

    testWidgets('shows the error details only when enabled', (tester) async {
      final error = StateError('no routes for location: /missing');
      await pumpScreen(
        tester,
        SymphonyRouteErrorScreen(error: error, showErrorDetails: true),
      );
      expect(find.text(error.toString()), findsOneWidget);

      await pumpScreen(
        tester,
        SymphonyRouteErrorScreen(error: error, showErrorDetails: false),
      );
      expect(find.text(error.toString()), findsNothing);
    });

    testWidgets('hides the location when unknown', (tester) async {
      await pumpScreen(tester, const SymphonyRouteErrorScreen());

      expect(find.text('Requested location'), findsNothing);
    });

    testWidgets('hides the home button without router or callback', (
      tester,
    ) async {
      await pumpScreen(tester, const SymphonyRouteErrorScreen());

      expect(find.text('Go to home'), findsNothing);
    });

    testWidgets('opens homeLocation through the enclosing router', (
      tester,
    ) async {
      final router = await pumpInRouter(
        tester,
        const SymphonyRouteErrorScreen(homeLocation: '/start'),
      );

      await tester.tap(find.text('Go to home'));
      await tester.pumpAndSettle();

      expect(locationOf(router), '/start');
      expect(findPage('start'), findsOneWidget);
    });
  });

  group('SymphonyUnauthorizedScreen', () {
    testWidgets('shows the default texts', (tester) async {
      await pumpScreen(tester, const SymphonyUnauthorizedScreen());

      expect(find.text('Access denied'), findsOneWidget);
      expect(
        find.text("You don't have permission to view this page."),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('accepts custom texts, callback and actions', (tester) async {
      var tapped = 0;
      await pumpScreen(
        tester,
        SymphonyUnauthorizedScreen(
          title: 'Accès refusé',
          message: "Vous n'avez pas les droits nécessaires.",
          homeLabel: 'Accueil',
          onGoHome: () => tapped++,
          actions: const <Widget>[Text('Changer de compte')],
        ),
      );

      expect(find.text('Accès refusé'), findsOneWidget);
      expect(
        find.text("Vous n'avez pas les droits nécessaires."),
        findsOneWidget,
      );
      expect(find.text('Changer de compte'), findsOneWidget);

      await tester.tap(find.text('Accueil'));
      expect(tapped, 1);
    });

    testWidgets('hides the home button without router or callback', (
      tester,
    ) async {
      await pumpScreen(tester, const SymphonyUnauthorizedScreen());

      expect(find.text('Go to home'), findsNothing);
    });

    testWidgets('opens homeLocation through the enclosing router', (
      tester,
    ) async {
      final router = await pumpInRouter(
        tester,
        const SymphonyUnauthorizedScreen(),
      );

      await tester.tap(find.text('Go to home'));
      await tester.pumpAndSettle();

      expect(locationOf(router), '/');
      expect(findPage('home'), findsOneWidget);
    });
  });
}
