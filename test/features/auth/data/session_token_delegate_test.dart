import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/features/networking/domain/auth_token_delegate.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../support/auth_test_support.dart';

void main() {
  setUpAll(registerAuthFallbacks);

  group('SessionTokenDelegate', () {
    late MockAuthRepository repository;
    final refreshed = <AuthSession>[];
    final expired = <Failure>[];

    SessionTokenDelegate createDelegate({bool withExpiryHandler = true}) {
      return SessionTokenDelegate(
        repository: () => repository,
        onSessionRefreshed: refreshed.add,
        onExpired: withExpiryHandler ? expired.add : null,
      );
    }

    setUp(() {
      repository = MockAuthRepository();
      refreshed.clear();
      expired.clear();
      when(() => repository.clearSession()).thenAnswer((_) async {});
    });

    test('returns the access token of the current session', () async {
      when(() => repository.currentSession).thenReturn(testSession());
      final delegate = createDelegate();

      expect(await delegate.getAccessToken(), 'access-1');
    });

    test('returns null when signed out', () async {
      when(() => repository.currentSession).thenReturn(null);

      expect(await createDelegate().getAccessToken(), isNull);
    });

    test('refreshes, notifies the new session and returns the new token',
        () async {
      final renewed = testSession(tokens: testTokens(access: 'access-2'));
      when(() => repository.refreshTokens())
          .thenAnswer((_) async => renewed.tokens);
      when(() => repository.currentSession).thenReturn(renewed);

      final token = await createDelegate().refreshAccessToken();

      expect(token, 'access-2');
      expect(refreshed, <AuthSession>[renewed]);
    });

    test('returns null when refreshing is impossible', () async {
      when(() => repository.refreshTokens()).thenAnswer((_) async => null);

      expect(await createDelegate().refreshAccessToken(), isNull);
      expect(refreshed, isEmpty);
    });

    test('shares one refresh between concurrent requests', () async {
      final pending = Completer<AuthTokens?>();
      when(() => repository.refreshTokens()).thenAnswer((_) => pending.future);
      when(() => repository.currentSession).thenReturn(testSession());
      final delegate = createDelegate();

      final first = delegate.refreshAccessToken();
      final second = delegate.refreshAccessToken();
      pending.complete(testTokens());

      expect(await first, 'access-1');
      expect(await second, 'access-1');
      verify(() => repository.refreshTokens()).called(1);
      expect(refreshed, hasLength(1));
    });

    test('a failing listener does not break the refresh', () async {
      when(() => repository.refreshTokens())
          .thenAnswer((_) async => testTokens());
      when(() => repository.currentSession).thenReturn(testSession());
      final delegate = SessionTokenDelegate(
        repository: () => repository,
        onSessionRefreshed: (_) => throw StateError('listener failed'),
      );

      expect(await delegate.refreshAccessToken(), 'access-1');
    });

    test('ends the session through the expiry handler', () async {
      await createDelegate().onSessionExpired();

      expect(expired, hasLength(1));
      expect(expired.single, isA<UnauthorizedFailure>());
      verifyNever(() => repository.clearSession());
    });

    test('does not end a session started after the failed refresh', () async {
      when(() => repository.currentSession).thenReturn(testSession());
      when(() => repository.refreshTokens()).thenAnswer((_) async => null);
      final delegate = createDelegate();

      expect(await delegate.refreshAccessToken(), isNull);
      // The user signed in again before the networking layer gave up.
      when(() => repository.currentSession).thenReturn(
        testSession(tokens: testTokens(access: 'new-login')),
      );
      await delegate.onSessionExpired();

      expect(expired, isEmpty);
    });

    test('ends the session whose refresh failed', () async {
      when(() => repository.currentSession).thenReturn(testSession());
      when(() => repository.refreshTokens()).thenAnswer((_) async => null);
      final delegate = createDelegate();

      await delegate.refreshAccessToken();
      await delegate.onSessionExpired();

      expect(expired, hasLength(1));
    });

    test('clears the repository session without an expiry handler', () async {
      await createDelegate(withExpiryHandler: false).onSessionExpired();

      verify(() => repository.clearSession()).called(1);
    });
  });

  group('sessionTokenDelegateProvider', () {
    late MockAuthAdapter adapter;

    setUp(() {
      adapter = MockAuthAdapter();
      stubAdapterDefaults(adapter);
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());
    });

    test('is wired to the repository and the controller', () async {
      final storage = InMemoryKeyValueStorage();
      final container = createAuthContainer(adapter: adapter, storage: storage);
      final AuthTokenDelegate delegate =
          container.read(sessionTokenDelegateProvider);
      final controller = container.read(authControllerProvider.notifier);

      expect(await delegate.getAccessToken(), isNull);

      await controller.login(const AuthCredentials(<String, Object?>{}));
      expect(await delegate.getAccessToken(), 'access-1');

      when(() => adapter.refresh(any())).thenAnswer(
        (_) async => testTokens(access: 'access-2', refresh: 'refresh-2'),
      );
      expect(await delegate.refreshAccessToken(), 'access-2');
      expect(
        container.read(authControllerProvider).session?.tokens.accessToken,
        'access-2',
      );

      await delegate.onSessionExpired();
      final state = container.read(authControllerProvider);
      expect(state, isA<AuthUnauthenticated>());
      expect(
        (state as AuthUnauthenticated).failure,
        isA<UnauthorizedFailure>(),
      );
      expect(await readPersistedSession(storage), isNull);
      expect(await delegate.getAccessToken(), isNull);
    });
  });
}
