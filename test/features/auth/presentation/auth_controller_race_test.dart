import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../data/auth_repository_race_test.dart' show GatedSessionStorage;
import '../support/auth_test_support.dart';

/// Regression tests for races between `AuthController` actions and the
/// session refreshes performed by the networking layer.
void main() {
  setUpAll(registerAuthFallbacks);

  const credentials = AuthCredentials(<String, Object?>{'email': 'a@b.c'});

  late MockAuthAdapter adapter;
  late InMemoryKeyValueStorage keyValueStorage;
  late GatedSessionStorage storage;
  late ProviderContainer container;

  AuthController controllerOf() =>
      container.read(authControllerProvider.notifier);

  setUp(() {
    adapter = MockAuthAdapter();
    stubAdapterDefaults(adapter);
    keyValueStorage = InMemoryKeyValueStorage();
    storage = GatedSessionStorage(SecureSessionStorage(keyValueStorage));
    container = createAuthContainer(
      adapter: adapter,
      storage: keyValueStorage,
      overrides: <Object>[sessionStorageProvider.overrideWithValue(storage)],
    );
  });

  test('a sign-in racing the start-up restoration never leaves the state '
      'authenticated with a session the repository dropped', () async {
    final validation = Completer<void>();
    when(() => adapter.login(any())).thenAnswer((_) async => testSession());
    when(
      () => adapter.validateSession(any()),
    ).thenAnswer((_) => validation.future);
    final readGate = storage.readGate = Completer<void>();

    final restoring = controllerOf().restoreSession();
    final signingIn = controllerOf().login(credentials);
    await flushMicrotasks();
    readGate.complete();
    await flushMicrotasks();

    // The sign-in is still being validated: its session must not show up.
    expect(
      container.read(authControllerProvider),
      isNot(isA<AuthAuthenticated>()),
    );

    validation.completeError(const AuthFailure('Account disabled'));
    final result = await signingIn;
    await restoring;

    expect(result.failureOrNull, const AuthFailure('Account disabled'));
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    expect(container.read(authRepositoryProvider).currentSession, isNull);
  });

  group('profile updates racing a token refresh', () {
    final renewed = testTokens(access: 'access-2', refresh: 'refresh-2');

    setUp(() async {
      when(
        () => adapter.login(any()),
      ).thenAnswer((_) async => testSession(user: plainUser));
      when(() => adapter.refresh(any())).thenAnswer((_) async => renewed);
      final result = await controllerOf().login(credentials);
      expect(result.isSuccess, isTrue);
    });

    void expectRenewedEverywhere(AuthUser user) {
      final repositorySession =
          container.read(authRepositoryProvider).currentSession;
      final state = container.read(authControllerProvider);
      expect(repositorySession?.tokens, renewed);
      expect(repositorySession?.user, user);
      expect(state.session?.tokens, renewed);
      expect(state.user, user);
    }

    test(
      'an update made while the refresh is persisted keeps the new tokens',
      () async {
        final writeGate = storage.writeGate = Completer<void>();
        // What the ApiClient does after a 401.
        final refreshing =
            container.read(sessionTokenDelegateProvider).refreshAccessToken();
        await flushMicrotasks();

        // The application updates the profile from the state it can see.
        final session = controllerOf().session!;
        controllerOf().updateSession(session.copyWith(user: adminUser));
        storage.writeGate = null;
        writeGate.complete();

        expect(await refreshing, 'access-2');
        await flushMicrotasks();

        expectRenewedEverywhere(adminUser);
        final persisted = await readPersistedSession(keyValueStorage);
        expect(persisted?.tokens, renewed);
        expect(persisted?.user, adminUser);
      },
    );

    test('an update built from a session read before the refresh keeps the '
        'new tokens', () async {
      final stale = controllerOf().session!;
      await container.read(sessionTokenDelegateProvider).refreshAccessToken();

      controllerOf().updateSession(stale.copyWith(user: adminUser));
      await flushMicrotasks();

      expectRenewedEverywhere(adminUser);
      expect((await readPersistedSession(keyValueStorage))?.tokens, renewed);
    });
  });

  test(
    'a profile update changing only custom user data reaches listeners',
    () async {
      when(
        () => adapter.login(any()),
      ).thenAnswer((_) async => testSession(user: plainUser));
      await controllerOf().login(credentials);
      final users = <AuthUser?>[];
      final states = <AuthState>[];
      container
        ..listen<AuthUser?>(currentUserProvider, (_, next) => users.add(next))
        ..listen<AuthState>(
          authControllerProvider,
          (_, next) => states.add(next),
        );

      final updated = plainUser.copyWith(
        data: <String, Object?>{
          'plan': 'pro',
          'address': <String, Object?>{'city': 'Paris'},
        },
      );
      controllerOf().updateSession(
        controllerOf().session!.copyWith(user: updated),
      );
      // Dependent providers are notified by Riverpod's scheduler.
      await flushMicrotasks();

      expect(states, hasLength(1));
      expect(users, <AuthUser?>[updated]);
      expect(container.read(currentUserProvider)?.data['plan'], 'pro');
    },
  );
}
