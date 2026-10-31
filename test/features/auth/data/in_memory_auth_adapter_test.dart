import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/auth/auth.dart';

import '../support/auth_test_support.dart';

void main() {
  late DateTime now;
  late InMemoryAuthAdapter adapter;

  InMemoryAuthAdapter createAdapter({
    bool refreshEnabled = true,
    bool registrationEnabled = true,
    bool passwordRecoveryEnabled = true,
    bool signInAfterRegistration = true,
    Duration latency = Duration.zero,
    void Function(String identifier, String code)? onResetCodeIssued,
    Failure? Function(InMemoryAuthOperation operation)? failureInjector,
    Future<void> Function(AuthSession session)? sessionValidator,
  }) {
    return InMemoryAuthAdapter(
      accounts: demoAccounts,
      refreshEnabled: refreshEnabled,
      registrationEnabled: registrationEnabled,
      passwordRecoveryEnabled: passwordRecoveryEnabled,
      signInAfterRegistration: signInAfterRegistration,
      latency: latency,
      onResetCodeIssued: onResetCodeIssued,
      failureInjector: failureInjector,
      sessionValidator: sessionValidator,
      clock: () => now,
      random: Random(7),
    );
  }

  AuthCredentials credentials(String email, String password) =>
      AuthCredentials.emailPassword(email: email, password: password);

  setUp(() {
    now = testNow;
    adapter = createAdapter();
  });

  group('login', () {
    test('returns the account user and expiring tokens', () async {
      final session =
          await adapter.login(credentials('admin@example.com', 'secret123'));

      expect(session.user, adminUser);
      expect(session.tokens.accessToken, isNotEmpty);
      expect(session.tokens.canRefresh, isTrue);
      expect(session.tokens.tokenType, 'Bearer');
      expect(session.tokens.expiresAt, testNow.add(const Duration(hours: 1)));
    });

    test('matches identifiers case-insensitively', () async {
      final session =
          await adapter.login(credentials(' ADMIN@example.com ', 'secret123'));

      expect(session.user, adminUser);
    });

    test('rejects wrong credentials with an AuthFailure', () async {
      await expectLater(
        adapter.login(credentials('admin@example.com', 'wrong')),
        throwsA(isA<AuthFailure>()),
      );
      await expectLater(
        adapter.login(credentials('nobody@example.com', 'secret123')),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('reports missing fields as field errors', () async {
      await expectLater(
        adapter.login(credentials('', '')),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.fieldErrors.keys.toSet(),
            'fields',
            <String>{'email', 'password'},
          ),
        ),
      );
    });
  });

  group('tokens', () {
    late AuthSession session;

    setUp(() async {
      session =
          await adapter.login(credentials('admin@example.com', 'secret123'));
    });

    test('fetchCurrentUser accepts a valid access token', () async {
      expect(await adapter.fetchCurrentUser(session), adminUser);
    });

    test('expired access tokens are rejected', () async {
      now = now.add(const Duration(hours: 2));

      await expectLater(
        adapter.fetchCurrentUser(session),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('refresh rotates the refresh token', () async {
      final renewed = await adapter.refresh(session.tokens);

      expect(renewed.accessToken, isNot(session.tokens.accessToken));
      expect(renewed.refreshToken, isNot(session.tokens.refreshToken));
      await expectLater(
        adapter.refresh(session.tokens),
        throwsA(isA<UnauthorizedFailure>()),
      );
      expect(
        await adapter.fetchCurrentUser(AuthSession(tokens: renewed)),
        adminUser,
      );
    });

    test('logout revokes the session tokens', () async {
      await adapter.logout(session);

      await expectLater(
        adapter.fetchCurrentUser(session),
        throwsA(isA<UnauthorizedFailure>()),
      );
      await expectLater(
        adapter.refresh(session.tokens),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('revokeAllSessions invalidates every issued token', () async {
      adapter.revokeAllSessions();

      await expectLater(
        adapter.fetchCurrentUser(session),
        throwsA(isA<UnauthorizedFailure>()),
      );
      final fresh =
          await adapter.login(credentials('admin@example.com', 'secret123'));
      expect(await adapter.fetchCurrentUser(fresh), adminUser);
    });

    test('tokens survive a new adapter instance (app restart)', () async {
      final restarted = createAdapter();

      expect(await restarted.fetchCurrentUser(session), adminUser);
    });

    test('foreign tokens are rejected', () async {
      await expectLater(
        adapter.fetchCurrentUser(
          const AuthSession(tokens: AuthTokens(accessToken: 'abc.def.ghi')),
        ),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('refresh can be disabled', () async {
      final noRefresh = createAdapter(refreshEnabled: false);
      final session =
          await noRefresh.login(credentials('admin@example.com', 'secret123'));

      expect(session.tokens.canRefresh, isFalse);
      await expectLater(
        noRefresh.refresh(session.tokens),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });
  });

  group('registration', () {
    const data = AuthCredentials(<String, Object?>{
      'email': 'new@example.com',
      'password': 'brandNew1',
      'name': 'Newton',
    });

    test('creates an account and signs the user in', () async {
      final session = await adapter.register(data);

      expect(session?.user?.displayName, 'Newton');
      expect(session?.user?.email, 'new@example.com');
      expect(session?.user?.roles, <String>{'user'});
      final login =
          await adapter.login(credentials('new@example.com', 'brandNew1'));
      expect(login.user?.id, session?.user?.id);
      expect(adapter.accounts, hasLength(3));
    });

    test('rejects existing identifiers with a field error', () async {
      await expectLater(
        adapter.register(
          credentials('admin@example.com', 'whatever1'),
        ),
        throwsA(
          isA<ValidationFailure>()
              .having((f) => f.errorFor('email'), 'email', isNotNull),
        ),
      );
    });

    test('can require a separate sign-in', () async {
      final noAutoLogin = createAdapter(signInAfterRegistration: false);

      expect(await noAutoLogin.register(data), isNull);
    });

    test('can be disabled', () async {
      final disabled = createAdapter(registrationEnabled: false);

      expect(disabled.supportsRegistration, isFalse);
      await expectLater(
        disabled.register(data),
        throwsA(isA<UnsupportedFailure>()),
      );
    });
  });

  group('password recovery', () {
    test('issues a code and resets the password with it', () async {
      String? delivered;
      final recovering = createAdapter(
        onResetCodeIssued: (identifier, code) => delivered = code,
      );

      await recovering.requestPasswordReset(
        const AuthCredentials(<String, Object?>{'email': 'admin@example.com'}),
      );

      expect(delivered, hasLength(6));
      expect(recovering.lastResetCode, delivered);
      expect(recovering.resetCodeFor('ADMIN@example.com'), delivered);

      await recovering.confirmPasswordReset(
        AuthCredentials(<String, Object?>{
          'email': 'admin@example.com',
          'code': delivered,
          'password': 'changed99',
        }),
      );

      expect(recovering.resetCodeFor('admin@example.com'), isNull);
      final session = await recovering
          .login(credentials('admin@example.com', 'changed99'));
      expect(session.user, adminUser);
      await expectLater(
        recovering.login(credentials('admin@example.com', 'secret123')),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('rejects a wrong code with a field error', () async {
      await adapter.requestPasswordReset(
        const AuthCredentials(<String, Object?>{'email': 'admin@example.com'}),
      );

      await expectLater(
        adapter.confirmPasswordReset(
          const AuthCredentials(<String, Object?>{
            'email': 'admin@example.com',
            'code': 'nope',
            'password': 'changed99',
          }),
        ),
        throwsA(
          isA<ValidationFailure>()
              .having((f) => f.errorFor('code'), 'code', isNotNull),
        ),
      );
    });

    test('silently accepts unknown identifiers', () async {
      await adapter.requestPasswordReset(
        const AuthCredentials(<String, Object?>{'email': 'ghost@example.com'}),
      );

      expect(adapter.lastResetCode, isNull);
    });

    test('can be disabled', () async {
      final disabled = createAdapter(passwordRecoveryEnabled: false);

      expect(disabled.supportsPasswordRecovery, isFalse);
      await expectLater(
        disabled.requestPasswordReset(
          const AuthCredentials(<String, Object?>{'email': 'a@b.co'}),
        ),
        throwsA(isA<UnsupportedFailure>()),
      );
    });
  });

  test('injects failures per operation', () async {
    final offline = createAdapter(
      failureInjector: (operation) => operation == InMemoryAuthOperation.login
          ? const NetworkFailure()
          : null,
    );

    await expectLater(
      offline.login(credentials('admin@example.com', 'secret123')),
      throwsA(isA<NetworkFailure>()),
    );
    await expectLater(
      offline.requestPasswordReset(
        const AuthCredentials(<String, Object?>{'email': 'admin@example.com'}),
      ),
      completes,
    );
  });

  test('applies the session validator', () async {
    final strict = createAdapter(
      sessionValidator: (session) async {
        if (!(session.user?.roles.contains('admin') ?? false)) {
          throw const AuthFailure('Administrators only');
        }
      },
    );

    await expectLater(strict.validateSession(testSession()), completes);
    await expectLater(
      strict.validateSession(testSession(user: plainUser)),
      throwsA(isA<AuthFailure>()),
    );
  });

  test('simulates latency', () async {
    final slow = createAdapter(latency: const Duration(milliseconds: 30));
    final stopwatch = Stopwatch()..start();

    await slow.login(credentials('admin@example.com', 'secret123'));

    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(25));
  });
}
