import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

void main() {
  Future<BuildContext> pumpWithTheme(
      WidgetTester tester, ThemeData theme) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return captured;
  }

  group('SymphonyContextX', () {
    testWidgets('exposes the theme, color scheme and text theme',
        (tester) async {
      final theme = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      );

      final context = await pumpWithTheme(tester, theme);

      expect(context.theme, Theme.of(context));
      expect(context.colorScheme, Theme.of(context).colorScheme);
      expect(context.colorScheme.primary, theme.colorScheme.primary);
      expect(context.textTheme, Theme.of(context).textTheme);
      expect(context.isDarkMode, isFalse);
    });

    testWidgets('isDarkMode follows the theme brightness', (tester) async {
      final theme = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      );

      final context = await pumpWithTheme(tester, theme);

      expect(context.isDarkMode, isTrue);
    });

    testWidgets('unfocus removes the focus from a text field', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return TextField(focusNode: focusNode);
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      captured.unfocus();
      await tester.pump();

      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets('unfocus does nothing when nothing is focused', (tester) async {
      final context = await pumpWithTheme(tester, ThemeData());

      expect(context.unfocus, returnsNormally);
    });
  });
}
