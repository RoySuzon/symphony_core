import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

void main() {
  const user = AccessContext(
    status: AuthStatus.authenticated,
    roles: <String>{'editor', 'viewer'},
    permissions: <String>{'orders.read', 'orders.write'},
    attributes: <String, Object?>{'tenant': 'acme'},
  );

  group('AccessContext', () {
    test('defaults to the unknown status without grants', () {
      const context = AccessContext();

      expect(context.status, AuthStatus.unknown);
      expect(context.isUnknown, isTrue);
      expect(context.isAuthenticated, isFalse);
      expect(context.roles, isEmpty);
      expect(context.permissions, isEmpty);
      expect(context.attributes, isEmpty);
      expect(AccessContext.unknown, context);
    });

    test('unauthenticated constant', () {
      expect(AccessContext.unauthenticated.status, AuthStatus.unauthenticated);
      expect(AccessContext.unauthenticated.isAuthenticated, isFalse);
      expect(AccessContext.unauthenticated.isUnknown, isFalse);
    });

    test('role helpers', () {
      expect(user.isAuthenticated, isTrue);
      expect(user.hasRole('editor'), isTrue);
      expect(user.hasRole('admin'), isFalse);
      expect(user.hasAnyRole(<String>['admin', 'viewer']), isTrue);
      expect(user.hasAnyRole(<String>['admin']), isFalse);
      expect(user.hasAnyRole(const <String>[]), isTrue);
      expect(user.hasAllRoles(<String>['editor', 'viewer']), isTrue);
      expect(user.hasAllRoles(<String>['editor', 'admin']), isFalse);
      expect(user.hasAllRoles(const <String>[]), isTrue);
    });

    test('permission helpers', () {
      expect(user.hasPermission('orders.read'), isTrue);
      expect(user.hasPermission('orders.delete'), isFalse);
      expect(
        user.hasAnyPermission(<String>['orders.delete', 'orders.read']),
        isTrue,
      );
      expect(user.hasAnyPermission(<String>['orders.delete']), isFalse);
      expect(user.hasAnyPermission(const <String>[]), isTrue);
      expect(
        user.hasAllPermissions(<String>['orders.read', 'orders.write']),
        isTrue,
      );
      expect(
        user.hasAllPermissions(<String>['orders.read', 'orders.delete']),
        isFalse,
      );
    });

    test('satisfies delegates to the requirement', () {
      expect(
          user.satisfies(const AccessRequirement(roles: {'editor'})), isTrue);
      expect(
          user.satisfies(const AccessRequirement(roles: {'admin'})), isFalse);
    });

    test('copyWith replaces the given fields', () {
      final copy = user.copyWith(
        status: AuthStatus.unauthenticated,
        roles: <String>{'admin'},
      );

      expect(copy.status, AuthStatus.unauthenticated);
      expect(copy.roles, <String>{'admin'});
      expect(copy.permissions, user.permissions);
      expect(copy.attributes, user.attributes);

      final same = user.copyWith();
      expect(same, user);

      final updated = user.copyWith(
        permissions: <String>{'x'},
        attributes: <String, Object?>{'tenant': 'other'},
      );
      expect(updated.permissions, <String>{'x'});
      expect(updated.attributes, <String, Object?>{'tenant': 'other'});
    });

    test('compares by value regardless of set ordering', () {
      // Sets in a different order are different constants: equality below
      // is by value, not by identity.
      const reordered = AccessContext(
        status: AuthStatus.authenticated,
        roles: <String>{'viewer', 'editor'},
        permissions: <String>{'orders.write', 'orders.read'},
        attributes: <String, Object?>{'tenant': 'acme'},
      );

      expect(identical(reordered, user), isFalse);
      expect(reordered, user);
      expect(reordered.hashCode, user.hashCode);
      expect(user, isNot(user.copyWith(roles: <String>{'editor'})));
      expect(
        user,
        isNot(user.copyWith(attributes: <String, Object?>{'tenant': 'x'})),
      );
    });

    test('toString lists status, roles and permissions', () {
      expect(
        user.toString(),
        allOf(
          contains('authenticated'),
          contains('editor'),
          contains('orders.read'),
        ),
      );
    });
  });
}
