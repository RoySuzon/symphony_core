import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

import '../../ui_test_utils.dart';

void main() {
  group('SymphonyDialogs.confirm', () {
    testWidgets('completes with true when confirmed', (tester) async {
      final context = await pumpTestContext(tester);

      final result = SymphonyDialogs.confirm(
        context,
        title: 'Delete project?',
        message: 'This cannot be undone.',
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete project?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(await result, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('completes with false when cancelled', (tester) async {
      final context = await pumpTestContext(tester);

      final result = SymphonyDialogs.confirm(context, title: 'Leave?');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await result, isFalse);
    });

    testWidgets('completes with false when dismissed', (tester) async {
      final context = await pumpTestContext(tester);

      final result = SymphonyDialogs.confirm(context, title: 'Leave?');
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(await result, isFalse);
    });

    testWidgets('uses custom labels and destructive styling', (tester) async {
      final theme = SymphonyTheme.light();
      final context = await pumpTestContext(tester, theme: theme);

      final result = SymphonyDialogs.confirm(
        context,
        title: 'Supprimer ?',
        confirmLabel: 'Supprimer',
        cancelLabel: 'Annuler',
        destructive: true,
        icon: Icons.delete_outline,
      );
      await tester.pumpAndSettle();

      expect(find.text('Annuler'), findsOneWidget);
      final confirmButton = find.widgetWithText(SymphonyButton, 'Supprimer');
      expect(
        tester.widget<SymphonyButton>(confirmButton).variant,
        SymphonyButtonVariant.danger,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color,
        theme.colorScheme.error,
      );
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('can disable barrier dismissal', (tester) async {
      final context = await pumpTestContext(tester);

      final result = SymphonyDialogs.confirm(
        context,
        title: 'Required',
        barrierDismissible: false,
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });
  });

  group('SymphonyDialogs.alert', () {
    testWidgets('shows the message and closes with the button', (tester) async {
      final context = await pumpTestContext(tester);
      var closed = false;

      unawaited(
        SymphonyDialogs.alert(
          context,
          title: 'Saved',
          message: 'Your changes were saved.',
          buttonLabel: 'Great',
          icon: Icons.check,
        ).then((_) => closed = true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Your changes were saved.'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('Great'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('SymphonyDialogs.prompt', () {
    testWidgets('completes with the entered text', (tester) async {
      final context = await pumpTestContext(tester);

      final result = SymphonyDialogs.prompt(
        context,
        title: 'Rename',
        label: 'Name',
        initialValue: 'Old name',
      );
      await tester.pumpAndSettle();

      expect(find.text('Old name'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'New name');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(await result, 'New name');
    });

    testWidgets('submits with the keyboard action', (tester) async {
      final context = await pumpTestContext(tester);

      final result = SymphonyDialogs.prompt(context, title: 'Code');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(await result, '1234');
    });

    testWidgets('completes with null when cancelled', (tester) async {
      final context = await pumpTestContext(tester);

      final result = SymphonyDialogs.prompt(
        context,
        title: 'Rename',
        cancelLabel: 'Annuler',
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ignored');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(await result, isNull);
    });

    testWidgets('validates the text before completing', (tester) async {
      final context = await pumpTestContext(tester);

      final result = SymphonyDialogs.prompt(
        context,
        title: 'E-mail',
        confirmLabel: 'Send',
        validator: (value) =>
            value != null && value.contains('@') ? null : 'Invalid e-mail',
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid e-mail'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'a@b.co');
      await tester.pumpAndSettle();
      expect(find.text('Invalid e-mail'), findsNothing);
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(await result, 'a@b.co');
    });
  });

  group('SymphonyDialogs.showLoading', () {
    testWidgets('shows a blocking dialog until closed', (tester) async {
      final context = await pumpTestContext(tester);

      final handle = SymphonyDialogs.showLoading(context, message: 'Saving');
      await tester.pump(const Duration(milliseconds: 300));

      expect(handle.isOpen, isTrue);
      expect(find.text('Saving'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Tapping the barrier does not dismiss the dialog.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Saving'), findsOneWidget);

      handle.close();
      handle.close();
      await tester.pumpAndSettle();

      expect(handle.isOpen, isFalse);
      expect(find.text('Saving'), findsNothing);
      await expectLater(handle.closed, completes);
    });

    testWidgets('close only removes the loading dialog', (tester) async {
      final context = await pumpTestContext(tester);
      final navigator = Navigator.of(context);

      final handle = SymphonyDialogs.showLoading(context);
      await tester.pump(const Duration(milliseconds: 300));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Text('Next page')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      handle.close();
      await tester.pumpAndSettle();

      expect(handle.isOpen, isFalse);
      expect(find.text('Next page'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('close is a no-op once the user navigated back',
        (tester) async {
      final context = await pumpTestContext(tester);
      final navigator = Navigator.of(context);

      final handle = SymphonyDialogs.showLoading(context);
      await tester.pump(const Duration(milliseconds: 300));
      navigator.pop();
      await tester.pumpAndSettle();

      expect(handle.isOpen, isFalse);
      handle.close();
      await tester.pumpAndSettle();
      // The home route is still displayed.
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('notices when another navigation removes the dialog',
        (tester) async {
      final context = await pumpTestContext(tester);
      final navigator = Navigator.of(context);
      var closedCompleted = false;

      final handle = SymphonyDialogs.showLoading(context, message: 'Saving');
      unawaited(handle.closed.then((_) => closedCompleted = true));
      await tester.pump(const Duration(milliseconds: 300));
      // For example a sign-out flow replacing the whole stack.
      unawaited(
        navigator.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const Text('Signed out')),
          (route) => false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Signed out'), findsOneWidget);
      expect(find.text('Saving'), findsNothing);
      expect(handle.isOpen, isFalse);
      expect(closedCompleted, isTrue);

      handle.close();
      await tester.pumpAndSettle();
      expect(find.text('Signed out'), findsOneWidget, reason: 'no extra pop');
    });

    testWidgets('close right after showLoading removes the dialog',
        (tester) async {
      final context = await pumpTestContext(tester);

      final handle = SymphonyDialogs.showLoading(context, message: 'Saving');
      handle.close();
      await tester.pumpAndSettle();

      expect(handle.isOpen, isFalse);
      expect(find.text('Saving'), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('SymphonyDialogs.runWithLoading', () {
    testWidgets('returns the task result and closes the dialog',
        (tester) async {
      final context = await pumpTestContext(tester);
      final completer = Completer<int>();

      final result = SymphonyDialogs.runWithLoading(
        context,
        () => completer.future,
        message: 'Working',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Working'), findsOneWidget);

      completer.complete(42);
      await tester.pumpAndSettle();

      expect(await result, 42);
      expect(find.text('Working'), findsNothing);
    });

    testWidgets('closes the dialog and rethrows when the task fails',
        (tester) async {
      final context = await pumpTestContext(tester);
      final completer = Completer<int>();

      final result = SymphonyDialogs.runWithLoading(
        context,
        () => completer.future,
      );
      final expectation = expectLater(result, throwsA(isA<StateError>()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.completeError(StateError('boom'));
      await tester.pumpAndSettle();

      await expectation;
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
