import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/access/access_requirement.dart';
import 'package:symphony_core/src/features/dashboard/dashboard.dart';

void main() {
  group('DashboardItem', () {
    test('has opt-in visibility and sensible defaults', () {
      const item = DashboardItem(id: 'orders', label: 'Orders');

      expect(item.access, AccessRequirement.none);
      expect(item.access.isPublic, isTrue);
      expect(item.navigation, DashboardNavigation.go);
      expect(item.enabled, isTrue);
      expect(item.children, isEmpty);
      expect(item.pathParameters, isEmpty);
      expect(item.queryParameters, isEmpty);
      expect(item.metadata, isEmpty);
      expect(item.badge, isNull);
    });

    test('is equal to another item with the same id', () {
      const a = DashboardItem(id: 'orders', label: 'Orders', route: '/a');
      const b = DashboardItem(id: 'orders', label: 'Other', route: '/b');
      const c = DashboardItem(id: 'invoices', label: 'Orders', route: '/a');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(<DashboardItem>{a, b, c}, hasLength(2));
    });

    test('derives group, leaf, destination and action getters', () {
      const leaf = DashboardItem(id: 'leaf', label: 'Leaf');
      const routed = DashboardItem(id: 'r', label: 'R', route: '/r');
      const named = DashboardItem(id: 'n', label: 'N', routeName: 'n');
      const emptyRoute = DashboardItem(id: 'e', label: 'E', route: '');
      final custom = DashboardItem(id: 'c', label: 'C', onTap: (_) {});
      const group = DashboardItem(
        id: 'g',
        label: 'G',
        children: <DashboardItem>[leaf],
      );

      expect(leaf.isLeaf, isTrue);
      expect(leaf.hasChildren, isFalse);
      expect(leaf.hasDestination, isFalse);
      expect(leaf.hasAction, isFalse);
      expect(routed.hasDestination, isTrue);
      expect(named.hasDestination, isTrue);
      expect(emptyRoute.hasDestination, isFalse);
      expect(custom.hasDestination, isFalse);
      expect(custom.hasAction, isTrue);
      expect(group.hasChildren, isTrue);
      expect(group.isLeaf, isFalse);
      expect(group.hasAction, isFalse);
    });

    test('copyWith replaces only the given fields', () {
      const original = DashboardItem(
        id: 'orders',
        label: 'Orders',
        icon: Icons.receipt_long,
        route: '/orders',
        badge: '1',
      );

      final copy = original.copyWith(
        label: 'All orders',
        badge: '2',
        enabled: false,
        navigation: DashboardNavigation.push,
        children: const <DashboardItem>[
          DashboardItem(id: 'orders.open', label: 'Open'),
        ],
      );

      expect(copy.id, 'orders');
      expect(copy.label, 'All orders');
      expect(copy.icon, Icons.receipt_long);
      expect(copy.route, '/orders');
      expect(copy.badge, '2');
      expect(copy.enabled, isFalse);
      expect(copy.navigation, DashboardNavigation.push);
      expect(copy.children.single.id, 'orders.open');
      expect(original.label, 'Orders');
      expect(original.children, isEmpty);
    });

    test('normalizes query parameters for URIs', () {
      const item = DashboardItem(
        id: 'q',
        label: 'Q',
        queryParameters: <String, dynamic>{
          'text': 'a',
          'page': 2,
          'tags': <Object?>['x', 3, null],
          'missing': null,
        },
      );

      expect(item.routeQueryParameters, <String, dynamic>{
        'text': 'a',
        'page': '2',
        'tags': <String>['x', '3'],
      });
      expect(
        const DashboardItem(id: 'e', label: 'E').routeQueryParameters,
        isEmpty,
      );
    });

    test('routeLocation merges query parameters into the route', () {
      expect(
        const DashboardItem(
          id: 'a',
          label: 'A',
          route: '/orders',
        ).routeLocation,
        '/orders',
      );
      expect(
        const DashboardItem(
          id: 'b',
          label: 'B',
          route: '/orders?status=open',
          queryParameters: <String, dynamic>{'page': 1},
        ).routeLocation,
        '/orders?status=open&page=1',
      );
      expect(
        const DashboardItem(
          id: 'c',
          label: 'C',
          route: '/orders?page=1',
          queryParameters: <String, dynamic>{'page': '5'},
        ).routeLocation,
        '/orders?page=5',
      );
      expect(
        const DashboardItem(id: 'd', label: 'D', routeName: 'd').routeLocation,
        isNull,
      );
    });

    test('toString describes the item', () {
      const item = DashboardItem(
        id: 'sales',
        label: 'Sales',
        enabled: false,
        children: <DashboardItem>[DashboardItem(id: 'x', label: 'X')],
      );

      expect(
        item.toString(),
        'DashboardItem(sales, label: Sales, children: 1, disabled)',
      );
      expect(
        const DashboardItem(
          id: 'o',
          label: 'O',
          routeName: 'orders',
        ).toString(),
        'DashboardItem(o, label: O, destination: orders)',
      );
    });
  });
}
