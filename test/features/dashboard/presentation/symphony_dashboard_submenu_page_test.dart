import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/access/access_context.dart';
import 'package:symphony_core/src/features/dashboard/dashboard.dart';

import '../dashboard_test_utils.dart';

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder appBarTitled(String title) => find.widgetWithText(AppBar, title);

Finder get allPages =>
    find.byType(SymphonyDashboardSubmenuPage, skipOffstage: false);

void main() {
  group('page presentation', () {
    testWidgets('pushes a page for groups and nested groups', (tester) async {
      await pumpInApp(
        tester,
        createAccessContainer(access: salesUser),
        const SymphonyDashboard(
          items: sampleMenu,
          submenuPresentation: DashboardSubmenuPresentation.page,
        ),
      );

      await tapAndSettle(tester, tile('Sales'));
      expect(allPages, findsOneWidget);
      expect(appBarTitled('Sales'), findsOneWidget);
      expect(tile('Invoices'), findsOneWidget);
      expect(tile('Reports'), findsOneWidget);

      await tapAndSettle(tester, tile('Reports'));
      expect(allPages, findsNWidgets(2));
      expect(appBarTitled('Reports'), findsOneWidget);
      expect(tile('Daily'), findsOneWidget);
      expect(tile('Monthly'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(appBarTitled('Sales'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(allPages, findsNothing);
      expect(tile('Orders'), findsOneWidget);
    });

    testWidgets('pages forward selections and custom tiles', (tester) async {
      final selected = <String>[];
      await pumpInApp(
        tester,
        createAccessContainer(access: salesUser),
        SymphonyDashboard(
          items: sampleMenu,
          submenuPresentation: DashboardSubmenuPresentation.page,
          onItemSelected: (item) => selected.add(item.id),
          tileBuilder:
              (context, item, onTap) => Material(
                child: InkWell(
                  onTap: onTap,
                  child: Center(child: Text('Tile ${item.label}')),
                ),
              ),
        ),
      );

      await tapAndSettle(tester, find.text('Tile Sales'));
      expect(appBarTitled('Sales'), findsOneWidget);
      await tapAndSettle(tester, find.text('Tile Invoices'));

      expect(selected, <String>['sales.invoices']);
    });

    testWidgets('pages refresh their tiles when the access changes', (
      tester,
    ) async {
      final container = createAccessContainer(access: salesUser);
      await pumpInApp(
        tester,
        container,
        const SymphonyDashboard(
          items: sampleMenu,
          submenuPresentation: DashboardSubmenuPresentation.page,
        ),
      );
      await tapAndSettle(tester, tile('Sales'));
      await tapAndSettle(tester, tile('Reports'));
      expect(tile('Monthly'), findsNothing);

      changeAccess(
        container,
        signedIn(
          roles: <String>{'sales'},
          permissions: <String>{'reports.read', 'reports.monthly'},
        ),
      );
      await tester.pumpAndSettle();

      expect(appBarTitled('Reports'), findsOneWidget);
      expect(tile('Monthly'), findsOneWidget);
    });

    testWidgets('pages close when their group becomes unavailable', (
      tester,
    ) async {
      final container = createAccessContainer(access: salesUser);
      await pumpInApp(
        tester,
        container,
        const SymphonyDashboard(
          items: sampleMenu,
          submenuPresentation: DashboardSubmenuPresentation.page,
        ),
      );
      await tapAndSettle(tester, tile('Sales'));
      await tapAndSettle(tester, tile('Reports'));
      expect(allPages, findsNWidgets(2));

      // Losing reports.read closes the Reports page only.
      changeAccess(container, signedIn(roles: <String>{'sales'}));
      await tester.pumpAndSettle();
      expect(allPages, findsOneWidget);
      expect(appBarTitled('Sales'), findsOneWidget);
      expect(tile('Reports'), findsNothing);
      expect(tile('Invoices'), findsOneWidget);

      // Losing the role closes the Sales page as well.
      changeAccess(container, AccessContext.unauthenticated);
      await tester.pumpAndSettle();
      expect(allPages, findsNothing);
      expect(tile('Sales'), findsNothing);
      expect(tile('Orders'), findsOneWidget);
    });

    testWidgets('closes every page whose ancestor group disappears', (
      tester,
    ) async {
      final container = createAccessContainer(access: salesUser);
      await pumpInApp(
        tester,
        container,
        const SymphonyDashboard(
          items: sampleMenu,
          submenuPresentation: DashboardSubmenuPresentation.page,
        ),
      );
      await tapAndSettle(tester, tile('Sales'));
      await tapAndSettle(tester, tile('Reports'));

      changeAccess(container, AccessContext.unauthenticated);
      await tester.pumpAndSettle();

      expect(allPages, findsNothing);
      expect(tile('Orders'), findsOneWidget);
    });

    testWidgets('pages follow the explicit configuration of the dashboard', (
      tester,
    ) async {
      final access = ValueNotifier<AccessContext>(salesUser);
      addTearDown(access.dispose);
      await pumpInApp(
        tester,
        createAccessContainer(),
        ValueListenableBuilder<AccessContext>(
          valueListenable: access,
          builder:
              (context, value, child) => SymphonyDashboard(
                items: sampleMenu,
                accessContext: value,
                submenuPresentation: DashboardSubmenuPresentation.page,
              ),
        ),
      );
      await tapAndSettle(tester, tile('Sales'));
      await tapAndSettle(tester, tile('Reports'));
      expect(tile('Daily'), findsOneWidget);

      access.value = signedIn(roles: <String>{'sales'});
      await tester.pumpAndSettle();

      expect(allPages, findsOneWidget);
      expect(appBarTitled('Sales'), findsOneWidget);
      expect(tile('Invoices'), findsOneWidget);
      expect(tile('Reports'), findsNothing);
    });
  });

  group('standalone page', () {
    Future<void> pumpPage(
      WidgetTester tester,
      ProviderContainer container,
      Widget page,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: page),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('reads the menu and access from providers', (tester) async {
      final container = createAccessContainer(
        menu: sampleMenu,
        access: salesUser,
      );
      await pumpPage(
        tester,
        container,
        const SymphonyDashboardSubmenuPage(groupPath: <String>['sales']),
      );

      expect(appBarTitled('Sales'), findsOneWidget);
      expect(tile('Invoices'), findsOneWidget);

      // Nested groups push another page by default.
      await tapAndSettle(tester, tile('Reports'));
      expect(allPages, findsNWidgets(2));
      expect(appBarTitled('Reports'), findsOneWidget);
      expect(tile('Daily'), findsOneWidget);
    });

    testWidgets('uses a custom title and opener', (tester) async {
      final opened = <List<String>>[];
      await pumpPage(
        tester,
        createAccessContainer(access: salesUser),
        SymphonyDashboardSubmenuPage(
          groupPath: const <String>['sales'],
          items: sampleMenu,
          title: const Text('All sales'),
          onOpenSubmenu: (context, groupPath) => opened.add(groupPath),
        ),
      );

      expect(appBarTitled('All sales'), findsOneWidget);
      await tapAndSettle(tester, tile('Reports'));

      expect(opened, <List<String>>[
        <String>['sales', 'sales.reports'],
      ]);
      expect(allPages, findsOneWidget);
    });

    testWidgets('shows the empty state when it cannot close itself', (
      tester,
    ) async {
      final container = createAccessContainer(access: salesUser);
      await pumpPage(
        tester,
        container,
        const SymphonyDashboardSubmenuPage(
          groupPath: <String>['sales', 'sales.reports'],
          items: sampleMenu,
          emptyTitle: 'Gone',
        ),
      );
      expect(tile('Daily'), findsOneWidget);

      changeAccess(container, AccessContext.unauthenticated);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(allPages, findsOneWidget);
      expect(appBarTitled('Reports'), findsOneWidget);
      expect(tile('Daily'), findsNothing);
      expect(find.text('Gone'), findsOneWidget);
    });

    testWidgets('an unknown group path shows the empty state', (tester) async {
      await pumpPage(
        tester,
        createAccessContainer(access: salesUser),
        const SymphonyDashboardSubmenuPage(
          groupPath: <String>['missing'],
          items: sampleMenu,
        ),
      );

      expect(find.text('No modules available'), findsOneWidget);
      expect(find.byType(SymphonyDashboardTile), findsNothing);
    });
  });
}
