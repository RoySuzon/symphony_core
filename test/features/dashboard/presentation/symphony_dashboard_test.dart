import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/access/access_context.dart';
import 'package:symphony_core/src/core/access/access_requirement.dart';
import 'package:symphony_core/src/features/dashboard/dashboard.dart';
import 'package:symphony_core/src/ui/widgets/feedback/symphony_empty_state.dart';

import '../dashboard_test_utils.dart';

/// Header with internal state, used to check that it survives level changes.
class _CounterHeader extends StatefulWidget {
  const _CounterHeader();

  @override
  State<_CounterHeader> createState() => _CounterHeaderState();
}

class _CounterHeaderState extends State<_CounterHeader> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => _count++),
      child: Text('Header taps: $_count'),
    );
  }
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('visibility', () {
    testWidgets('renders only the tiles the user may see', (tester) async {
      final container = createAccessContainer(
        access: signedIn(roles: <String>{'sales'}),
      );
      await pumpInApp(
        tester,
        container,
        const SymphonyDashboard(items: sampleMenu),
      );

      expect(tile('Orders'), findsOneWidget);
      expect(tile('Sales'), findsOneWidget);
      expect(tile('Help'), findsOneWidget);
      expect(tile('Admin'), findsNothing);
      expect(find.byType(SymphonyDashboardTile), findsNWidgets(3));
    });

    testWidgets('reacts to access changes at runtime', (tester) async {
      final container = createAccessContainer();
      await pumpInApp(
        tester,
        container,
        const SymphonyDashboard(items: sampleMenu),
      );
      expect(find.byType(SymphonyDashboardTile), findsNWidgets(2));
      expect(tile('Sales'), findsNothing);

      changeAccess(container, signedIn(roles: <String>{'admin'}));
      await tester.pumpAndSettle();
      expect(tile('Sales'), findsOneWidget);
      expect(tile('Admin'), findsOneWidget);

      changeAccess(container, AccessContext.unauthenticated);
      await tester.pumpAndSettle();
      expect(tile('Sales'), findsNothing);
      expect(tile('Admin'), findsNothing);
      expect(tile('Orders'), findsOneWidget);
    });

    testWidgets('reads the menu and the access from providers by default',
        (tester) async {
      final container = createAccessContainer(
        menu: sampleMenu,
        access: signedIn(roles: <String>{'admin'}),
      );
      await pumpInApp(tester, container, const SymphonyDashboard());

      expect(find.byType(SymphonyDashboardTile), findsNWidgets(4));

      changeAccess(container, AccessContext.unauthenticated);
      await tester.pumpAndSettle();
      expect(find.byType(SymphonyDashboardTile), findsNWidgets(2));
    });

    testWidgets('an explicit accessContext overrides the provider',
        (tester) async {
      final container = createAccessContainer(menu: sampleMenu);
      await pumpInApp(
        tester,
        container,
        SymphonyDashboard(accessContext: signedIn(roles: <String>{'admin'})),
      );

      expect(tile('Admin'), findsOneWidget);
    });

    testWidgets('keeps disabled items visible but ignores their taps',
        (tester) async {
      final selected = <String>[];
      await pumpInApp(
        tester,
        createAccessContainer(),
        SymphonyDashboard(
          onItemSelected: (item) => selected.add(item.id),
          items: const <DashboardItem>[
            DashboardItem(
              id: 'soon',
              label: 'Soon',
              route: '/soon',
              enabled: false,
            ),
            DashboardItem(
              id: 'off',
              label: 'Off group',
              enabled: false,
              children: <DashboardItem>[DashboardItem(id: 'off.a', label: 'A')],
            ),
          ],
        ),
      );

      expect(tile('Soon'), findsOneWidget);
      await tapAndSettle(tester, tile('Soon'));
      await tapAndSettle(tester, tile('Off group'));

      expect(selected, isEmpty);
      expect(tile('A'), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);
    });

    testWidgets('rejects duplicate ids in debug builds', (tester) async {
      await pumpInApp(
        tester,
        createAccessContainer(),
        const SymphonyDashboard(
          items: <DashboardItem>[
            DashboardItem(id: 'same', label: 'A'),
            DashboardItem(id: 'same', label: 'B'),
          ],
        ),
      );

      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (error) => error.message,
          'message',
          contains('Duplicate DashboardItem ids'),
        ),
      );
    });
  });

  group('inline submenus', () {
    testWidgets('open, go back and jump through three levels', (tester) async {
      await pumpInApp(
        tester,
        createAccessContainer(access: salesUser),
        const SymphonyDashboard(items: sampleMenu),
      );
      expect(find.byTooltip('Back'), findsNothing);

      // Level 1: Sales.
      await tapAndSettle(tester, tile('Sales'));
      expect(tile('Orders'), findsNothing);
      expect(tile('Invoices'), findsOneWidget);
      expect(tile('Reports'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Home'), findsOneWidget);
      expect(find.text('Sales'), findsOneWidget);

      // Level 2: Sales > Reports (Monthly requires another permission).
      await tapAndSettle(tester, tile('Reports'));
      expect(tile('Daily'), findsOneWidget);
      expect(tile('Monthly'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Home'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Sales'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);

      // Breadcrumb jump to Sales.
      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Sales'));
      expect(tile('Invoices'), findsOneWidget);
      expect(tile('Daily'), findsNothing);

      // Back button to the top level.
      await tapAndSettle(tester, find.byTooltip('Back'));
      expect(tile('Orders'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);

      // Breadcrumb root from the deepest level.
      await tapAndSettle(tester, tile('Sales'));
      await tapAndSettle(tester, tile('Reports'));
      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Home'));
      expect(tile('Orders'), findsOneWidget);
    });

    testWidgets('falls back to the nearest visible level on access changes',
        (tester) async {
      final container = createAccessContainer(access: salesUser);
      await pumpInApp(
        tester,
        container,
        const SymphonyDashboard(items: sampleMenu),
      );
      await tapAndSettle(tester, tile('Sales'));
      await tapAndSettle(tester, tile('Reports'));
      expect(tile('Daily'), findsOneWidget);

      // Losing reports.read hides the Reports group: back to Sales.
      changeAccess(container, signedIn(roles: <String>{'sales'}));
      await tester.pumpAndSettle();
      expect(tile('Daily'), findsNothing);
      expect(tile('Reports'), findsNothing);
      expect(tile('Invoices'), findsOneWidget);

      // Losing the role hides Sales: back to the top level.
      changeAccess(container, AccessContext.unauthenticated);
      await tester.pumpAndSettle();
      expect(tile('Invoices'), findsNothing);
      expect(tile('Sales'), findsNothing);
      expect(tile('Orders'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
    });

    testWidgets('can be driven and observed through a controller',
        (tester) async {
      final controller = SymphonyDashboardController();
      addTearDown(controller.dispose);
      final container = createAccessContainer(access: salesUser);
      await pumpInApp(
        tester,
        container,
        SymphonyDashboard(items: sampleMenu, controller: controller),
      );

      await tapAndSettle(tester, tile('Sales'));
      expect(controller.path, <String>['sales']);
      expect(controller.canGoBack, isTrue);
      expect(controller.currentGroupId, 'sales');

      controller.open('sales.reports');
      await tester.pumpAndSettle();
      expect(tile('Daily'), findsOneWidget);
      expect(controller.depth, 2);

      expect(controller.goBack(), isTrue);
      await tester.pumpAndSettle();
      expect(tile('Invoices'), findsOneWidget);

      controller.goToRoot();
      await tester.pumpAndSettle();
      expect(tile('Orders'), findsOneWidget);
      expect(controller.goBack(), isFalse);

      // Ids that do not resolve to a visible group are dropped.
      controller.path = <String>['sales', 'sales.invoices'];
      await tester.pumpAndSettle();
      expect(controller.path, <String>['sales']);
      expect(tile('Invoices'), findsOneWidget);

      // Access changes keep the controller in sync with the display.
      changeAccess(container, AccessContext.unauthenticated);
      await tester.pumpAndSettle();
      expect(controller.path, isEmpty);
      expect(tile('Orders'), findsOneWidget);
    });

    testWidgets('starts at the controller initial path', (tester) async {
      final controller = SymphonyDashboardController(
        initialPath: <String>['sales', 'sales.reports'],
      );
      addTearDown(controller.dispose);
      await pumpInApp(
        tester,
        createAccessContainer(access: salesUser),
        SymphonyDashboard(items: sampleMenu, controller: controller),
      );

      expect(tile('Daily'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Sales'), findsOneWidget);
    });

    testWidgets('supports a replaced controller', (tester) async {
      final first = SymphonyDashboardController();
      final second =
          SymphonyDashboardController(initialPath: <String>['sales']);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final container = createAccessContainer(access: salesUser);

      await pumpInApp(
        tester,
        container,
        SymphonyDashboard(items: sampleMenu, controller: first),
      );
      expect(tile('Orders'), findsOneWidget);

      await pumpInApp(
        tester,
        container,
        SymphonyDashboard(items: sampleMenu, controller: second),
      );
      expect(tile('Invoices'), findsOneWidget);

      // The previous controller is no longer listened to.
      first.open('sales');
      await tester.pumpAndSettle();
      expect(tile('Invoices'), findsOneWidget);
      second.goToRoot();
      await tester.pumpAndSettle();
      expect(tile('Orders'), findsOneWidget);

      // Back to an internal controller.
      await pumpInApp(
        tester,
        container,
        const SymphonyDashboard(items: sampleMenu),
      );
      await tapAndSettle(tester, tile('Sales'));
      expect(tile('Invoices'), findsOneWidget);
      expect(second.path, isEmpty);
    });

    testWidgets('uses custom labels and can hide the breadcrumb',
        (tester) async {
      await pumpInApp(
        tester,
        createAccessContainer(access: salesUser),
        const SymphonyDashboard(
          items: sampleMenu,
          backLabel: 'Retour',
          rootLabel: 'Accueil',
        ),
      );
      await tapAndSettle(tester, tile('Sales'));
      expect(find.byTooltip('Retour'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Accueil'), findsOneWidget);

      await pumpInApp(
        tester,
        createAccessContainer(access: salesUser),
        const SymphonyDashboard(
          key: ValueKey<String>('no-breadcrumb'),
          items: sampleMenu,
          showBreadcrumbs: false,
        ),
      );
      await tapAndSettle(tester, tile('Sales'));
      expect(find.byType(TextButton), findsNothing);
      expect(find.text('Sales'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets('shows the title at the top level and keeps the header state',
        (tester) async {
      await pumpInApp(
        tester,
        createAccessContainer(access: salesUser),
        const SymphonyDashboard(
          items: sampleMenu,
          title: Text('Modules'),
          header: _CounterHeader(),
        ),
      );
      expect(find.text('Modules'), findsOneWidget);
      await tapAndSettle(tester, find.text('Header taps: 0'));
      expect(find.text('Header taps: 1'), findsOneWidget);

      await tapAndSettle(tester, tile('Sales'));
      expect(find.text('Modules'), findsNothing);
      expect(find.text('Header taps: 1'), findsOneWidget);

      await tapAndSettle(tester, find.byTooltip('Back'));
      expect(find.text('Modules'), findsOneWidget);
      expect(find.text('Header taps: 1'), findsOneWidget);
    });
  });

  group('tap handling', () {
    testWidgets('onTap replaces the submenu and the navigation',
        (tester) async {
      BuildContext? tappedContext;
      await pumpInApp(
        tester,
        createAccessContainer(),
        SymphonyDashboard(
          items: <DashboardItem>[
            DashboardItem(
              id: 'group',
              label: 'Group',
              route: '/group',
              onTap: (context) => tappedContext = context,
              children: const <DashboardItem>[
                DashboardItem(id: 'group.child', label: 'Child'),
              ],
            ),
          ],
        ),
      );

      await tapAndSettle(tester, tile('Group'));

      expect(tappedContext, isNotNull);
      expect(
        tappedContext!.findAncestorWidgetOfExactType<SymphonyDashboard>(),
        isNotNull,
      );
      expect(tile('Child'), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);
    });

    testWidgets('onItemSelected replaces the navigation of leaves',
        (tester) async {
      final selected = <String>[];
      await pumpInApp(
        tester,
        createAccessContainer(access: salesUser),
        SymphonyDashboard(
          items: sampleMenu,
          onItemSelected: (item) => selected.add(item.id),
        ),
      );

      await tapAndSettle(tester, tile('Orders'));
      expect(selected, <String>['orders']);

      // Groups still open their submenu.
      await tapAndSettle(tester, tile('Sales'));
      expect(selected, <String>['orders']);
      expect(tile('Invoices'), findsOneWidget);

      await tapAndSettle(tester, tile('Invoices'));
      expect(selected, <String>['orders', 'sales.invoices']);
    });
  });

  group('customization', () {
    testWidgets('tileBuilder replaces the tiles and keeps the tap handling',
        (tester) async {
      final callbacks = <String, bool>{};
      await pumpInApp(
        tester,
        createAccessContainer(access: salesUser),
        SymphonyDashboard(
          items: const <DashboardItem>[
            ...sampleMenu,
            DashboardItem(id: 'off', label: 'Off', enabled: false),
          ],
          tileBuilder: (context, item, onTap) {
            callbacks[item.id] = onTap != null;
            return Material(
              child: InkWell(
                onTap: onTap,
                child: Center(child: Text('Custom ${item.label}')),
              ),
            );
          },
        ),
      );

      expect(find.byType(SymphonyDashboardTile), findsNothing);
      expect(find.text('Custom Orders'), findsOneWidget);
      expect(callbacks['orders'], isTrue);
      expect(callbacks['off'], isFalse);

      await tapAndSettle(tester, find.text('Custom Sales'));
      expect(find.text('Custom Invoices'), findsOneWidget);
    });

    testWidgets('renders iconBuilder icons and badges', (tester) async {
      await pumpInApp(
        tester,
        createAccessContainer(),
        SymphonyDashboard(
          items: <DashboardItem>[
            DashboardItem(
              id: 'inbox',
              label: 'Inbox',
              badge: '5',
              iconBuilder: (context) => const SizedBox(
                key: Key('inbox-icon'),
                width: 24,
                height: 24,
              ),
            ),
            const DashboardItem(
              id: 'news',
              label: 'News',
              icon: Icons.newspaper,
              badge: '',
            ),
          ],
        ),
      );

      expect(find.byKey(const Key('inbox-icon')), findsOneWidget);
      expect(
        find.descendant(of: tile('Inbox'), matching: find.text('5')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile('News'), matching: find.byType(Badge)),
        findsOneWidget,
      );
    });

    testWidgets('shows the default empty state', (tester) async {
      await pumpInApp(
        tester,
        createAccessContainer(),
        const SymphonyDashboard(items: <DashboardItem>[]),
      );

      expect(find.byType(SymphonyEmptyState), findsOneWidget);
      expect(find.text('No modules available'), findsOneWidget);
    });

    testWidgets('shows the empty state when everything is filtered out',
        (tester) async {
      await pumpInApp(
        tester,
        createAccessContainer(),
        const SymphonyDashboard(
          items: <DashboardItem>[
            DashboardItem(
              id: 'admin',
              label: 'Admin',
              access: AccessRequirement(roles: <String>{'admin'}),
            ),
          ],
          emptyTitle: 'Nothing for you',
          emptyMessage: 'Ask an administrator for access.',
        ),
      );

      expect(tile('Admin'), findsNothing);
      expect(find.text('Nothing for you'), findsOneWidget);
      expect(find.text('Ask an administrator for access.'), findsOneWidget);
    });

    testWidgets('accepts a custom empty state widget', (tester) async {
      await pumpInApp(
        tester,
        createAccessContainer(),
        const SymphonyDashboard(
          items: <DashboardItem>[],
          emptyState: Text('Custom empty'),
        ),
      );

      expect(find.text('Custom empty'), findsOneWidget);
      expect(find.byType(SymphonyEmptyState), findsNothing);
    });

    testWidgets('crossAxisCount fixes the number of columns', (tester) async {
      const items = <DashboardItem>[
        DashboardItem(id: 'a', label: 'Alpha'),
        DashboardItem(id: 'b', label: 'Bravo'),
        DashboardItem(id: 'c', label: 'Charlie'),
        DashboardItem(id: 'd', label: 'Delta'),
      ];
      await pumpInApp(
        tester,
        createAccessContainer(),
        const SymphonyDashboard(items: items, crossAxisCount: 3),
      );

      final rects = <Rect>[
        for (final label in <String>['Alpha', 'Bravo', 'Charlie', 'Delta'])
          tester.getRect(tile(label)),
      ];
      expect(rects[1].top, rects[0].top);
      expect(rects[2].top, rects[0].top);
      expect(rects[3].top, greaterThan(rects[0].bottom));
      expect(rects[3].left, rects[0].left);
      // 800 px wide surface, 16 px padding and two 12 px gaps.
      expect(rects[0].width, moreOrLessEquals((800 - 32 - 24) / 3));
      expect(rects[0].height, moreOrLessEquals(rects[0].width));
    });

    testWidgets('adapts the columns to maxCrossAxisExtent', (tester) async {
      const items = <DashboardItem>[
        DashboardItem(id: 'a', label: 'Alpha'),
        DashboardItem(id: 'b', label: 'Bravo'),
        DashboardItem(id: 'c', label: 'Charlie'),
      ];
      await pumpInApp(
        tester,
        createAccessContainer(),
        const SymphonyDashboard(
          items: items,
          maxCrossAxisExtent: 400,
          childAspectRatio: 2,
          spacing: 8,
          padding: EdgeInsets.zero,
        ),
      );

      final a = tester.getRect(tile('Alpha'));
      final b = tester.getRect(tile('Bravo'));
      final c = tester.getRect(tile('Charlie'));
      expect(b.top, a.top);
      expect(c.top, greaterThan(a.top));
      expect(a.width, moreOrLessEquals((800 - 8) / 2));
      expect(a.height, moreOrLessEquals(a.width / 2));
    });

    testWidgets('can be embedded in another scroll view', (tester) async {
      await pumpInApp(
        tester,
        createAccessContainer(),
        ListView(
          children: const <Widget>[
            Text('Above'),
            SymphonyDashboard(
              items: sampleMenu,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              header: Text('Welcome'),
            ),
            Text('Below'),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Welcome'), findsOneWidget);
      expect(tile('Orders'), findsOneWidget);
      expect(find.text('Below'), findsOneWidget);
    });
  });
}
