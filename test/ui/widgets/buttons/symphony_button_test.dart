import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

import '../../ui_test_utils.dart';

Widget _app(Widget button) => buildTestApp(Center(child: button));

void main() {
  group('SymphonyButton', () {
    testWidgets('renders the label and calls onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(SymphonyButton(label: 'Save', onPressed: () => taps++)),
      );

      expect(find.text('Save'), findsOneWidget);
      await tester.tap(find.byType(SymphonyButton));
      expect(taps, 1);
    });

    testWidgets('maps every variant to the matching Material button', (
      tester,
    ) async {
      final scheme = SymphonyTheme.light().colorScheme;
      final expectations = <SymphonyButtonVariant, (Type, Color)>{
        SymphonyButtonVariant.primary: (FilledButton, scheme.primary),
        SymphonyButtonVariant.secondary: (
          FilledButton,
          scheme.secondaryContainer,
        ),
        SymphonyButtonVariant.danger: (FilledButton, scheme.error),
        SymphonyButtonVariant.outlined: (OutlinedButton, Colors.transparent),
        SymphonyButtonVariant.text: (TextButton, Colors.transparent),
      };

      for (final entry in expectations.entries) {
        var taps = 0;
        await tester.pumpWidget(
          _app(
            SymphonyButton(
              label: entry.key.name,
              variant: entry.key,
              onPressed: () => taps++,
            ),
          ),
        );
        final (type, background) = entry.value;

        expect(find.byType(type), findsOneWidget, reason: entry.key.name);
        expect(
          firstMaterialOf(tester, find.byType(SymphonyButton)).color,
          background,
          reason: entry.key.name,
        );
        await tester.tap(find.byType(SymphonyButton));
        expect(taps, 1, reason: entry.key.name);
      }
    });

    testWidgets('danger uses the error foreground colour', (tester) async {
      await tester.pumpWidget(
        _app(
          SymphonyButton(
            label: 'Delete',
            icon: Icons.delete_outline,
            variant: SymphonyButtonVariant.danger,
            onPressed: () {},
          ),
        ),
      );
      final scheme = SymphonyTheme.light().colorScheme;
      final text = tester.widget<RichText>(
        find.descendant(
          of: find.text('Delete'),
          matching: find.byType(RichText),
        ),
      );
      final icon = tester.widget<RichText>(
        find.descendant(
          of: find.byIcon(Icons.delete_outline),
          matching: find.byType(RichText),
        ),
      );

      expect(text.text.style?.color, scheme.onError);
      expect(icon.text.style?.color, scheme.onError);
    });

    testWidgets('applies the minimum height of each size', (tester) async {
      for (final size in SymphonyButtonSize.values) {
        await tester.pumpWidget(
          _app(SymphonyButton(label: 'Go', size: size, onPressed: () {})),
        );
        final surface =
            find
                .descendant(
                  of: find.byType(SymphonyButton),
                  matching: find.byType(Material),
                )
                .first;

        expect(tester.getSize(surface).height, size.minHeight, reason: '$size');
      }
      expect(SymphonyButtonSize.small.minHeight, 36);
      expect(SymphonyButtonSize.medium.minHeight, 44);
      expect(SymphonyButtonSize.large.minHeight, 52);
    });

    testWidgets('renders leading and trailing icons sized to the button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SymphonyButton(
            label: 'Next',
            icon: Icons.save,
            trailingIcon: Icons.arrow_forward,
            size: SymphonyButtonSize.large,
            onPressed: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.save), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(Icons.save)).size, 20);
      expect(
        tester.getTopLeft(find.byIcon(Icons.save)).dx,
        lessThan(tester.getTopLeft(find.text('Next')).dx),
      );
      expect(
        tester.getTopLeft(find.byIcon(Icons.arrow_forward)).dx,
        greaterThan(tester.getTopLeft(find.text('Next')).dx),
      );
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(
        _app(const SymphonyButton(label: 'Save', onPressed: null)),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, isFalse);
      expect(button.onPressed, isNull);
    });

    testWidgets('shows a spinner, keeps its width and ignores taps while '
        'loading', (tester) async {
      var taps = 0;
      Widget build({required bool loading}) => _app(
        SymphonyButton(
          label: 'Sign in',
          icon: Icons.login,
          isLoading: loading,
          onPressed: () => taps++,
        ),
      );

      await tester.pumpWidget(build(loading: false));
      final idleSize = tester.getSize(find.byType(SymphonyButton));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpWidget(build(loading: true));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getSize(find.byType(SymphonyButton)), idleSize);
      await tester.tap(find.byType(SymphonyButton), warnIfMissed: false);
      expect(taps, 0);

      // The button keeps its enabled colours and the spinner uses the
      // foreground colour.
      final scheme = SymphonyTheme.light().colorScheme;
      expect(
        firstMaterialOf(tester, find.byType(SymphonyButton)).color,
        scheme.primary,
      );
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.valueColor?.value, scheme.onPrimary);

      await tester.pumpWidget(build(loading: false));
      await tester.tap(find.byType(SymphonyButton));
      expect(taps, 1);
    });

    testWidgets('announces the loading state to screen readers', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          SymphonyButton(
            label: 'Pay',
            isLoading: true,
            loadingSemanticsLabel: 'Processing',
            onPressed: () {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(SymphonyButton)),
        matchesSemantics(
          label: 'Pay',
          value: 'Processing',
          isButton: true,
          hasEnabledState: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('exposes the label to screen readers when idle', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(SymphonyButton(label: 'Pay', onPressed: () {})),
      );

      final node = tester.getSemantics(find.byType(FilledButton));
      expect(node.label, 'Pay');
      expect(node.value, isEmpty);
      semantics.dispose();
    });

    testWidgets('keeps keyboard focus when toggling the loading state', (
      tester,
    ) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      Widget build({required bool loading}) => _app(
        SymphonyButton(
          label: 'Save',
          focusNode: focusNode,
          isLoading: loading,
          onPressed: () {},
        ),
      );

      await tester.pumpWidget(build(loading: false));
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await tester.pumpWidget(build(loading: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('expands to the available width', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          SymphonyButton(label: 'Continue', expanded: true, onPressed: () {}),
        ),
      );

      expect(tester.getSize(find.byType(SymphonyButton)).width, 800);
    });

    testWidgets('shows the tooltip and merges custom styles', (tester) async {
      await tester.pumpWidget(
        _app(
          SymphonyButton(
            label: 'Archive',
            tooltip: 'Archive the selected items',
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () {},
          ),
        ),
      );

      expect(find.byTooltip('Archive the selected items'), findsOneWidget);
      expect(
        firstMaterialOf(tester, find.byType(SymphonyButton)).color,
        Colors.teal,
      );
    });

    testWidgets('follows the theme corner radius', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          Center(child: SymphonyButton(label: 'Go', onPressed: () {})),
          theme: SymphonyTheme.light(
            const SymphonyThemeConfig(cornerRadius: 4),
          ),
        ),
      );
      final shape = firstMaterialOf(tester, find.byType(SymphonyButton)).shape;

      expect(shape, isA<RoundedRectangleBorder>());
      expect(
        (shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(4),
      );
    });
  });
}
