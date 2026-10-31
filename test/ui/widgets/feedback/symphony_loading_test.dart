import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

import '../../ui_test_utils.dart';

void main() {
  group('SymphonyLoadingIndicator', () {
    testWidgets('renders a centered indicator of the given size',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(const SymphonyLoadingIndicator(size: 48)),
      );

      final indicator = find.byType(CircularProgressIndicator);
      expect(indicator, findsOneWidget);
      expect(tester.getSize(indicator), const Size(48, 48));
      expect(
          tester.getCenter(indicator), tester.getCenter(find.byType(Scaffold)));
      expect(
        tester.widget<CircularProgressIndicator>(indicator).semanticsLabel,
        'Loading',
      );
    });

    testWidgets('renders the message and uses it as semantics label',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(const SymphonyLoadingIndicator(message: 'Fetching data')),
      );

      expect(find.text('Fetching data'), findsOneWidget);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .semanticsLabel,
        'Fetching data',
      );
    });

    testWidgets('uses the theme colour by default and the given colour',
        (tester) async {
      await tester.pumpWidget(buildTestApp(const SymphonyLoadingIndicator()));
      final theme = SymphonyTheme.light();
      var indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.color, theme.colorScheme.primary);
      expect(indicator.strokeWidth, 4);

      await tester.pumpWidget(
        buildTestApp(
          const SymphonyLoadingIndicator(
            color: Colors.red,
            size: 18,
            semanticsLabel: 'Chargement',
          ),
        ),
      );
      indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.color, Colors.red);
      expect(indicator.strokeWidth, 2);
      expect(indicator.semanticsLabel, 'Chargement');
    });

    testWidgets('supports the adaptive indicator', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SymphonyLoadingIndicator(adaptive: true, color: Colors.green),
        ),
      );
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );

      expect(indicator.valueColor?.value, Colors.green);
    });
  });

  group('SymphonyLoadingOverlay', () {
    Widget overlay({
      required bool isLoading,
      VoidCallback? onTap,
      String? message,
      Color? barrierColor,
      FocusNode? focusNode,
    }) {
      return buildTestApp(
        SymphonyLoadingOverlay(
          isLoading: isLoading,
          message: message,
          barrierColor: barrierColor,
          child: Column(
            children: <Widget>[
              ElevatedButton(onPressed: onTap, child: const Text('Tap me')),
              TextField(focusNode: focusNode),
            ],
          ),
        ),
      );
    }

    testWidgets('lets interactions through when not loading', (tester) async {
      var taps = 0;
      await tester.pumpWidget(overlay(isLoading: false, onTap: () => taps++));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Tap me'));
      expect(taps, 1);
    });

    testWidgets('blocks taps and shows the indicator while loading',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        overlay(isLoading: true, onTap: () => taps++, message: 'Saving'),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Saving'), findsOneWidget);
      await tester.tap(find.text('Tap me'), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('preserves the child state and fades out', (tester) async {
      await tester.pumpWidget(overlay(isLoading: false));
      await tester.enterText(find.byType(TextField), 'draft');

      await tester.pumpWidget(overlay(isLoading: true));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(overlay(isLoading: false));
      await tester.pumpAndSettle();

      expect(find.text('draft'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('removes focus from the child while loading', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(overlay(isLoading: false, focusNode: focusNode));
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await tester.pumpWidget(overlay(isLoading: true, focusNode: focusNode));
      await tester.pump(const Duration(milliseconds: 300));
      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets('uses the given barrier colour', (tester) async {
      const barrier = Color(0x80112233);
      await tester.pumpWidget(overlay(isLoading: true, barrierColor: barrier));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == barrier,
        ),
        findsOneWidget,
      );
    });

    testWidgets('does not change the layout of the child', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SymphonyLoadingOverlay(
            isLoading: false,
            child: SizedBox.expand(key: Key('content')),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const Key('content'))),
        tester.getSize(find.byType(Scaffold)),
      );
    });
  });
}
