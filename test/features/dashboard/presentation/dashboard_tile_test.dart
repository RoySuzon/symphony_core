import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/dashboard/dashboard.dart';

Future<void> pumpTile(
  WidgetTester tester,
  SymphonyDashboardTile tile, {
  Size size = const Size(180, 180),
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: size.width, height: size.height, child: tile),
        ),
      ),
    ),
  );
}

/// Semantics of the (single) tile on screen.
SemanticsData semanticsOf(WidgetTester tester) =>
    tester.getSemantics(find.byType(SymphonyDashboardTile)).getSemanticsData();

/// The [Semantics] widget annotating the tile as a button (the flag getters
/// of the semantics tree differ between the supported Flutter versions).
Semantics tileSemanticsWidget(WidgetTester tester) {
  return tester.widget<Semantics>(
    find.descendant(
      of: find.byType(SymphonyDashboardTile),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.button == true,
      ),
    ),
  );
}

void main() {
  testWidgets('shows icon, label and description', (tester) async {
    await pumpTile(
      tester,
      const SymphonyDashboardTile(
        item: DashboardItem(
          id: 'orders',
          label: 'Orders',
          description: 'Track every order',
          icon: Icons.receipt_long,
        ),
      ),
    );

    expect(find.byIcon(Icons.receipt_long), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Track every order'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('can hide the description', (tester) async {
    await pumpTile(
      tester,
      const SymphonyDashboardTile(
        showDescription: false,
        item: DashboardItem(id: 'o', label: 'Orders', description: 'Hidden'),
      ),
    );

    expect(find.text('Hidden'), findsNothing);
  });

  testWidgets('renders iconBuilder instead of icon', (tester) async {
    await pumpTile(
      tester,
      SymphonyDashboardTile(
        item: DashboardItem(
          id: 'custom',
          label: 'Custom',
          icon: Icons.star,
          iconBuilder: (context) => Icon(
            Icons.image,
            key: const Key('custom-icon'),
            // Inherits the tile's icon theme.
            color: IconTheme.of(context).color,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('custom-icon')), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
    final icon = tester.widget<Icon>(find.byKey(const Key('custom-icon')));
    final scheme = Theme.of(tester.element(find.byType(Card))).colorScheme;
    expect(icon.color, scheme.onPrimaryContainer);
  });

  testWidgets('falls back to the first letter of the label', (tester) async {
    await pumpTile(
      tester,
      const SymphonyDashboardTile(
        item: DashboardItem(id: 'w', label: ' warehouse'),
      ),
    );

    expect(find.text('W'), findsOneWidget);
  });

  testWidgets('uses the item color for the icon', (tester) async {
    const accent = Color(0xFF2E7D32);
    await pumpTile(
      tester,
      const SymphonyDashboardTile(
        item: DashboardItem(
          id: 'green',
          label: 'Green',
          icon: Icons.eco,
          color: accent,
        ),
      ),
    );

    final iconTheme = IconTheme.of(tester.element(find.byIcon(Icons.eco)));
    expect(iconTheme.color, accent);
  });

  testWidgets('displays badges with text or as a dot', (tester) async {
    await pumpTile(
      tester,
      const SymphonyDashboardTile(
        item: DashboardItem(id: 'b', label: 'Inbox', badge: '12'),
      ),
    );
    expect(find.byType(Badge), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('12')),
      findsOneWidget,
    );

    await pumpTile(
      tester,
      const SymphonyDashboardTile(
        item: DashboardItem(id: 'd', label: 'Dot', badge: ''),
      ),
    );
    expect(tester.widget<Badge>(find.byType(Badge)).label, isNull);
  });

  testWidgets('marks groups with a chevron', (tester) async {
    await pumpTile(
      tester,
      const SymphonyDashboardTile(
        item: DashboardItem(
          id: 'g',
          label: 'Group',
          children: <DashboardItem>[DashboardItem(id: 'g.a', label: 'A')],
        ),
      ),
    );

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('is a single accessible button', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pumpTile(
      tester,
      SymphonyDashboardTile(
        item: const DashboardItem(
          id: 'orders',
          label: 'Orders',
          description: 'Track every order',
          badge: '3',
        ),
        onTap: () => taps++,
      ),
    );

    final data = semanticsOf(tester);
    expect(data.label, 'Orders');
    expect(data.value, '3');
    expect(data.hint, 'Track every order');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    final properties = tileSemanticsWidget(tester).properties;
    expect(properties.button, isTrue);
    expect(properties.enabled, isTrue);

    await tester.tap(find.byType(SymphonyDashboardTile));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('disabled tiles look disabled and ignore taps', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pumpTile(
      tester,
      SymphonyDashboardTile(
        item: const DashboardItem(
          id: 'soon',
          label: 'Soon',
          icon: Icons.lock_clock,
          enabled: false,
        ),
        onTap: () => taps++,
      ),
    );

    await tester.tap(find.byType(SymphonyDashboardTile));
    expect(taps, 0);
    final data = semanticsOf(tester);
    expect(data.label, 'Soon');
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    final properties = tileSemanticsWidget(tester).properties;
    expect(properties.button, isTrue);
    expect(properties.enabled, isFalse);
    final scheme = Theme.of(tester.element(find.byType(Card))).colorScheme;
    final iconTheme =
        IconTheme.of(tester.element(find.byIcon(Icons.lock_clock)));
    expect(iconTheme.color, scheme.onSurface.withAlpha(97));
    semantics.dispose();
  });

  testWidgets('scales down instead of overflowing small cells', (tester) async {
    await pumpTile(
      tester,
      const SymphonyDashboardTile(
        item: DashboardItem(
          id: 'long',
          label: 'A very long module label that needs two lines',
          description: 'And a long description that also wraps on two lines',
          icon: Icons.inventory,
          badge: '99+',
          children: <DashboardItem>[DashboardItem(id: 'x', label: 'X')],
        ),
      ),
      size: const Size(72, 72),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('works with unbounded height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const <Widget>[
              SymphonyDashboardTile(
                item: DashboardItem(
                  id: 'row',
                  label: 'In a list',
                  description: 'Unbounded height',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('In a list'), findsOneWidget);
  });
}
