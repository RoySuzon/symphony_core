import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/access/access_context.dart';
import 'package:symphony_core/src/core/access/auth_status.dart';
import 'package:symphony_core/src/core/config/symphony_config.dart';
import 'package:symphony_core/src/core/di/core_providers.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../support/auth_test_support.dart';

void main() {
  setUpAll(registerAuthFallbacks);

  late MockAuthAdapter adapter;
  late InMemoryKeyValueStorage storage;

  setUp(() {
    adapter = MockAuthAdapter();
    stubAdapterDefaults(adapter);
    storage = InMemoryKeyValueStorage();
  });

  ProviderContainer createContainer() =>
      createAuthContainer(adapter: adapter, storage: storage);

  const credentials = AuthCredentials(<String, Object?>{
    'email': 'admin@example.com',
    'password': 'secret123',
  });

  test('build returns the unknown state without side effects', () async {
    final container = createContainer();

    expect(container.read(authControllerProvider), const AuthState.unknown());
    expect(container.read(accessContextProvider), AccessContext.unknown);
    expect(container.read(isAuthenticatedProvider), isFalse);
    expect(container.read(currentUserProvider), isNull);
    verifyZeroInteractions(adapter);
  });

  group('restoreSession', () {
    test('ends unauthenticated without a persisted session', () async {
      final container = createContainer();

      await container.read(authControllerProvider.notifier).restoreSession();

      expect(
        container.read(authControllerProvider),
        const AuthState.unauthenticated(),
      );
      expect(
        container.read(accessContextProvider).status,
        AuthStatus.unauthenticated,
      );
    });

    test('ends authenticated with a persisted session', () async {
      await persistSession(storage, testSession());
      final container = createContainer();

      await container.read(authControllerProvider.notifier).restoreSession();

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthAuthenticated>());
      expect(state.user, adminUser);
      expect(container.read(isAuthenticatedProvider), isTrue);
    });

    test('reports failures through the unauthenticated state', () async {
      final container = createAuthContainer(
        adapter: adapter,
        overrides: <Object>[
          sessionStorageProvider.overrideWithValue(
            FailingSessionStorage(failReads: true),
          ),
        ],
      );

      await container.read(authControllerProvider.notifier).restoreSession();

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthUnauthenticated>());
      expect(
        (state as AuthUnauthenticated).failure,
        isA<StorageFailure>(),
      );
    });

    test('is idempotent unless forced', () async {
      await persistSession(storage, testSession());
      final container = createContainer();
      final controller = container.read(authControllerProvider.notifier);

      await controller.restoreSession();
      await controller.restoreSession();
      verify(() => adapter.fetchCurrentUser(any())).called(1);

      await controller.restoreSession(force: true);
      verify(() => adapter.fetchCurrentUser(any())).called(1);
    });

    test('a forced restoration re-applies the business rules', () async {
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());
      final container = createContainer();
      final controller = container.read(authControllerProvider.notifier);
      await controller.login(credentials);
      const rejection = AuthFailure('Subscription expired');
      when(() => adapter.validateSession(any()))
          .thenAnswer((_) => Future<void>.error(rejection));

      await controller.restoreSession(force: true);

      expect(
        container.read(authControllerProvider),
        const AuthState.unauthenticated(failure: rejection),
      );
      expect(await readPersistedSession(storage), isNull);
    });

    test('concurrent calls share one restoration', () async {
      await persistSession(storage, testSession());
      final pending = Completer<AuthUser?>();
      when(() => adapter.fetchCurrentUser(any()))
          .thenAnswer((_) => pending.future);
      final container = createContainer();
      final controller = container.read(authControllerProvider.notifier);

      final first = controller.restoreSession();
      final second = controller.restoreSession();
      expect(identical(first, second), isTrue);
      expect(container.read(authControllerProvider), isA<AuthUnknown>());

      pending.complete(adminUser);
      await Future.wait(<Future<void>>[first, second]);

      verify(() => adapter.fetchCurrentUser(any())).called(1);
      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    });

    test('a slow restoration never overrides a newer sign-in', () async {
      await persistSession(storage, testSession(user: plainUser));
      final pending = Completer<AuthUser?>();
      when(() => adapter.fetchCurrentUser(any()))
          .thenAnswer((_) => pending.future);
      final fresh = testSession(tokens: testTokens(access: 'fresh'));
      when(() => adapter.login(any())).thenAnswer((_) async => fresh);
      final container = createContainer();
      final controller = container.read(authControllerProvider.notifier);

      final restoring = controller.restoreSession();
      await controller.login(credentials);
      pending.complete(plainUser);
      await restoring;

      expect(container.read(authControllerProvider).session, fresh);
    });

    test('notifies listeners of every transition', () async {
      await persistSession(storage, testSession());
      final container = createContainer();
      final states = <AuthState>[];
      final subscription = container.listen<AuthState>(
        authControllerProvider,
        (previous, next) => states.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final controller = container.read(authControllerProvider.notifier);

      await controller.restoreSession();
      await controller.logout();

      expect(states.map((s) => s.status), <AuthStatus>[
        AuthStatus.unknown,
        AuthStatus.authenticated,
        AuthStatus.unauthenticated,
      ]);
    });
  });

  group('login', () {
    test('authenticates and exposes roles and permissions', () async {
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());
      final container = createContainer();

      final result =
          await container.read(authControllerProvider.notifier).login(
                credentials,
              );

      expect(result.isSuccess, isTrue);
      final access = container.read(accessContextProvider);
      expect(access.isAuthenticated, isTrue);
      expect(access.roles, <String>{'admin'});
      expect(access.permissions, <String>{'orders.read', 'orders.write'});
      expect(access.hasPermission('orders.write'), isTrue);
      expect(container.read(currentUserProvider), adminUser);
      expect(
        container.read(authControllerProvider.notifier).session,
        testSession(),
      );
      expect(await readPersistedSession(storage), testSession());
    });

    test('returns the failure and keeps the state', () async {
      const failure = AuthFailure('Invalid credentials');
      when(() => adapter.login(any()))
          .thenAnswer((_) => Future<AuthSession>.error(failure));
      final container = createContainer();
      final controller = container.read(authControllerProvider.notifier);
      await controller.restoreSession();

      final result = await controller.login(credentials);

      expect(result.failureOrNull, failure);
      expect(
        container.read(authControllerProvider),
        const AuthState.unauthenticated(),
      );
    });

    test('never throws when authentication is not configured', () async {
      final container = ProviderContainer(
        overrides: [
          symphonyConfigProvider.overrideWithValue(testConfig),
          secureStorageProvider.overrideWithValue(InMemoryKeyValueStorage()),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);

      final result = await controller.login(credentials);
      await controller.restoreSession();

      expect(result.failureOrNull, isA<UnexpectedFailure>());
      final state = container.read(authControllerProvider);
      expect(state, isA<AuthUnauthenticated>());
      expect(
        (state as AuthUnauthenticated).failure,
        isA<UnexpectedFailure>(),
      );
    });
  });

  test('logout ends unauthenticated and clears the persisted session',
      () async {
    when(() => adapter.login(any())).thenAnswer((_) async => testSession());
    when(() => adapter.logout(any()))
        .thenAnswer((_) => Future<void>.error(const NetworkFailure()));
    final container = createContainer();
    final controller = container.read(authControllerProvider.notifier);
    await controller.login(credentials);

    await controller.logout();

    expect(
      container.read(authControllerProvider),
      const AuthState.unauthenticated(),
    );
    expect(
        container.read(accessContextProvider), AccessContext.unauthenticated);
    expect(await readPersistedSession(storage), isNull);
    verify(() => adapter.logout(testSession())).called(1);
  });

  group('handleSessionExpired', () {
    test('clears the session and records the reason', () async {
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());
      final container = createContainer();
      final controller = container.read(authControllerProvider.notifier);
      await controller.login(credentials);

      await controller.handleSessionExpired();

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthUnauthenticated>());
      expect(
        (state as AuthUnauthenticated).failure,
        const UnauthorizedFailure(),
      );
      expect(await readPersistedSession(storage), isNull);
      verifyNever(() => adapter.logout(any()));
    });

    test('keeps a custom reason and ignores repeated calls', () async {
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());
      final container = createContainer();
      final controller = container.read(authControllerProvider.notifier);
      await controller.login(credentials);
      const reason = AuthFailure('Signed in on another device');

      await controller.handleSessionExpired(reason);
      await controller.handleSessionExpired();

      expect(
        container.read(authControllerProvider),
        const AuthState.unauthenticated(failure: reason),
      );
    });
  });

  group('updateSession', () {
    test('replaces and persists the session while authenticated', () async {
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());
      final container = createContainer();
      final controller = container.read(authControllerProvider.notifier);
      await controller.login(credentials);
      final updated = testSession(
        user: adminUser.copyWith(roles: <String>{'admin', 'auditor'}),
      );

      controller.updateSession(updated);
      await flushMicrotasks();

      expect(container.read(authControllerProvider).session, updated);
      expect(
        container.read(accessContextProvider).roles,
        <String>{'admin', 'auditor'},
      );
      expect(container.read(authRepositoryProvider).currentSession, updated);
      expect((await readPersistedSession(storage))?.user, updated.user);
    });

    test('is ignored while not authenticated', () async {
      final container = createContainer();
      final controller = container.read(authControllerProvider.notifier);
      await controller.restoreSession();

      controller.updateSession(testSession());

      expect(
        container.read(authControllerProvider),
        const AuthState.unauthenticated(),
      );
    });
  });

  group('register', () {
    test('authenticates when the backend returns a session', () async {
      when(() => adapter.register(any()))
          .thenAnswer((_) async => testSession(user: plainUser));
      final container = createContainer();

      final result = await container
          .read(authControllerProvider.notifier)
          .register(credentials);

      expect(result.valueOrNull?.user, plainUser);
      expect(container.read(currentUserProvider), plainUser);
    });

    test('keeps the state when the user must sign in separately', () async {
      when(() => adapter.register(any())).thenAnswer((_) async => null);
      final container = createContainer();
      final controller = container.read(authControllerProvider.notifier);
      await controller.restoreSession();

      final result = await controller.register(credentials);

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isNull);
      expect(
        container.read(authControllerProvider),
        const AuthState.unauthenticated(),
      );
    });
  });

  test('password recovery actions return results', () async {
    when(() => adapter.requestPasswordReset(any())).thenAnswer((_) async {});
    when(() => adapter.confirmPasswordReset(any())).thenAnswer(
      (_) => Future<void>.error(const ValidationFailure('Invalid code')),
    );
    final container = createContainer();
    final controller = container.read(authControllerProvider.notifier);

    final requested = await controller.requestPasswordReset(credentials);
    final confirmed = await controller.confirmPasswordReset(credentials);

    expect(requested.isSuccess, isTrue);
    expect(confirmed.failureOrNull, isA<ValidationFailure>());
  });

  test('exposes the adapter capabilities', () {
    when(() => adapter.supportsRegistration).thenReturn(true);
    final container = createContainer();
    final controller = container.read(authControllerProvider.notifier);

    expect(controller.supportsRegistration, isTrue);
    expect(controller.supportsPasswordRecovery, isFalse);
  });

  test('works end-to-end with the in-memory adapter', () async {
    final memoryAdapter = InMemoryAuthAdapter(accounts: demoAccounts);
    final first = createAuthContainer(adapter: memoryAdapter, storage: storage);
    final firstController = first.read(authControllerProvider.notifier);
    await firstController.restoreSession();
    await firstController.login(
      AuthCredentials.emailPassword(
        email: 'admin@example.com',
        password: 'secret123',
      ),
    );
    expect(first.read(accessContextProvider).hasRole('admin'), isTrue);

    // A second container simulates an application restart.
    final second = createAuthContainer(
      adapter: InMemoryAuthAdapter(accounts: demoAccounts),
      storage: storage,
    );
    await second.read(authControllerProvider.notifier).restoreSession();

    expect(second.read(currentUserProvider), adminUser);
  });

  test('uses the configuration of the container', () {
    final container = createContainer();

    expect(container.read(symphonyConfigProvider), isA<SymphonyConfig>());
    expect(container.read(authRepositoryProvider), isA<AuthRepositoryImpl>());
  });
}
