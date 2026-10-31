import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';
import 'package:symphony_core/src/features/routing/routing.dart';

const AccessContext unknown = AccessContext.unknown;
const AccessContext signedOut = AccessContext.unauthenticated;
const AccessContext signedIn = AccessContext(status: AuthStatus.authenticated);
const AccessContext admin = AccessContext(
  status: AuthStatus.authenticated,
  roles: <String>{'admin'},
  permissions: <String>{'orders.read', 'orders.write'},
);

const SymphonyRedirectResolver resolver = SymphonyRedirectResolver(
  paths: SymphonyRoutePaths(
    guestOnlyPaths: <String>{'/register', '/forgot-password'},
  ),
  publicPaths: <String>{'/legal', '/reset-password'},
);

Uri u(String location) => Uri.parse(location);

/// The location remembered in the `from` parameter of [location].
String? fromOf(String? location) =>
    location == null ? null : Uri.parse(location).queryParameters['from'];

/// The path of [location].
String? pathOf(String? location) =>
    location == null ? null : Uri.parse(location).path;

void main() {
  group('locationOf', () {
    test('keeps path, query and fragment', () {
      expect(SymphonyRedirectResolver.locationOf(u('/orders')), '/orders');
      expect(
        SymphonyRedirectResolver.locationOf(u('/orders?page=2&sort=asc#top')),
        '/orders?page=2&sort=asc#top',
      );
    });

    test('drops scheme and authority of absolute deep links', () {
      expect(
        SymphonyRedirectResolver.locationOf(
          u('https://user@example.com:8443/orders?page=2'),
        ),
        '/orders?page=2',
      );
    });

    test('uses the root path for empty or relative paths', () {
      expect(
          SymphonyRedirectResolver.locationOf(u('https://example.com')), '/');
      expect(SymphonyRedirectResolver.locationOf(u('orders')), '/orders');
    });
  });

  group('sanitizeTarget', () {
    test('accepts in-app locations', () {
      for (final target in <String>[
        '/',
        '/orders',
        '/orders/42',
        '/orders?page=2&sort=desc',
        '/docs#section-2',
        '/my%20files',
        '/caf%C3%A9',
        '/@team',
        '/a:b',
        '/x?next=https://example.com',
      ]) {
        expect(resolver.sanitizeTarget(target), target, reason: target);
      }
    });

    test('rejects missing values', () {
      expect(resolver.sanitizeTarget(null), isNull);
      expect(resolver.sanitizeTarget(''), isNull);
    });

    test('rejects open-redirect attempts', () {
      for (final target in <String>[
        'orders',
        'https://evil.com',
        'http://evil.com/orders',
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        '//evil.com',
        '///evil.com',
        '//evil.com/orders',
        r'/\evil.com',
        r'\\evil.com',
        r'/orders\..\admin',
        '/%2F%2Fevil.com',
        '/%2f/evil.com',
        '/%5Cevil.com',
        '/\t/evil.com',
        '/\n/evil.com',
        '/ evil',
        '/orders\u0000',
        '/orders\u007f',
        '/%00admin',
        '/%FF',
        ' /orders',
      ]) {
        expect(resolver.sanitizeTarget(target), isNull, reason: target);
      }
    });

    test('rejects splash and login loops', () {
      for (final target in <String>[
        '/splash',
        '/splash?from=%2Forders',
        '/login',
        '/login/',
        '/LOGIN',
        '/login?from=%2Forders',
        '/login/otp',
      ]) {
        expect(resolver.sanitizeTarget(target), isNull, reason: target);
      }
    });

    test('accepts guest-only locations (they are valid for signed-out users)',
        () {
      expect(resolver.sanitizeTarget('/register'), '/register');
    });
  });

  group('redirectTargetOf', () {
    test('reads and sanitizes the redirect parameter', () {
      expect(resolver.redirectTargetOf(u('/login?from=%2Forders')), '/orders');
      expect(resolver.redirectTargetOf(u('/login')), isNull);
      expect(
        resolver.redirectTargetOf(u('/login?from=https%3A%2F%2Fevil.com')),
        isNull,
      );
      expect(
          resolver.redirectTargetOf(u('/login?from=%2F%2Fevil.com')), isNull);
    });

    test('returns null instead of throwing on malformed encoding', () {
      final location = u('/login?from=%FF%FE');
      expect(() => resolver.redirectTargetOf(location), returnsNormally);
      expect(resolver.redirectTargetOf(location), isNull);
    });

    test('uses the configured parameter name', () {
      const custom = SymphonyRedirectResolver(
        paths: SymphonyRoutePaths(redirectParameter: 'next'),
      );
      expect(custom.redirectTargetOf(u('/login?next=%2Forders')), '/orders');
      expect(custom.redirectTargetOf(u('/login?from=%2Forders')), isNull);
    });
  });

  group('isPublicPath', () {
    test('matches entries and their descendants, case-insensitively', () {
      expect(resolver.isPublicPath('/legal'), isTrue);
      expect(resolver.isPublicPath('/legal/terms'), isTrue);
      expect(resolver.isPublicPath('/LEGAL/'), isTrue);
      expect(resolver.isPublicPath('/legalese'), isFalse);
      expect(resolver.isPublicPath('/'), isFalse);
    });
  });

  group('resolveGlobal while the session is unknown', () {
    test('sends protected locations to the splash, remembering them', () {
      final target = resolver.resolveGlobal(unknown, u('/orders'));
      expect(target, '/splash?from=%2Forders');
    });

    test('remembers query and fragment', () {
      final target = resolver.resolveGlobal(
        unknown,
        u('/orders?page=2&sort=desc#row-4'),
      );
      expect(pathOf(target), '/splash');
      expect(fromOf(target), '/orders?page=2&sort=desc#row-4');
    });

    test('remembers home', () {
      expect(resolver.resolveGlobal(unknown, u('/')), '/splash?from=%2F');
    });

    test('remembers only the in-app part of absolute deep links', () {
      final target = resolver.resolveGlobal(
        unknown,
        u('https://example.com/orders?page=2'),
      );
      expect(fromOf(target), '/orders?page=2');
    });

    test('stays on the splash route', () {
      expect(resolver.resolveGlobal(unknown, u('/splash')), isNull);
      expect(resolver.resolveGlobal(unknown, u('/splash/')), isNull);
      expect(
        resolver.resolveGlobal(unknown, u('/splash?from=%2Forders')),
        isNull,
      );
    });

    test('lets public paths through', () {
      expect(resolver.resolveGlobal(unknown, u('/legal')), isNull);
      expect(resolver.resolveGlobal(unknown, u('/legal/terms')), isNull);
      expect(
        resolver.resolveGlobal(unknown, u('/reset-password?token=abc')),
        isNull,
      );
      expect(
        resolver.resolveGlobal(unknown, u('/legalese')),
        '/splash?from=%2Flegalese',
      );
    });

    test('never remembers the login route itself', () {
      expect(resolver.resolveGlobal(unknown, u('/login')), '/splash');
    });

    test('carries the location remembered by the login route', () {
      expect(
        resolver.resolveGlobal(unknown, u('/login?from=%2Forders')),
        '/splash?from=%2Forders',
      );
      expect(
        resolver.resolveGlobal(unknown, u('/login?from=%2F%2Fevil.com')),
        '/splash',
      );
    });

    test('remembers guest-only locations other than login', () {
      expect(
        resolver.resolveGlobal(unknown, u('/register')),
        '/splash?from=%2Fregister',
      );
    });

    test('uses the configured parameter name', () {
      const custom = SymphonyRedirectResolver(
        paths: SymphonyRoutePaths(splash: '/boot', redirectParameter: 'next'),
      );
      expect(
        custom.resolveGlobal(unknown, u('/orders')),
        '/boot?next=%2Forders',
      );
    });
  });

  group('resolveGlobal on the splash route once the status is known', () {
    test('signed-in users go to the remembered location', () {
      expect(
        resolver.resolveGlobal(
          signedIn,
          u('/splash?from=%2Forders%3Fpage%3D2'),
        ),
        '/orders?page=2',
      );
    });

    test('signed-in users go home without a usable location', () {
      expect(resolver.resolveGlobal(signedIn, u('/splash')), '/');
      expect(
        resolver.resolveGlobal(signedIn, u('/splash?from=%2F%2Fevil.com')),
        '/',
      );
      expect(
        resolver.resolveGlobal(signedIn, u('/splash?from=%2Flogin')),
        '/',
      );
      expect(
        resolver.resolveGlobal(signedIn, u('/splash?from=%2Fregister')),
        '/',
        reason: 'guest-only pages are pointless for signed-in users',
      );
    });

    test('signed-out users go to the remembered location for the guards', () {
      expect(
        resolver.resolveGlobal(signedOut, u('/splash?from=%2Forders')),
        '/orders',
      );
      expect(
        resolver.resolveGlobal(signedOut, u('/splash?from=%2Fregister')),
        '/register',
      );
    });

    test('signed-out users go to login without a usable location', () {
      expect(resolver.resolveGlobal(signedOut, u('/splash')), '/login');
      expect(
        resolver.resolveGlobal(
          signedOut,
          u('/splash?from=https%3A%2F%2Fevil.com'),
        ),
        '/login',
      );
    });
  });

  group('resolveGlobal on guest-only routes', () {
    test('sends signed-in users home', () {
      expect(resolver.resolveGlobal(signedIn, u('/login')), '/');
      expect(resolver.resolveGlobal(signedIn, u('/LOGIN')), '/');
      expect(resolver.resolveGlobal(signedIn, u('/register')), '/');
      expect(resolver.resolveGlobal(signedIn, u('/register/step-2')), '/');
    });

    test('sends signed-in users to the remembered location', () {
      expect(
        resolver.resolveGlobal(signedIn, u('/login?from=%2Forders%3Fpage%3D2')),
        '/orders?page=2',
      );
      expect(
        resolver.resolveGlobal(signedIn, u('/forgot-password?from=%2Forders')),
        '/orders',
      );
    });

    test('ignores unsafe or guest-only remembered locations', () {
      expect(
        resolver.resolveGlobal(
          signedIn,
          u('/login?from=https%3A%2F%2Fevil.com'),
        ),
        '/',
      );
      expect(
        resolver.resolveGlobal(signedIn, u('/login?from=%2F%5Cevil.com')),
        '/',
      );
      expect(
        resolver.resolveGlobal(signedIn, u('/login?from=%2Fregister')),
        '/',
      );
      expect(
        resolver.resolveGlobal(signedIn, u('/login?from=%2Flogin')),
        '/',
      );
    });

    test('lets signed-out users through', () {
      expect(resolver.resolveGlobal(signedOut, u('/login')), isNull);
      expect(
        resolver.resolveGlobal(signedOut, u('/login?from=%2Forders')),
        isNull,
      );
      expect(resolver.resolveGlobal(signedOut, u('/register')), isNull);
    });

    test('never redirects to the current page', () {
      const homeIsGuestOnly = SymphonyRedirectResolver(
        paths: SymphonyRoutePaths(
          home: '/welcome',
          guestOnlyPaths: <String>{'/welcome'},
        ),
      );
      expect(homeIsGuestOnly.resolveGlobal(signedIn, u('/welcome')), isNull);
    });
  });

  group('resolveGlobal elsewhere', () {
    test('does not redirect known users on regular routes', () {
      expect(resolver.resolveGlobal(signedIn, u('/orders')), isNull);
      expect(resolver.resolveGlobal(signedOut, u('/orders')), isNull);
      expect(resolver.resolveGlobal(signedOut, u('/')), isNull);
      expect(resolver.resolveGlobal(signedIn, u('/legal')), isNull);
    });
  });

  group('resolveGuard', () {
    test('grants access when the requirement is satisfied', () {
      expect(resolver.resolveGuard(signedIn, u('/orders')), isNull);
      expect(
        resolver.resolveGuard(
          signedOut,
          u('/catalog'),
          requirement: AccessRequirement.none,
        ),
        isNull,
      );
      expect(
        resolver.resolveGuard(
          unknown,
          u('/catalog'),
          requirement: const AccessRequirement.public(),
        ),
        isNull,
      );
      expect(
        resolver.resolveGuard(
          admin,
          u('/admin'),
          requirement: const AccessRequirement(roles: <String>{'admin'}),
        ),
        isNull,
      );
    });

    test('waits on the splash while the session is unknown', () {
      expect(
        resolver.resolveGuard(unknown, u('/orders')),
        '/splash?from=%2Forders',
      );
    });

    test('sends signed-out users to login, remembering the location', () {
      expect(
        resolver.resolveGuard(signedOut, u('/orders')),
        '/login?from=%2Forders',
      );
      final target = resolver.resolveGuard(
        signedOut,
        u('/orders/42?tab=items#notes'),
      );
      expect(pathOf(target), '/login');
      expect(fromOf(target), '/orders/42?tab=items#notes');
    });

    test('does not remember the bare home location', () {
      expect(resolver.resolveGuard(signedOut, u('/')), '/login');
      expect(
        resolver.resolveGuard(signedOut, u('/?tab=2')),
        '/login?from=%2F%3Ftab%3D2',
      );
    });

    test('never remembers the login route itself', () {
      expect(resolver.resolveGuard(signedOut, u('/login')), '/login');
    });

    test('sends signed-out users to login for role requirements too', () {
      expect(
        resolver.resolveGuard(
          signedOut,
          u('/beta'),
          requirement: const AccessRequirement(
            requiresAuth: false,
            roles: <String>{'beta'},
          ),
        ),
        '/login?from=%2Fbeta',
      );
    });

    test('sends signed-in users lacking a role to the unauthorized route', () {
      expect(
        resolver.resolveGuard(
          signedIn,
          u('/admin'),
          requirement: const AccessRequirement(roles: <String>{'admin'}),
        ),
        '/unauthorized',
      );
    });

    test('prefers the route deniedRedirect', () {
      expect(
        resolver.resolveGuard(
          signedIn,
          u('/admin'),
          requirement: const AccessRequirement(roles: <String>{'admin'}),
          deniedRedirect: '/upgrade?plan=pro',
        ),
        '/upgrade?plan=pro',
      );
    });

    test('falls back to home without an unauthorized route', () {
      const noUnauthorized = SymphonyRedirectResolver(
        paths: SymphonyRoutePaths(unauthorized: null, home: '/dashboard'),
      );
      expect(
        noUnauthorized.resolveGuard(
          signedIn,
          u('/admin'),
          requirement: const AccessRequirement(roles: <String>{'admin'}),
        ),
        '/dashboard',
      );
    });

    test('never redirects a denied user to the current page', () {
      const admins = AccessRequirement(roles: <String>{'admin'});
      expect(
        resolver.resolveGuard(
          signedIn,
          u('/reports?x=1'),
          requirement: admins,
          deniedRedirect: '/reports?denied=1',
        ),
        '/unauthorized',
      );
      expect(
        resolver.resolveGuard(signedIn, u('/unauthorized'),
            requirement: admins),
        '/',
      );
      const homeOnly = SymphonyRedirectResolver(
        paths: SymphonyRoutePaths(unauthorized: null),
      );
      expect(
        homeOnly.resolveGuard(signedIn, u('/'), requirement: admins),
        '/login',
        reason: 'no safe page left: go_router then reports a redirect loop',
      );
    });

    test('checks permissions with the configured match mode', () {
      const all = AccessRequirement(
        permissions: <String>{'orders.read', 'orders.delete'},
      );
      const any = AccessRequirement(
        permissions: <String>{'orders.read', 'orders.delete'},
        permissionMatch: MatchMode.any,
      );
      expect(
        resolver.resolveGuard(admin, u('/orders'), requirement: all),
        '/unauthorized',
      );
      expect(
          resolver.resolveGuard(admin, u('/orders'), requirement: any), isNull);
    });

    test('checks custom predicates', () {
      final beta = AccessRequirement(
        predicate: (AccessContext access) => access.attributes['beta'] == true,
      );
      expect(
        resolver.resolveGuard(signedIn, u('/beta'), requirement: beta),
        '/unauthorized',
      );
      expect(
        resolver.resolveGuard(
          signedIn.copyWith(attributes: <String, Object?>{'beta': true}),
          u('/beta'),
          requirement: beta,
        ),
        isNull,
      );
    });
  });

  group('resolveGuest', () {
    test('lets signed-out and unknown users through', () {
      expect(resolver.resolveGuest(signedOut, u('/login')), isNull);
      expect(resolver.resolveGuest(unknown, u('/register')), isNull);
    });

    test('sends signed-in users home', () {
      expect(resolver.resolveGuest(signedIn, u('/login')), '/');
      expect(resolver.resolveGuest(signedIn, u('/signup')), '/');
    });

    test('sends signed-in users to the remembered location', () {
      expect(
        resolver.resolveGuest(signedIn, u('/signup?from=%2Forders')),
        '/orders',
      );
      expect(
        resolver.resolveGuest(signedIn, u('/signup?from=%2Fregister')),
        '/',
      );
      expect(
        resolver.resolveGuest(signedIn, u('/signup?from=%2F%2Fevil.com')),
        '/',
      );
    });

    test('prefers the authenticatedRedirect of the route', () {
      expect(
        resolver.resolveGuest(
          signedIn,
          u('/signup?from=%2Forders'),
          authenticatedRedirect: '/welcome',
        ),
        '/welcome',
      );
    });

    test('never redirects to the current page', () {
      expect(
        resolver.resolveGuest(
          signedIn,
          u('/welcome'),
          authenticatedRedirect: '/welcome',
        ),
        isNull,
      );
    });
  });

  group('redirect parameter round trip', () {
    const locations = <String>[
      '/orders',
      '/orders?page=2&sort=desc',
      '/search?q=a+b%2Bc%20d',
      '/files/a%2Fb',
      '/caf%C3%A9?city=Montr%C3%A9al',
      '/docs#section-2',
      '/x?from=%2Fy&redirect=%2Fz',
    ];

    for (final location in locations) {
      test('login → back to $location', () {
        final login = resolver.resolveGuard(signedOut, u(location));
        expect(pathOf(login), '/login');
        expect(resolver.redirectTargetOf(u(login!)), location);
        expect(resolver.resolveGlobal(signedIn, u(login)), location);
      });

      test('splash → back to $location', () {
        final splash = resolver.resolveGlobal(unknown, u(location));
        expect(pathOf(splash), '/splash');
        expect(resolver.resolveGlobal(signedIn, u(splash!)), location);
        expect(resolver.resolveGlobal(signedOut, u(splash)), location);
      });
    }
  });

  group('value semantics', () {
    test('equality and hashCode', () {
      const a = SymphonyRedirectResolver(publicPaths: <String>{'/a', '/b'});
      const b = SymphonyRedirectResolver(publicPaths: <String>{'/b', '/a'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(resolver));
      expect(a.toString(), contains('publicPaths'));
    });
  });
}
