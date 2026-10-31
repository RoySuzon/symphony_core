import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

/// Wraps [child] in a [MaterialApp] + [Scaffold] using [theme] (the
/// symphony light theme by default).
Widget buildTestApp(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? SymphonyTheme.light(),
    home: Scaffold(body: child),
  );
}

/// Pumps an empty [buildTestApp] and returns a context below the scaffold,
/// suitable for showing dialogs and snack bars.
Future<BuildContext> pumpTestContext(
  WidgetTester tester, {
  ThemeData? theme,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    buildTestApp(
      Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.expand();
        },
      ),
      theme: theme,
    ),
  );
  return captured;
}

/// The first [Material] drawn by the widget found by [finder] (for buttons,
/// the button surface).
Material firstMaterialOf(WidgetTester tester, Finder finder) {
  return tester.widget<Material>(
    find.descendant(of: finder, matching: find.byType(Material)).first,
  );
}

/// Gives [child] a tight [width] (which may exceed the test surface) inside
/// a left-to-right [Directionality].
Widget withWidth(double width, Widget child, {double height = 200}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 0,
      maxWidth: width,
      minHeight: 0,
      maxHeight: height,
      child: SizedBox(width: width, height: height, child: child),
    ),
  );
}
