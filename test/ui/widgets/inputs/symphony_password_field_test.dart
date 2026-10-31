import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

import '../../ui_test_utils.dart';

Widget _app(Widget field) => buildTestApp(
      Padding(padding: const EdgeInsets.all(16), child: field),
    );

bool _isObscured(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).obscureText;

void main() {
  group('SymphonyPasswordField', () {
    testWidgets('hides the text and toggles its visibility', (tester) async {
      await tester.pumpWidget(_app(const SymphonyPasswordField()));

      expect(find.text('Password'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(_isObscured(tester), isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(_isObscured(tester), isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(_isObscured(tester), isTrue);
    });

    testWidgets('uses custom tooltips, label and prefix icon', (tester) async {
      await tester.pumpWidget(
        _app(
          const SymphonyPasswordField(
            label: 'Mot de passe',
            prefixIcon: Icons.key,
            showPasswordTooltip: 'Afficher',
            hidePasswordTooltip: 'Masquer',
          ),
        ),
      );

      expect(find.text('Mot de passe'), findsOneWidget);
      expect(find.byIcon(Icons.key), findsOneWidget);
      expect(find.byTooltip('Afficher'), findsOneWidget);
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(find.byTooltip('Masquer'), findsOneWidget);
    });

    testWidgets('disables the toggle when the field is disabled',
        (tester) async {
      await tester.pumpWidget(
        _app(const SymphonyPasswordField(enabled: false)),
      );

      expect(
          tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('does not show the strength meter by default', (tester) async {
      await tester.pumpWidget(_app(const SymphonyPasswordField()));

      expect(find.byType(SymphonyPasswordStrengthMeter), findsNothing);
    });

    testWidgets('shows the strength level while typing', (tester) async {
      await tester.pumpWidget(
        _app(const SymphonyPasswordField(showStrengthIndicator: true)),
      );

      expect(find.byType(SymphonyPasswordStrengthMeter), findsOneWidget);
      for (final label in <String>['Weak', 'Fair', 'Good', 'Strong']) {
        expect(find.text(label), findsNothing);
      }

      final expectations = <String, String>{
        'abc': 'Weak',
        'Zebracat9': 'Fair',
        'Zebra-cat9': 'Good',
        'Zebra-cat9-Moon': 'Strong',
      };
      for (final entry in expectations.entries) {
        await tester.enterText(find.byType(TextField), entry.key);
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      }

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('Strong'), findsNothing);
      expect(find.text('Weak'), findsNothing);
    });

    testWidgets('uses custom strength labels', (tester) async {
      await tester.pumpWidget(
        _app(
          const SymphonyPasswordField(
            showStrengthIndicator: true,
            strengthLabels: <PasswordStrength, String>{
              PasswordStrength.weak: 'Faible',
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pumpAndSettle();
      expect(find.text('Faible'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Zebra-cat9-Moon');
      await tester.pumpAndSettle();
      expect(find.text('Strong'), findsOneWidget);
    });

    testWidgets('reports strength changes and text changes', (tester) async {
      final strengths = <PasswordStrength>[];
      final changes = <String>[];
      await tester.pumpWidget(
        _app(
          SymphonyPasswordField(
            onChanged: changes.add,
            onStrengthChanged: (result) => strengths.add(result.strength),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.enterText(find.byType(TextField), 'Zebra-cat9-Moon');
      await tester.enterText(find.byType(TextField), '');

      expect(changes, <String>['abc', 'Zebra-cat9-Moon', '']);
      expect(strengths, <PasswordStrength>[
        PasswordStrength.weak,
        PasswordStrength.strong,
        PasswordStrength.weak,
      ]);
    });

    testWidgets('works with an external controller', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          SymphonyPasswordField(
            controller: controller,
            showStrengthIndicator: true,
          ),
        ),
      );

      controller.text = r'Xk9#mP2$vL7!qR4&';
      await tester.pumpAndSettle();
      expect(find.text('Strong'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pumpAndSettle();
      expect(controller.text, 'abc');
      expect(find.text('Weak'), findsOneWidget);
    });

    testWidgets('switches between internal and external controllers',
        (tester) async {
      final external = TextEditingController(text: 'Zebra-cat9-Moon');
      addTearDown(external.dispose);
      TextEditingController? current;
      late StateSetter setOuterState;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              setOuterState = setState;
              return SymphonyPasswordField(
                controller: current,
                showStrengthIndicator: true,
              );
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pumpAndSettle();
      expect(find.text('Weak'), findsOneWidget);

      setOuterState(() => current = external);
      await tester.pumpAndSettle();
      expect(find.text('Strong'), findsOneWidget);

      setOuterState(() => current = null);
      await tester.pumpAndSettle();
      // The internal controller is seeded with the previous external text.
      expect(find.text('Strong'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pumpAndSettle();
      expect(find.text('Weak'), findsOneWidget);
      expect(external.text, 'Zebra-cat9-Moon');
    });

    testWidgets('keeps the form field state when toggling the indicator',
        (tester) async {
      late StateSetter setOuterState;
      var showIndicator = false;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              setOuterState = setState;
              return SymphonyPasswordField(
                showStrengthIndicator: showIndicator,
              );
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Zebra-cat9');
      setOuterState(() => showIndicator = true);
      await tester.pumpAndSettle();

      expect(find.text('Good'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Zebra-cat9',
      );
    });

    testWidgets('validates and saves through the enclosing form',
        (tester) async {
      final formKey = GlobalKey<FormState>();
      String? saved;
      await tester.pumpWidget(
        _app(
          Form(
            key: formKey,
            child: SymphonyPasswordField(
              validator: (value) =>
                  (value ?? '').length < 8 ? 'Too short' : null,
              onSaved: (value) => saved = value,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'short');
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Too short'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'long enough');
      expect(formKey.currentState!.validate(), isTrue);
      formKey.currentState!.save();
      expect(saved, 'long enough');
    });

    testWidgets('forwards autofill hints and disables suggestions',
        (tester) async {
      await tester.pumpWidget(
        _app(
          const SymphonyPasswordField(
            autofillHints: <String>[AutofillHints.newPassword],
          ),
        ),
      );
      final editable = tester.widget<EditableText>(find.byType(EditableText));

      expect(
        tester.widget<TextField>(find.byType(TextField)).autofillHints,
        <String>[AutofillHints.newPassword],
      );
      expect(editable.autocorrect, isFalse);
      expect(editable.enableSuggestions, isFalse);
    });
  });

  group('SymphonyPasswordStrengthMeter', () {
    testWidgets('fills one segment per level with the level colour',
        (tester) async {
      final theme = SymphonyTheme.light();
      for (final strength in PasswordStrength.values) {
        await tester.pumpWidget(
          buildTestApp(
            SymphonyPasswordStrengthMeter(
              result: PasswordStrengthResult(strength: strength, score: 50),
            ),
            theme: theme,
          ),
        );
        await tester.pumpAndSettle();
        final activeColor =
            SymphonyPasswordStrengthMeter.colorFor(strength, theme);
        final colors = tester
            .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
            .map((container) => (container.decoration! as BoxDecoration).color)
            .toList();

        expect(colors, hasLength(4));
        expect(
          colors.where((color) => color == activeColor),
          hasLength(strength.index + 1),
          reason: '$strength',
        );
      }
    });

    testWidgets('uses distinct colours for each level', (tester) async {
      final theme = SymphonyTheme.light();
      final colors = PasswordStrength.values
          .map((strength) =>
              SymphonyPasswordStrengthMeter.colorFor(strength, theme))
          .toSet();

      expect(colors, hasLength(PasswordStrength.values.length));
      expect(
        SymphonyPasswordStrengthMeter.colorFor(PasswordStrength.weak, theme),
        theme.colorScheme.error,
      );
      expect(
        SymphonyPasswordStrengthMeter.colorFor(PasswordStrength.strong, theme),
        SymphonyColors.light.success,
      );
    });

    testWidgets('renders empty segments without a label for a null result',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(const SymphonyPasswordStrengthMeter(result: null)),
      );

      expect(find.byType(Text), findsNothing);
      expect(find.byType(AnimatedContainer), findsNWidgets(4));
    });

    testWidgets('exposes the level to screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        buildTestApp(
          const SymphonyPasswordStrengthMeter(
            result: PasswordStrengthResult(
              strength: PasswordStrength.good,
              score: 60,
            ),
            semanticsLabel: 'Robustesse',
          ),
        ),
      );

      final node = tester.getSemantics(
        find.byType(SymphonyPasswordStrengthMeter),
      );
      expect(node.label, 'Robustesse');
      expect(node.value, 'Good');
      semantics.dispose();
    });

    testWidgets('can hide the label', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SymphonyPasswordStrengthMeter(
            result: PasswordStrengthResult(
              strength: PasswordStrength.fair,
              score: 40,
            ),
            showLabel: false,
          ),
        ),
      );

      expect(find.text('Fair'), findsNothing);
    });
  });
}
