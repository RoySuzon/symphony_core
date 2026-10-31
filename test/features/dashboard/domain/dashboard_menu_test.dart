import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/access/access_context.dart';
import 'package:symphony_core/src/core/access/access_requirement.dart';
import 'package:symphony_core/src/features/dashboard/dashboard.dart';

import '../dashboard_test_utils.dart';

List<String> ids(Iterable<DashboardItem> items) =>
    <String>[for (final item in items) item.id];

void main() {
  group('DashboardMenu.filterVisibleItems', () {
    test('keeps public items for everybody', () {
      final visible = DashboardMenu.filterVisibleItems(
        sampleMenu,
        AccessContext.unauthenticated,
      );

      expect(ids(visible), <String>['orders', 'help']);
    });

    test('requires authentication by default for restricted items', () {
      const items = <DashboardItem>[
        DashboardItem(
          id: 'profile',
          label: 'Profile',
          access: AccessRequirement.authenticated,
        ),
      ];

      expect(
        DashboardMenu.filterVisibleItems(items, AccessContext.unknown),
        isEmpty,
      );
      expect(
        DashboardMenu.filterVisibleItems(items, AccessContext.unauthenticated),
        isEmpty,
      );
      expect(ids(DashboardMenu.filterVisibleItems(items, signedIn())), <String>[
        'profile',
      ]);
    });

    test('matches roles with any (default) and all modes', () {
      const items = <DashboardItem>[
        DashboardItem(
          id: 'any',
          label: 'Any',
          access: AccessRequirement(roles: <String>{'a', 'b'}),
        ),
        DashboardItem(
          id: 'all',
          label: 'All',
          access: AccessRequirement(
            roles: <String>{'a', 'b'},
            roleMatch: MatchMode.all,
          ),
        ),
      ];

      expect(
        ids(
          DashboardMenu.filterVisibleItems(
            items,
            signedIn(roles: <String>{'b'}),
          ),
        ),
        <String>['any'],
      );
      expect(
        ids(
          DashboardMenu.filterVisibleItems(
            items,
            signedIn(roles: <String>{'a', 'b'}),
          ),
        ),
        <String>['any', 'all'],
      );
      expect(
        DashboardMenu.filterVisibleItems(
          items,
          signedIn(roles: <String>{'c'}),
        ),
        isEmpty,
      );
    });

    test('matches permissions with all (default) and any modes', () {
      const items = <DashboardItem>[
        DashboardItem(
          id: 'all',
          label: 'All',
          access: AccessRequirement(permissions: <String>{'r', 'w'}),
        ),
        DashboardItem(
          id: 'any',
          label: 'Any',
          access: AccessRequirement(
            permissions: <String>{'r', 'w'},
            permissionMatch: MatchMode.any,
          ),
        ),
      ];

      expect(
        ids(
          DashboardMenu.filterVisibleItems(
            items,
            signedIn(permissions: <String>{'r'}),
          ),
        ),
        <String>['any'],
      );
      expect(
        ids(
          DashboardMenu.filterVisibleItems(
            items,
            signedIn(permissions: <String>{'r', 'w'}),
          ),
        ),
        <String>['all', 'any'],
      );
    });

    test('evaluates custom predicates', () {
      final items = <DashboardItem>[
        DashboardItem(
          id: 'beta',
          label: 'Beta',
          access: AccessRequirement(
            requiresAuth: false,
            predicate: (context) => context.attributes['beta'] == true,
          ),
        ),
      ];

      expect(
        DashboardMenu.filterVisibleItems(items, AccessContext.unauthenticated),
        isEmpty,
      );
      expect(
        ids(
          DashboardMenu.filterVisibleItems(
            items,
            const AccessContext(attributes: <String, Object?>{'beta': true}),
          ),
        ),
        <String>['beta'],
      );
    });

    test('prunes nested groups recursively', () {
      final sales = DashboardMenu.filterVisibleItems(
        sampleMenu,
        signedIn(roles: <String>{'sales'}),
      );
      expect(ids(sales), <String>['orders', 'sales', 'help']);
      // Reports requires a permission: Sales only keeps Invoices.
      expect(ids(sales[1].children), <String>['sales.invoices']);

      final reports = DashboardMenu.filterVisibleItems(sampleMenu, salesUser);
      final reportsGroup = reports[1].children[1];
      expect(reportsGroup.id, 'sales.reports');
      expect(ids(reportsGroup.children), <String>['sales.reports.daily']);

      final admin = DashboardMenu.filterVisibleItems(
        sampleMenu,
        signedIn(
          roles: <String>{'admin'},
          permissions: <String>{'reports.read', 'reports.monthly'},
        ),
      );
      expect(ids(admin), <String>['orders', 'sales', 'admin', 'help']);
      expect(
        ids(admin[1].children[1].children),
        <String>['sales.reports.daily', 'sales.reports.monthly'],
      );
    });

    test('hides a restricted group with all of its children', () {
      const items = <DashboardItem>[
        DashboardItem(
          id: 'admin',
          label: 'Admin',
          access: AccessRequirement(roles: <String>{'admin'}),
          children: <DashboardItem>[
            DashboardItem(id: 'admin.public', label: 'Public child'),
          ],
        ),
      ];

      expect(
        DashboardMenu.filterVisibleItems(
          items,
          signedIn(roles: <String>{'user'}),
        ),
        isEmpty,
      );
    });

    test('hides emptied groups unless they have their own action', () {
      const hidden = AccessRequirement(roles: <String>{'nobody'});
      final items = <DashboardItem>[
        const DashboardItem(
          id: 'empty',
          label: 'Empty',
          children: <DashboardItem>[
            DashboardItem(id: 'empty.a', label: 'A', access: hidden),
          ],
        ),
        const DashboardItem(
          id: 'routed',
          label: 'Routed',
          route: '/routed',
          children: <DashboardItem>[
            DashboardItem(id: 'routed.a', label: 'A', access: hidden),
          ],
        ),
        DashboardItem(
          id: 'custom',
          label: 'Custom',
          onTap: (_) {},
          children: const <DashboardItem>[
            DashboardItem(id: 'custom.a', label: 'A', access: hidden),
          ],
        ),
        const DashboardItem(id: 'placeholder', label: 'Placeholder'),
      ];

      final visible = DashboardMenu.filterVisibleItems(items, signedIn());

      expect(ids(visible), <String>['routed', 'custom', 'placeholder']);
      // Kept groups become leaves.
      expect(visible[0].isLeaf, isTrue);
      expect(visible[1].isLeaf, isTrue);
    });

    test('keeps disabled items visible', () {
      const items = <DashboardItem>[
        DashboardItem(
          id: 'soon',
          label: 'Coming soon',
          enabled: false,
          route: '/soon',
        ),
        DashboardItem(
          id: 'group',
          label: 'Group',
          children: <DashboardItem>[
            DashboardItem(id: 'group.off', label: 'Off', enabled: false),
          ],
        ),
      ];

      final visible = DashboardMenu.filterVisibleItems(
        items,
        AccessContext.unauthenticated,
      );

      expect(ids(visible), <String>['soon', 'group']);
      expect(visible.first.enabled, isFalse);
      expect(visible.last.children.single.enabled, isFalse);
    });

    test('returns unchanged items as is and copies changed groups', () {
      final visible = DashboardMenu.filterVisibleItems(
        sampleMenu,
        signedIn(roles: <String>{'sales'}),
      );

      expect(identical(visible.first, sampleMenu.first), isTrue);
      expect(identical(visible[1], sampleMenu[1]), isFalse);
      expect(sampleMenu[1].children, hasLength(2));
      expect(() => visible.add(sampleMenu.first), throwsUnsupportedError);
    });
  });

  group('DashboardMenu lookups', () {
    test('findItemById searches the whole tree', () {
      expect(
        DashboardMenu.findItemById(sampleMenu, 'sales.reports.monthly')?.label,
        'Monthly',
      );
      expect(DashboardMenu.findItemById(sampleMenu, 'help')?.label, 'Help');
      expect(DashboardMenu.findItemById(sampleMenu, 'missing'), isNull);
    });

    test('pathTo returns the breadcrumb down to the item', () {
      expect(
        ids(DashboardMenu.pathTo(sampleMenu, 'sales.reports.daily')),
        <String>['sales', 'sales.reports', 'sales.reports.daily'],
      );
      expect(ids(DashboardMenu.pathTo(sampleMenu, 'orders')), <String>[
        'orders',
      ]);
      expect(DashboardMenu.pathTo(sampleMenu, 'missing'), isEmpty);
    });

    test('flatten lists every item in depth-first pre-order', () {
      expect(ids(DashboardMenu.flatten(sampleMenu)), <String>[
        'orders',
        'sales',
        'sales.invoices',
        'sales.reports',
        'sales.reports.daily',
        'sales.reports.monthly',
        'admin',
        'help',
      ]);
      expect(DashboardMenu.flatten(const <DashboardItem>[]), isEmpty);
    });

    test('resolveSubmenuPath returns the longest valid prefix', () {
      expect(
        ids(
          DashboardMenu.resolveSubmenuPath(
            sampleMenu,
            <String>['sales', 'sales.reports'],
          ),
        ),
        <String>['sales', 'sales.reports'],
      );
      // A leaf cannot be opened as a submenu.
      expect(
        ids(
          DashboardMenu.resolveSubmenuPath(
            sampleMenu,
            <String>['sales', 'sales.invoices'],
          ),
        ),
        <String>['sales'],
      );
      // Ids must follow the hierarchy.
      expect(
        DashboardMenu.resolveSubmenuPath(sampleMenu, <String>['sales.reports']),
        isEmpty,
      );
      expect(
        DashboardMenu.resolveSubmenuPath(sampleMenu, const <String>[]),
        isEmpty,
      );

      // Hidden groups are not resolved in the filtered tree.
      final visible = DashboardMenu.filterVisibleItems(
        sampleMenu,
        signedIn(roles: <String>{'sales'}),
      );
      expect(
        ids(
          DashboardMenu.resolveSubmenuPath(
            visible,
            <String>['sales', 'sales.reports'],
          ),
        ),
        <String>['sales'],
      );
    });

    test('resolveSubmenuPath stops at disabled groups', () {
      const items = <DashboardItem>[
        DashboardItem(
          id: 'g',
          label: 'G',
          enabled: false,
          children: <DashboardItem>[DashboardItem(id: 'g.a', label: 'A')],
        ),
      ];

      expect(
        DashboardMenu.resolveSubmenuPath(items, <String>['g']),
        isEmpty,
      );
    });
  });

  group('DashboardMenu id validation', () {
    const duplicated = <DashboardItem>[
      DashboardItem(id: 'a', label: 'A'),
      DashboardItem(
        id: 'g',
        label: 'G',
        children: <DashboardItem>[
          DashboardItem(id: 'a', label: 'Nested A'),
          DashboardItem(id: 'b', label: 'B'),
        ],
      ),
      DashboardItem(id: 'b', label: 'B again'),
    ];

    test('duplicateIds reports ids used more than once', () {
      expect(DashboardMenu.duplicateIds(sampleMenu), isEmpty);
      expect(DashboardMenu.duplicateIds(duplicated), <String>{'a', 'b'});
    });

    test('debugAssertUniqueIds throws a descriptive error in debug', () {
      expect(DashboardMenu.debugAssertUniqueIds(sampleMenu), isTrue);
      expect(
        () => DashboardMenu.debugAssertUniqueIds(duplicated),
        throwsA(
          isA<FlutterError>().having(
            (error) => error.message,
            'message',
            contains('Duplicate DashboardItem ids: a, b.'),
          ),
        ),
      );
    });
  });

  group('DashboardMenu.resolveTapAction', () {
    test('applies the documented precedence', () {
      final custom = DashboardItem(
        id: 'c',
        label: 'C',
        route: '/c',
        onTap: (_) {},
        children: const <DashboardItem>[DashboardItem(id: 'x', label: 'X')],
      );
      const group = DashboardItem(
        id: 'g',
        label: 'G',
        route: '/g',
        children: <DashboardItem>[DashboardItem(id: 'y', label: 'Y')],
      );
      const leaf = DashboardItem(id: 'l', label: 'L', route: '/l');
      const placeholder = DashboardItem(id: 'p', label: 'P');
      final disabled = custom.copyWith(enabled: false);

      expect(
        DashboardMenu.resolveTapAction(disabled, hasSelectionHandler: true),
        DashboardTapAction.none,
      );
      expect(
        DashboardMenu.resolveTapAction(custom, hasSelectionHandler: true),
        DashboardTapAction.custom,
      );
      expect(
        DashboardMenu.resolveTapAction(group, hasSelectionHandler: true),
        DashboardTapAction.openSubmenu,
      );
      expect(
        DashboardMenu.resolveTapAction(leaf, hasSelectionHandler: true),
        DashboardTapAction.select,
      );
      expect(
        DashboardMenu.resolveTapAction(placeholder, hasSelectionHandler: true),
        DashboardTapAction.select,
      );
      expect(DashboardMenu.resolveTapAction(leaf), DashboardTapAction.navigate);
      expect(
        DashboardMenu.resolveTapAction(placeholder),
        DashboardTapAction.none,
      );
    });
  });
}
