import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/ui/ui.dart';

import '../../ui_test_utils.dart';

void main() {
  group('SymphonyErrorView', () {
    final cases = <Failure, (IconData, String)>{
      const NetworkFailure(): (Icons.wifi_off, 'No internet connection'),
      const TimeoutFailure(): (Icons.timer_off, 'Request timed out'),
      const UnauthorizedFailure(): (Icons.lock_outline, 'Session expired'),
      const ForbiddenFailure(): (Icons.block, 'Access denied'),
      const NotFoundFailure(): (Icons.search_off, 'Not found'),
      const ValidationFailure('Check the form'): (Icons.rule, 'Invalid input'),
      const ServerFailure('Server exploded'): (
        Icons.error_outline,
        'Something went wrong',
      ),
      const UnexpectedFailure(): (Icons.error_outline, 'Something went wrong'),
    };

    for (final entry in cases.entries) {
      final failure = entry.key;
      final (icon, title) = entry.value;

      testWidgets('describes ${failure.runtimeType}', (tester) async {
        await tester.pumpWidget(
          buildTestApp(SymphonyErrorView(failure: failure)),
        );

        expect(find.byIcon(icon), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        expect(find.text(failure.message), findsOneWidget);
        expect(SymphonyErrorView.iconFor(failure), icon);
        expect(SymphonyErrorView.titleFor(failure), title);
      });
    }

    testWidgets('uses generic defaults without a failure', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const SymphonyErrorView(message: 'Could not load')),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.byType(SymphonyButton), findsNothing);
    });

    testWidgets('lets the title, message and icon be overridden',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SymphonyErrorView(
            failure: NetworkFailure(),
            title: 'Hors ligne',
            message: 'Vérifiez votre connexion',
            icon: Icons.cloud_off_outlined,
          ),
        ),
      );

      expect(find.text('Hors ligne'), findsOneWidget);
      expect(find.text('Vérifiez votre connexion'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.text('No internet connection'), findsNothing);
      expect(find.byIcon(Icons.wifi_off), findsNothing);
    });

    testWidgets('shows a retry button calling onRetry', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        buildTestApp(
          SymphonyErrorView(
            failure: const TimeoutFailure(),
            onRetry: () => retries++,
          ),
        ),
      );

      expect(find.text('Try again'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('supports a custom retry label', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          SymphonyErrorView(
            failure: const NetworkFailure(),
            retryLabel: 'Réessayer',
            retryIcon: null,
            onRetry: () {},
          ),
        ),
      );

      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('renders a compact inline banner', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        buildTestApp(
          Column(
            children: <Widget>[
              SymphonyErrorView(
                failure: const NetworkFailure(),
                compact: true,
                onRetry: () => retries++,
              ),
            ],
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.wifi_off));
      expect(icon.size, 24);
      expect(find.text('No internet connection'), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
      expect(
        tester.getSize(find.byType(SymphonyErrorView)).height,
        lessThan(120),
      );
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('fits in a small area without overflowing', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          Center(
            child: SizedBox(
              height: 120,
              child: SymphonyErrorView(
                failure: const NetworkFailure(),
                onRetry: () {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('is a live region with a header title', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const SymphonyErrorView(failure: NotFoundFailure())),
      );
      final semantics = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byType(SymphonyErrorView),
              matching: find.byType(Semantics),
            ),
          )
          .toList();

      expect(
        semantics.where((widget) => widget.properties.liveRegion ?? false),
        isNotEmpty,
      );
      final header = find.ancestor(
        of: find.text('Not found'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && (widget.properties.header ?? false),
        ),
      );
      expect(header, findsOneWidget);
    });
  });
}
