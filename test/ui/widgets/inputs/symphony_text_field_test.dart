import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

import '../../ui_test_utils.dart';

Widget _app(Widget field, {ThemeData? theme}) => buildTestApp(
  Padding(padding: const EdgeInsets.all(16), child: field),
  theme: theme,
);

void main() {
  group('SymphonyTextField', () {
    testWidgets('renders the label, helper, error and icons', (tester) async {
      await tester.pumpWidget(
        _app(
          const SymphonyTextField(
            label: 'E-mail',
            helperText: 'We never share it',
            errorText: 'Invalid e-mail',
            prefixIcon: Icons.alternate_email,
            suffix: Icon(Icons.check, key: Key('suffix')),
          ),
        ),
      );

      expect(find.text('E-mail'), findsOneWidget);
      expect(find.text('Invalid e-mail'), findsOneWidget);
      expect(find.byIcon(Icons.alternate_email), findsOneWidget);
      expect(find.byKey(const Key('suffix')), findsOneWidget);
    });

    testWidgets('renders the hint and the helper text', (tester) async {
      await tester.pumpWidget(
        _app(const SymphonyTextField(hint: 'Search', helperText: 'Helper')),
      );

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Helper'), findsOneWidget);
    });

    testWidgets('uses an outline border with the theme radius', (tester) async {
      await tester.pumpWidget(_app(const SymphonyTextField(label: 'Name')));
      var border =
          tester.widget<TextField>(find.byType(TextField)).decoration!.border;

      expect(border, isA<OutlineInputBorder>());
      expect(
        (border! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(12),
      );

      await tester.pumpWidget(
        _app(
          const SymphonyTextField(label: 'Name'),
          theme: SymphonyTheme.light(
            const SymphonyThemeConfig(cornerRadius: 20),
          ),
        ),
      );
      // MaterialApp animates theme changes (the radius extension is lerped).
      await tester.pumpAndSettle();
      border =
          tester.widget<TextField>(find.byType(TextField)).decoration!.border;
      expect(
        (border! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(20),
      );
    });

    testWidgets('reports changes, submissions and taps', (tester) async {
      final changes = <String>[];
      final submissions = <String>[];
      var taps = 0;
      await tester.pumpWidget(
        _app(
          SymphonyTextField(
            onChanged: changes.add,
            onSubmitted: submissions.add,
            onTap: () => taps++,
            textInputAction: TextInputAction.done,
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(taps, 1);
      expect(changes, <String>['hello']);
      expect(submissions, <String>['hello']);
    });

    testWidgets('participates in form validation and saving', (tester) async {
      final formKey = GlobalKey<FormState>();
      String? saved;
      await tester.pumpWidget(
        _app(
          Form(
            key: formKey,
            child: SymphonyTextField(
              label: 'Name',
              validator:
                  (value) => value == null || value.isEmpty ? 'Required' : null,
              onSaved: (value) => saved = value,
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Ada');
      expect(formKey.currentState!.validate(), isTrue);
      formKey.currentState!.save();
      await tester.pump();
      expect(find.text('Required'), findsNothing);
      expect(saved, 'Ada');
    });

    testWidgets('supports an initial value or a controller', (tester) async {
      await tester.pumpWidget(
        _app(const SymphonyTextField(initialValue: 'initial')),
      );
      expect(find.text('initial'), findsOneWidget);

      final controller = TextEditingController(text: 'from controller');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(SymphonyTextField(controller: controller)));
      expect(find.text('from controller'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'typed');
      expect(controller.text, 'typed');
    });

    testWidgets('obscured text is single line without suggestions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SymphonyTextField(obscureText: true, maxLines: 4, minLines: 2),
        ),
      );
      final editable = tester.widget<EditableText>(find.byType(EditableText));

      expect(editable.obscureText, isTrue);
      expect(editable.maxLines, 1);
      expect(editable.minLines, isNull);
      expect(editable.autocorrect, isFalse);
      expect(editable.enableSuggestions, isFalse);
    });

    testWidgets('forwards the input configuration', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        _app(
          SymphonyTextField(
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            maxLines: 3,
            minLines: 2,
            autofillHints: const <String>[AutofillHints.name],
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            focusNode: focusNode,
            textAlign: TextAlign.end,
            readOnly: true,
          ),
        ),
      );
      final editable = tester.widget<EditableText>(find.byType(EditableText));

      expect(editable.keyboardType, TextInputType.number);
      expect(editable.textInputAction, TextInputAction.next);
      expect(editable.textCapitalization, TextCapitalization.words);
      expect(editable.maxLines, 3);
      expect(editable.minLines, 2);
      // Older Flutter versions forward the hints through the TextField's own
      // autofill client instead of EditableText.autofillHints.
      expect(
        tester.widget<TextField>(find.byType(TextField)).autofillHints,
        <String>[AutofillHints.name],
      );
      expect(editable.focusNode, same(focusNode));
      expect(editable.textAlign, TextAlign.end);
      expect(editable.readOnly, isTrue);
    });

    testWidgets('filters input with the formatters', (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(
        _app(
          SymphonyTextField(
            onChanged: changes.add,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'a1b2');
      expect(changes.last, '12');
    });

    testWidgets('can be disabled', (tester) async {
      await tester.pumpWidget(_app(const SymphonyTextField(enabled: false)));

      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('shows a counter, prefix and suffix texts', (tester) async {
      await tester.pumpWidget(
        _app(
          const SymphonyTextField(
            initialValue: '42',
            maxLength: 10,
            prefixText: r'$',
            suffixText: 'USD',
          ),
        ),
      );

      expect(find.text('2/10'), findsOneWidget);
      expect(find.text(r'$'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
    });
  });
}
