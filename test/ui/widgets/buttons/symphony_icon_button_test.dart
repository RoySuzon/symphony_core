import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

import '../../ui_test_utils.dart';

Widget _app(Widget button) => buildTestApp(Center(child: button));

void main() {
  group('SymphonyIconButton', () {
    testWidgets('renders every variant with its tooltip', (tester) async {
      final scheme = SymphonyTheme.light().colorScheme;
      final backgrounds = <SymphonyIconButtonVariant, Color?>{
        SymphonyIconButtonVariant.filled: scheme.primary,
        SymphonyIconButtonVariant.tonal: scheme.secondaryContainer,
      };

      for (final variant in SymphonyIconButtonVariant.values) {
        var taps = 0;
        await tester.pumpWidget(
          _app(
            SymphonyIconButton(
              icon: Icons.refresh,
              tooltip: 'Refresh',
              variant: variant,
              onPressed: () => taps++,
            ),
          ),
        );

        expect(find.byType(IconButton), findsOneWidget, reason: '$variant');
        expect(find.byIcon(Icons.refresh), findsOneWidget, reason: '$variant');
        expect(find.byTooltip('Refresh'), findsOneWidget, reason: '$variant');
        final background = backgrounds[variant];
        if (background != null) {
          expect(
            firstMaterialOf(tester, find.byType(IconButton)).color,
            background,
            reason: '$variant',
          );
        }
        await tester.tap(find.byType(SymphonyIconButton));
        expect(taps, 1, reason: '$variant');
      }
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(
        _app(
          const SymphonyIconButton(
            icon: Icons.delete,
            tooltip: 'Delete',
            onPressed: null,
          ),
        ),
      );

      expect(
          tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    });

    testWidgets('shows a spinner and ignores taps while loading',
        (tester) async {
      var taps = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          SymphonyIconButton(
            icon: Icons.sync,
            tooltip: 'Synchronize',
            isLoading: true,
            loadingSemanticsLabel: 'Synchronizing',
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsNothing);
      await tester.tap(find.byType(SymphonyIconButton), warnIfMissed: false);
      expect(taps, 0);
      expect(
        tester.getSemantics(find.byType(SymphonyIconButton)),
        matchesSemantics(
          label: 'Synchronize',
          value: 'Synchronizing',
          isButton: true,
          hasEnabledState: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('applies the icon size and colour', (tester) async {
      await tester.pumpWidget(
        _app(
          SymphonyIconButton(
            icon: Icons.star,
            tooltip: 'Favourite',
            iconSize: 32,
            color: Colors.amber,
            onPressed: () {},
          ),
        ),
      );
      final button = tester.widget<IconButton>(find.byType(IconButton));

      expect(button.iconSize, 32);
      expect(button.color, Colors.amber);
    });
  });
}
