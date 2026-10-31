import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/routing/routing.dart';

void main() {
  group('SymphonyRoutePaths defaults', () {
    test('use conventional app routes', () {
      const paths = SymphonyRoutePaths();
      expect(paths.splash, '/splash');
      expect(paths.login, '/login');
      expect(paths.home, '/');
      expect(paths.unauthorized, '/unauthorized');
      expect(paths.redirectParameter, 'from');
      expect(paths.guestOnlyPaths, isEmpty);
    });
  });

  group('normalizePath', () {
    test('guarantees a leading slash and strips trailing slashes', () {
      expect(SymphonyRoutePaths.normalizePath(''), '/');
      expect(SymphonyRoutePaths.normalizePath('/'), '/');
      expect(SymphonyRoutePaths.normalizePath('//'), '/');
      expect(SymphonyRoutePaths.normalizePath('/orders'), '/orders');
      expect(SymphonyRoutePaths.normalizePath('/orders/'), '/orders');
      expect(SymphonyRoutePaths.normalizePath('/orders//'), '/orders');
      expect(SymphonyRoutePaths.normalizePath('orders'), '/orders');
      expect(SymphonyRoutePaths.normalizePath('/a/b/'), '/a/b');
    });

    test('keeps the case', () {
      expect(SymphonyRoutePaths.normalizePath('/Orders'), '/Orders');
    });
  });

  group('matchesPath', () {
    test('matches the entry itself', () {
      expect(SymphonyRoutePaths.matchesPath('/login', '/login'), isTrue);
    });

    test('matches descendants', () {
      expect(SymphonyRoutePaths.matchesPath('/login/otp', '/login'), isTrue);
      expect(SymphonyRoutePaths.matchesPath('/a/b/c', '/a/b'), isTrue);
    });

    test('does not match siblings sharing a prefix', () {
      expect(SymphonyRoutePaths.matchesPath('/login-help', '/login'), isFalse);
      expect(SymphonyRoutePaths.matchesPath('/log', '/login'), isFalse);
    });

    test('ignores case and trailing slashes', () {
      expect(SymphonyRoutePaths.matchesPath('/LOGIN', '/login'), isTrue);
      expect(SymphonyRoutePaths.matchesPath('/login/', '/Login/'), isTrue);
    });

    test('root entry only matches the root path', () {
      expect(SymphonyRoutePaths.matchesPath('/', '/'), isTrue);
      expect(SymphonyRoutePaths.matchesPath('', '/'), isTrue);
      expect(SymphonyRoutePaths.matchesPath('/orders', '/'), isFalse);
    });
  });

  group('route predicates', () {
    const paths = SymphonyRoutePaths(
      splash: '/boot',
      login: '/auth/sign-in',
      guestOnlyPaths: <String>{'/auth/register', '/forgot-password'},
    );

    test('isSplash', () {
      expect(paths.isSplash('/boot'), isTrue);
      expect(paths.isSplash('/boot/'), isTrue);
      expect(paths.isSplash('/splash'), isFalse);
    });

    test('isLogin', () {
      expect(paths.isLogin('/auth/sign-in'), isTrue);
      expect(paths.isLogin('/auth/sign-in/otp'), isTrue);
      expect(paths.isLogin('/auth'), isFalse);
    });

    test('isGuestOnly includes the login route and the configured paths', () {
      expect(paths.isGuestOnly('/auth/sign-in'), isTrue);
      expect(paths.isGuestOnly('/auth/register'), isTrue);
      expect(paths.isGuestOnly('/auth/register/step-2'), isTrue);
      expect(paths.isGuestOnly('/forgot-password'), isTrue);
      expect(paths.isGuestOnly('/auth'), isFalse);
      expect(paths.isGuestOnly('/'), isFalse);
      expect(paths.isGuestOnly('/orders'), isFalse);
    });
  });

  group('locations with the redirect parameter', () {
    const paths = SymphonyRoutePaths();

    test('return the location unchanged without from', () {
      expect(paths.withRedirectParameter('/login', null), '/login');
      expect(paths.splashLocation(), '/splash');
      expect(paths.loginLocation(), '/login');
    });

    test('encode the remembered location', () {
      expect(
        paths.loginLocation(from: '/orders?page=2'),
        '/login?from=%2Forders%3Fpage%3D2',
      );
      expect(paths.splashLocation(from: '/'), '/splash?from=%2F');
    });

    test('round trip through Uri.queryParameters', () {
      const original = '/search?q=a+b%20c&tags=x,y#results';
      final location = paths.loginLocation(from: original);
      final decoded = Uri.parse(location).queryParameters['from'];
      expect(decoded, original);
    });

    test('keep the existing query parameters of the location', () {
      final location = paths.withRedirectParameter(
        '/auth?mode=sign-in',
        '/orders',
      );
      final uri = Uri.parse(location);
      expect(uri.path, '/auth');
      expect(uri.queryParameters, <String, String>{
        'mode': 'sign-in',
        'from': '/orders',
      });
    });

    test('use the configured parameter name', () {
      const custom = SymphonyRoutePaths(redirectParameter: 'next');
      expect(custom.loginLocation(from: '/orders'), '/login?next=%2Forders');
    });
  });

  group('value semantics', () {
    test('equality and hashCode', () {
      const a = SymphonyRoutePaths(guestOnlyPaths: <String>{'/a', '/b'});
      const b = SymphonyRoutePaths(guestOnlyPaths: <String>{'/b', '/a'});
      const c = SymphonyRoutePaths(home: '/dashboard');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith replaces the given fields only', () {
      const paths = SymphonyRoutePaths();
      final copy = paths.copyWith(
        home: '/dashboard',
        guestOnlyPaths: <String>{'/register'},
      );
      expect(copy.home, '/dashboard');
      expect(copy.guestOnlyPaths, <String>{'/register'});
      expect(copy.splash, paths.splash);
      expect(copy.login, paths.login);
      expect(copy.unauthorized, paths.unauthorized);
      expect(copy.redirectParameter, paths.redirectParameter);
      expect(paths.copyWith(), paths);
    });

    test('toString describes the paths', () {
      expect(const SymphonyRoutePaths().toString(), contains('login: /login'));
    });
  });
}
