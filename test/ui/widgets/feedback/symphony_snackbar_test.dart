import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/ui/ui.dart';

import '../../ui_test_utils.dart';

SnackBar _snackBar(WidgetTester tester) =>
    tester.widget<SnackBar>(find.byType(SnackBar));

void main() {
  group('SymphonySnackbar', () {
    testWidgets('shows an info snack bar by default', (tester) async {
      final context = await pumpTestContext(tester);

      SymphonySnackbar.show(context, 'Draft saved');
      await tester.pumpAndSettle();

      expect(find.text('Draft saved'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      final snackBar = _snackBar(tester);
      expect(snackBar.backgroundColor, SymphonyColors.light.info);
      expect(snackBar.behavior, SnackBarBehavior.floating);
      expect(snackBar.duration, const Duration(seconds: 4));
      expect(snackBar.action, isNull);
      expect(snackBar.showCloseIcon, isFalse);
    });

    testWidgets('styles every type with the theme colours', (tester) async {
      final theme = SymphonyTheme.light();
      final context = await pumpTestContext(tester, theme: theme);
      final expectations = <SymphonySnackbarType, (Color, Color, IconData)>{
        SymphonySnackbarType.info: (
          SymphonyColors.light.info,
          SymphonyColors.light.onInfo,
          Icons.info_outline,
        ),
        SymphonySnackbarType.success: (
          SymphonyColors.light.success,
          SymphonyColors.light.onSuccess,
          Icons.check_circle_outline,
        ),
        SymphonySnackbarType.warning: (
          SymphonyColors.light.warning,
          SymphonyColors.light.onWarning,
          Icons.warning_amber_rounded,
        ),
        SymphonySnackbarType.error: (
          theme.colorScheme.error,
          theme.colorScheme.onError,
          Icons.error_outline,
        ),
      };

      for (final entry in expectations.entries) {
        SymphonySnackbar.show(context, entry.key.name, type: entry.key);
        await tester.pumpAndSettle();
        final (background, foreground, icon) = entry.value;

        expect(_snackBar(tester).backgroundColor, background);
        expect(
          tester.widget<Icon>(find.byIcon(icon)).color,
          foreground,
          reason: entry.key.name,
        );
        expect(
          tester.widget<Text>(find.text(entry.key.name)).style?.color,
          foreground,
        );
        expect(SymphonySnackbar.iconFor(entry.key), icon);
      }
    });

    testWidgets('shorthands use the matching type', (tester) async {
      final theme = SymphonyTheme.light();
      final context = await pumpTestContext(tester, theme: theme);

      SymphonySnackbar.success(context, 'Saved');
      await tester.pumpAndSettle();
      expect(_snackBar(tester).backgroundColor, SymphonyColors.light.success);

      SymphonySnackbar.warning(context, 'Careful');
      await tester.pumpAndSettle();
      expect(_snackBar(tester).backgroundColor, SymphonyColors.light.warning);

      SymphonySnackbar.info(context, 'FYI');
      await tester.pumpAndSettle();
      expect(_snackBar(tester).backgroundColor, SymphonyColors.light.info);

      SymphonySnackbar.error(context, 'Failed');
      await tester.pumpAndSettle();
      expect(_snackBar(tester).backgroundColor, theme.colorScheme.error);
      expect(_snackBar(tester).duration, const Duration(seconds: 6));
    });

    testWidgets('hides the current snack bar before showing a new one',
        (tester) async {
      final context = await pumpTestContext(tester);

      SymphonySnackbar.show(context, 'First');
      await tester.pumpAndSettle();
      SymphonySnackbar.show(context, 'Second');
      await tester.pumpAndSettle();

      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('runs the action and shows a close icon', (tester) async {
      final context = await pumpTestContext(tester);
      var undone = 0;

      SymphonySnackbar.show(
        context,
        'Item deleted',
        actionLabel: 'Undo',
        onAction: () => undone++,
        duration: const Duration(seconds: 10),
      );
      await tester.pumpAndSettle();

      expect(_snackBar(tester).duration, const Duration(seconds: 10));
      expect(_snackBar(tester).showCloseIcon, isTrue);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, 1);
      expect(find.text('Item deleted'), findsNothing);
    });

    testWidgets('can hide the icon and the close icon', (tester) async {
      final context = await pumpTestContext(tester);

      SymphonySnackbar.show(
        context,
        'Plain',
        showIcon: false,
        actionLabel: 'OK',
        showCloseIcon: false,
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.info_outline), findsNothing);
      expect(_snackBar(tester).showCloseIcon, isFalse);
    });

    testWidgets('showFailure displays the failure message as an error',
        (tester) async {
      final theme = SymphonyTheme.light();
      final context = await pumpTestContext(tester, theme: theme);

      final controller = SymphonySnackbar.showFailure(
        context,
        const NetworkFailure(),
      );
      await tester.pumpAndSettle();

      expect(find.text(const NetworkFailure().message), findsOneWidget);
      expect(_snackBar(tester).backgroundColor, theme.colorScheme.error);

      controller.close();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(await controller.closed, SnackBarClosedReason.hide);
    });

    testWidgets('falls back to the default colours without the extension',
        (tester) async {
      final context = await pumpTestContext(
        tester,
        theme: ThemeData(useMaterial3: true),
      );

      SymphonySnackbar.success(context, 'Done');
      await tester.pumpAndSettle();

      expect(_snackBar(tester).backgroundColor, SymphonyColors.light.success);
    });
  });
}
