import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

void main() {
  const unknown = AccessContext.unknown;
  const guest = AccessContext.unauthenticated;
  const member = AccessContext(status: AuthStatus.authenticated);
  const editor = AccessContext(
    status: AuthStatus.authenticated,
    roles: <String>{'editor'},
    permissions: <String>{'orders.read'},
  );
  const admin = AccessContext(
    status: AuthStatus.authenticated,
    roles: <String>{'admin', 'editor'},
    permissions: <String>{'orders.read', 'orders.write'},
    attributes: <String, Object?>{'tenant': 'acme'},
  );

  void expectMatrix(
    AccessRequirement requirement,
    Map<AccessContext, bool> expectations,
  ) {
    expectations.forEach((context, expected) {
      expect(
        requirement.isSatisfiedBy(context),
        expected,
        reason: '$requirement with $context',
      );
    });
  }

  group('AccessRequirement', () {
    test('public requirements allow everyone', () {
      for (final requirement in <AccessRequirement>[
        const AccessRequirement.public(),
        AccessRequirement.none,
      ]) {
        expect(requirement.isPublic, isTrue);
        expectMatrix(requirement, <AccessContext, bool>{
          unknown: true,
          guest: true,
          member: true,
          admin: true,
        });
      }
    });

    test('the default requirement needs a signed-in user', () {
      const requirement = AccessRequirement();

      expect(requirement.isPublic, isFalse);
      expect(requirement, AccessRequirement.authenticated);
      expectMatrix(requirement, <AccessContext, bool>{
        unknown: false,
        guest: false,
        member: true,
        editor: true,
      });
    });

    test('roles match any by default', () {
      const requirement = AccessRequirement(roles: <String>{'admin', 'editor'});

      expectMatrix(requirement, <AccessContext, bool>{
        guest: false,
        member: false,
        editor: true,
        admin: true,
        const AccessContext(
          status: AuthStatus.unauthenticated,
          roles: <String>{'admin'},
        ): false,
      });
    });

    test('roles can require all entries', () {
      const requirement = AccessRequirement(
        roles: <String>{'admin', 'editor'},
        roleMatch: MatchMode.all,
      );

      expectMatrix(requirement, <AccessContext, bool>{
        editor: false,
        admin: true,
      });
    });

    test('permissions match all by default', () {
      const requirement = AccessRequirement(
        permissions: <String>{'orders.read', 'orders.write'},
      );

      expectMatrix(requirement, <AccessContext, bool>{
        member: false,
        editor: false,
        admin: true,
      });
    });

    test('permissions can match any entry', () {
      const requirement = AccessRequirement(
        permissions: <String>{'orders.write', 'orders.read'},
        permissionMatch: MatchMode.any,
      );

      expectMatrix(requirement, <AccessContext, bool>{
        member: false,
        editor: true,
        admin: true,
      });
    });

    test('roles and permissions must both be satisfied', () {
      const requirement = AccessRequirement(
        roles: <String>{'editor'},
        permissions: <String>{'orders.write'},
      );

      expectMatrix(requirement, <AccessContext, bool>{
        editor: false,
        admin: true,
      });
    });

    test('grants can be checked without authentication', () {
      const requirement = AccessRequirement(
        requiresAuth: false,
        roles: <String>{'kiosk'},
      );

      expect(requirement.isPublic, isFalse);
      expectMatrix(requirement, <AccessContext, bool>{
        guest: false,
        const AccessContext(
          status: AuthStatus.unauthenticated,
          roles: <String>{'kiosk'},
        ): true,
      });
    });

    test('predicate runs after the declarative checks', () {
      var calls = 0;
      final requirement = AccessRequirement(
        roles: const <String>{'editor'},
        predicate: (context) {
          calls++;
          return context.attributes['tenant'] == 'acme';
        },
      );

      expect(requirement.isPublic, isFalse);
      expect(requirement.isSatisfiedBy(guest), isFalse);
      expect(requirement.isSatisfiedBy(member), isFalse);
      expect(calls, 0, reason: 'declarative checks failed first');
      expect(requirement.isSatisfiedBy(editor), isFalse);
      expect(requirement.isSatisfiedBy(admin), isTrue);
      expect(calls, 2);
    });

    test('a predicate alone makes a public requirement restrictive', () {
      final requirement = AccessRequirement(
        requiresAuth: false,
        predicate: (context) => context.isUnknown,
      );

      expect(requirement.isPublic, isFalse);
      expectMatrix(requirement, <AccessContext, bool>{
        unknown: true,
        guest: false,
      });
    });

    test('copyWith replaces the given fields', () {
      bool predicate(AccessContext context) => true;
      const original = AccessRequirement(roles: <String>{'a'});

      final copy = original.copyWith(
        requiresAuth: false,
        roles: <String>{'b'},
        permissions: <String>{'p'},
        roleMatch: MatchMode.all,
        permissionMatch: MatchMode.any,
        predicate: predicate,
      );

      expect(copy.requiresAuth, isFalse);
      expect(copy.roles, <String>{'b'});
      expect(copy.permissions, <String>{'p'});
      expect(copy.roleMatch, MatchMode.all);
      expect(copy.permissionMatch, MatchMode.any);
      expect(copy.predicate, same(predicate));
      expect(original.copyWith(), original);
    });

    test('compares by value', () {
      // Sets in a different order are different constants: equality below
      // is by value, not by identity.
      const reordered = AccessRequirement(roles: <String>{'b', 'a'});

      expect(
        identical(
            const AccessRequirement(roles: <String>{'a', 'b'}), reordered),
        isFalse,
      );
      expect(const AccessRequirement(roles: <String>{'a', 'b'}), reordered);
      expect(
        const AccessRequirement(roles: <String>{'a', 'b'}).hashCode,
        reordered.hashCode,
      );
      expect(
        const AccessRequirement(roles: <String>{'a'}),
        isNot(
            const AccessRequirement(roles: <String>{'a'}, requiresAuth: false)),
      );
      expect(
        const AccessRequirement(roles: <String>{'a'}).toString(),
        allOf(contains('a'), contains('any')),
      );
    });
  });
}
