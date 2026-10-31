import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/core/result/result.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../support/auth_test_support.dart';

void main() {
  setUpAll(registerAuthFallbacks);

  late MockAuthAdapter adapter;
  late InMemoryKeyValueStorage keyValueStorage;
  late AuthRepositoryImpl repository;

  AuthRepositoryImpl createRepository({SessionStorage? storage}) {
    return AuthRepositoryImpl(
      adapter: adapter,
      storage: storage ?? SecureSessionStorage(keyValueStorage),
      clock: () => testNow,
    );
  }

  setUp(() {
    adapter = MockAuthAdapter();
    stubAdapterDefaults(adapter);
    keyValueStorage = InMemoryKeyValueStorage();
    repository = createRepository();
  });

  group('restoreSession', () {
    test('returns null without touching the adapter when nothing is stored',
        () async {
      final result = await repository.restoreSession();

      expect(result, const Result<AuthSession?>.success(null));
      expect(repository.currentSession, isNull);
      verifyNever(() => adapter.fetchCurrentUser(any()));
      verifyNever(() => adapter.refresh(any()));
    });

    test('restores a valid session, reloads the user and validates it',
        () async {
      await persistSession(keyValueStorage, testSession(user: plainUser));
      when(() => adapter.fetchCurrentUser(any()))
          .thenAnswer((_) async => adminUser);

      final result = await repository.restoreSession();

      final session = result.valueOrNull;
      expect(session?.tokens, testTokens());
      expect(session?.user, adminUser);
      expect(repository.currentSession, session);
      verifyNever(() => adapter.refresh(any()));
      verify(() => adapter.validateSession(session!)).called(1);
      final persisted = await readPersistedSession(keyValueStorage);
      expect(persisted?.user, adminUser);
    });

    test('authenticated adapter calls see the session being restored',
        () async {
      await persistSession(keyValueStorage, testSession());
      AuthSession? visibleDuringFetch;
      when(() => adapter.fetchCurrentUser(any())).thenAnswer((_) async {
        visibleDuringFetch = repository.currentSession;
        return adminUser;
      });

      await repository.restoreSession();

      expect(visibleDuringFetch?.tokens.accessToken, 'access-1');
    });

    test('refreshes expired tokens and keeps the previous refresh token',
        () async {
      final expired = testTokens(
        expiresAt: testNow.subtract(const Duration(minutes: 1)),
      );
      await persistSession(keyValueStorage, testSession(tokens: expired));
      final renewed = AuthTokens(
        accessToken: 'access-2',
        expiresAt: testNow.add(const Duration(hours: 1)),
      );
      when(() => adapter.refresh(any())).thenAnswer((_) async => renewed);

      final result = await repository.restoreSession();

      verify(() => adapter.refresh(expired)).called(1);
      final tokens = result.valueOrNull?.tokens;
      expect(tokens?.accessToken, 'access-2');
      expect(tokens?.refreshToken, 'refresh-1');
      expect(tokens?.tokenType, 'Bearer');
      final persisted = await readPersistedSession(keyValueStorage);
      expect(persisted?.tokens.accessToken, 'access-2');
      expect(persisted?.tokens.refreshToken, 'refresh-1');
    });

    test('treats tokens expiring within the leeway as expired', () async {
      final expiringSoon = testTokens(
        expiresAt: testNow.add(const Duration(seconds: 10)),
      );
      await persistSession(keyValueStorage, testSession(tokens: expiringSoon));
      when(() => adapter.refresh(any()))
          .thenAnswer((_) async => testTokens(access: 'access-2'));

      final result = await repository.restoreSession();

      verify(() => adapter.refresh(expiringSoon)).called(1);
      expect(result.valueOrNull?.tokens.accessToken, 'access-2');
    });

    for (final failure in <Failure>[
      const UnauthorizedFailure(),
      const AuthFailure('Refresh token revoked'),
    ]) {
      test('clears the session when the refresh is rejected '
          '(${failure.runtimeType})', () async {
        await persistSession(
          keyValueStorage,
          testSession(
            tokens: testTokens(expiresAt: testNow.subtract(Duration.zero)),
          ),
        );
        when(() => adapter.refresh(any()))
            .thenAnswer((_) => Future<AuthTokens>.error(failure));

        final result = await repository.restoreSession();

        expect(result, const Result<AuthSession?>.success(null));
        expect(repository.currentSession, isNull);
        expect(await readPersistedSession(keyValueStorage), isNull);
        verifyNever(() => adapter.fetchCurrentUser(any()));
      });
    }

    for (final failure in <Failure>[
      const NetworkFailure(),
      const TimeoutFailure(),
    ]) {
      test('keeps the stored session when offline (${failure.runtimeType})',
          () async {
        final expired = testTokens(
          expiresAt: testNow.subtract(const Duration(minutes: 5)),
        );
        await persistSession(
          keyValueStorage,
          testSession(tokens: expired, user: plainUser),
        );
        when(() => adapter.refresh(any()))
            .thenAnswer((_) => Future<AuthTokens>.error(failure));
        when(() => adapter.fetchCurrentUser(any()))
            .thenAnswer((_) => Future<AuthUser?>.error(failure));

        final result = await repository.restoreSession();

        final session = result.valueOrNull;
        expect(session, isNotNull);
        expect(session?.tokens, expired);
        expect(session?.user, plainUser);
        expect(repository.currentSession, session);
        expect(await readPersistedSession(keyValueStorage), isNotNull);
      });
    }

    test('discards expired tokens that cannot be refreshed', () async {
      await persistSession(
        keyValueStorage,
        testSession(
          tokens: testTokens(
            refresh: null,
            expiresAt: testNow.subtract(const Duration(seconds: 1)),
          ),
        ),
      );

      final result = await repository.restoreSession();

      expect(result, const Result<AuthSession?>.success(null));
      expect(await readPersistedSession(keyValueStorage), isNull);
      verifyNever(() => adapter.refresh(any()));
    });

    test('returns unexpected refresh failures without clearing the session',
        () async {
      await persistSession(
        keyValueStorage,
        testSession(tokens: testTokens(expiresAt: testNow)),
      );
      when(() => adapter.refresh(any())).thenAnswer(
        (_) => Future<AuthTokens>.error(const ParsingFailure('bad payload')),
      );

      final result = await repository.restoreSession();

      expect(result.failureOrNull, isA<ParsingFailure>());
      expect(repository.currentSession, isNull);
      expect(await readPersistedSession(keyValueStorage), isNotNull);
    });

    test('clears the session when the user lookup is unauthorized', () async {
      await persistSession(keyValueStorage, testSession());
      when(() => adapter.fetchCurrentUser(any())).thenAnswer(
        (_) => Future<AuthUser?>.error(const UnauthorizedFailure()),
      );

      final result = await repository.restoreSession();

      expect(result, const Result<AuthSession?>.success(null));
      expect(repository.currentSession, isNull);
      expect(await readPersistedSession(keyValueStorage), isNull);
      verifyNever(() => adapter.validateSession(any()));
    });

    test('falls back to the stored user when the user lookup fails', () async {
      await persistSession(keyValueStorage, testSession(user: plainUser));
      when(() => adapter.fetchCurrentUser(any())).thenAnswer(
        (_) => Future<AuthUser?>.error(
          const ServerFailure('Internal error', statusCode: 500),
        ),
      );

      final result = await repository.restoreSession();

      expect(result.valueOrNull?.user, plainUser);
      expect(repository.currentSession?.user, plainUser);
    });

    test('clears the session and returns the failure when validation rejects',
        () async {
      await persistSession(keyValueStorage, testSession());
      const rejection = AuthFailure('Subscription expired');
      when(() => adapter.validateSession(any()))
          .thenAnswer((_) => Future<void>.error(rejection));

      final result = await repository.restoreSession();

      expect(result, const Result<AuthSession?>.failure(rejection));
      expect(repository.currentSession, isNull);
      expect(await readPersistedSession(keyValueStorage), isNull);
    });

    test('reports unreadable storage as a StorageFailure', () async {
      repository = createRepository(
        storage: FailingSessionStorage(failReads: true),
      );

      final result = await repository.restoreSession();

      expect(result.failureOrNull, isA<StorageFailure>());
    });

    test('revalidates an active session from memory', () async {
      final expired = testTokens(
        expiresAt: testNow.subtract(const Duration(minutes: 1)),
      );
      when(() => adapter.login(any()))
          .thenAnswer((_) async => testSession(tokens: expired));
      await repository.login(const AuthCredentials(<String, Object?>{}));
      when(() => adapter.refresh(any()))
          .thenAnswer((_) async => testTokens(access: 'access-2'));
      when(() => adapter.fetchCurrentUser(any()))
          .thenAnswer((_) async => plainUser);

      final result = await repository.restoreSession();

      verify(() => adapter.refresh(expired)).called(1);
      expect(result.valueOrNull?.tokens.accessToken, 'access-2');
      expect(result.valueOrNull?.user, plainUser);
      expect((await readPersistedSession(keyValueStorage))?.user, plainUser);
    });

    test('keeps tokens refreshed by the networking layer during restoration',
        () async {
      await persistSession(keyValueStorage, testSession());
      when(() => adapter.refresh(any()))
          .thenAnswer((_) async => testTokens(access: 'access-2'));
      when(() => adapter.fetchCurrentUser(any())).thenAnswer((_) async {
        // Simulates the ApiClient refreshing after a 401 on the profile call.
        await repository.refreshTokens();
        return adminUser;
      });

      final result = await repository.restoreSession();

      expect(result.valueOrNull?.tokens.accessToken, 'access-2');
      final persisted = await readPersistedSession(keyValueStorage);
      expect(persisted?.tokens.accessToken, 'access-2');
    });
  });

  group('login', () {
    const credentials = AuthCredentials(<String, Object?>{
      'email': 'admin@example.com',
      'password': 'secret123',
    });

    test('persists the session and makes it current', () async {
      final session = testSession();
      when(() => adapter.login(any())).thenAnswer((_) async => session);

      final result = await repository.login(credentials);

      expect(result, Result<AuthSession>.success(session));
      expect(repository.currentSession, session);
      verify(() => adapter.login(credentials)).called(1);
      verify(() => adapter.validateSession(session)).called(1);
      final persisted = await readPersistedSession(keyValueStorage);
      expect(persisted?.tokens, session.tokens);
      expect(persisted?.user, adminUser);
    });

    test('replaces the stored user of a previous account', () async {
      await persistSession(keyValueStorage, testSession(user: plainUser));
      when(() => adapter.login(any()))
          .thenAnswer((_) async => testSession(user: null));

      await repository.login(credentials);

      final persisted = await readPersistedSession(keyValueStorage);
      expect(persisted?.user, isNull);
    });

    test('returns adapter failures unchanged', () async {
      const failure = AuthFailure('Invalid credentials');
      when(() => adapter.login(any()))
          .thenAnswer((_) => Future<AuthSession>.error(failure));

      final result = await repository.login(credentials);

      expect(result, const Result<AuthSession>.failure(failure));
      expect(repository.currentSession, isNull);
    });

    test('wraps unexpected errors into an UnexpectedFailure', () async {
      when(() => adapter.login(any()))
          .thenAnswer((_) => Future<AuthSession>.error(StateError('boom')));

      final result = await repository.login(credentials);

      expect(result.failureOrNull, isA<UnexpectedFailure>());
    });

    test('rejects sessions refused by validateSession', () async {
      const rejection = AuthFailure('Account disabled');
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());
      when(() => adapter.validateSession(any()))
          .thenAnswer((_) => Future<void>.error(rejection));

      final result = await repository.login(credentials);

      expect(result, const Result<AuthSession>.failure(rejection));
      expect(repository.currentSession, isNull);
      expect(await readPersistedSession(keyValueStorage), isNull);
    });

    test('lets validateSession make authenticated calls', () async {
      final session = testSession();
      AuthSession? visible;
      when(() => adapter.login(any())).thenAnswer((_) async => session);
      when(() => adapter.validateSession(any())).thenAnswer((_) async {
        visible = repository.currentSession;
      });

      await repository.login(credentials);

      expect(visible, session);
    });

    test('reports storage failures and restores the previous session',
        () async {
      repository = createRepository(
        storage: FailingSessionStorage(failWrites: true),
      );
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());

      final result = await repository.login(credentials);

      expect(result.failureOrNull, isA<StorageFailure>());
      expect(repository.currentSession, isNull);
    });
  });

  group('logout', () {
    Future<void> signIn() async {
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());
      await repository.login(const AuthCredentials(<String, Object?>{}));
    }

    test('signs out remotely and clears storage and memory', () async {
      await signIn();

      await repository.logout();

      verify(() => adapter.logout(testSession())).called(1);
      expect(repository.currentSession, isNull);
      expect(await readPersistedSession(keyValueStorage), isNull);
    });

    test('clears the local session even when the adapter throws', () async {
      await signIn();
      when(() => adapter.logout(any())).thenAnswer(
        (_) => Future<void>.error(const NetworkFailure()),
      );

      await repository.logout();

      expect(repository.currentSession, isNull);
      expect(await readPersistedSession(keyValueStorage), isNull);
    });

    test('signs out a persisted session that was not restored yet', () async {
      await persistSession(keyValueStorage, testSession());

      await repository.logout();

      verify(() => adapter.logout(testSession())).called(1);
      expect(await readPersistedSession(keyValueStorage), isNull);
    });

    test('never throws when the storage cannot be cleared', () async {
      repository = createRepository(
        storage: FailingSessionStorage(failClear: true),
      );

      await expectLater(repository.logout(), completes);
      expect(repository.currentSession, isNull);
    });
  });

  group('refreshTokens', () {
    Future<void> signIn({AuthTokens? tokens}) async {
      when(() => adapter.login(any()))
          .thenAnswer((_) async => testSession(tokens: tokens));
      await repository.login(const AuthCredentials(<String, Object?>{}));
    }

    test('returns null without a session', () async {
      expect(await repository.refreshTokens(), isNull);
      verifyNever(() => adapter.refresh(any()));
    });

    test('returns null without a refresh token', () async {
      await signIn(tokens: testTokens(refresh: null));

      expect(await repository.refreshTokens(), isNull);
      verifyNever(() => adapter.refresh(any()));
    });

    test('shares one refresh between concurrent callers', () async {
      await signIn();
      final pending = Completer<AuthTokens>();
      when(() => adapter.refresh(any())).thenAnswer((_) => pending.future);

      final first = repository.refreshTokens();
      final second = repository.refreshTokens();
      pending.complete(testTokens(access: 'access-2', refresh: 'refresh-2'));
      final results = await Future.wait(<Future<AuthTokens?>>[first, second]);

      verify(() => adapter.refresh(any())).called(1);
      expect(results[0]?.accessToken, 'access-2');
      expect(results[1]?.accessToken, 'access-2');
    });

    test('starts a new refresh once the previous one completed', () async {
      await signIn();
      when(() => adapter.refresh(any()))
          .thenAnswer((_) async => testTokens(access: 'access-2'));

      await repository.refreshTokens();
      await repository.refreshTokens();

      verify(() => adapter.refresh(any())).called(2);
    });

    test('persists the new tokens, keeps the refresh token and the user',
        () async {
      await signIn();
      when(() => adapter.refresh(any())).thenAnswer(
        (_) async => const AuthTokens(accessToken: 'access-2'),
      );

      final tokens = await repository.refreshTokens();

      expect(tokens?.accessToken, 'access-2');
      expect(tokens?.refreshToken, 'refresh-1');
      expect(repository.currentSession?.tokens, tokens);
      expect(repository.currentSession?.user, adminUser);
      final persisted = await readPersistedSession(keyValueStorage);
      expect(persisted?.tokens.accessToken, 'access-2');
      expect(persisted?.tokens.refreshToken, 'refresh-1');
    });

    test('returns null on failure without clearing the session', () async {
      await signIn();

      final tokens = await repository.refreshTokens();

      expect(tokens, isNull);
      expect(repository.currentSession, testSession());
      expect(await readPersistedSession(keyValueStorage), isNotNull);
    });

    test('a forced restoration of the same session keeps the refresh valid',
        () async {
      await signIn();
      final pending = Completer<AuthTokens>();
      when(() => adapter.refresh(any())).thenAnswer((_) => pending.future);

      final refresh = repository.refreshTokens();
      final restore = repository.restoreSession();
      pending.complete(testTokens(access: 'access-2'));

      expect((await refresh)?.accessToken, 'access-2');
      expect((await restore).valueOrNull?.tokens.accessToken, 'access-2');
      expect(repository.currentSession?.tokens.accessToken, 'access-2');
    });

    test('never resurrects a session signed out during the refresh', () async {
      await signIn();
      final pending = Completer<AuthTokens>();
      when(() => adapter.refresh(any())).thenAnswer((_) => pending.future);

      final refresh = repository.refreshTokens();
      await repository.logout();
      pending.complete(testTokens(access: 'access-2'));

      expect(await refresh, isNull);
      expect(repository.currentSession, isNull);
      expect(await readPersistedSession(keyValueStorage), isNull);
    });
  });

  group('register', () {
    const data = AuthCredentials(<String, Object?>{
      'email': 'new@example.com',
      'password': 'secret123',
    });

    test('persists the session returned by the adapter', () async {
      final session = testSession(user: plainUser);
      when(() => adapter.register(any())).thenAnswer((_) async => session);

      final result = await repository.register(data);

      expect(result, Result<AuthSession?>.success(session));
      expect(repository.currentSession, session);
      expect((await readPersistedSession(keyValueStorage))?.user, plainUser);
    });

    test('returns null when the backend does not sign the user in', () async {
      when(() => adapter.register(any())).thenAnswer((_) async => null);

      final result = await repository.register(data);

      expect(result, const Result<AuthSession?>.success(null));
      expect(repository.currentSession, isNull);
      expect(await readPersistedSession(keyValueStorage), isNull);
    });

    test('returns adapter failures', () async {
      when(() => adapter.register(any())).thenAnswer(
        (_) => Future<AuthSession?>.error(const UnsupportedFailure()),
      );

      final result = await repository.register(data);

      expect(result.failureOrNull, isA<UnsupportedFailure>());
    });

    test('exposes the adapter capabilities', () {
      when(() => adapter.supportsRegistration).thenReturn(true);
      when(() => adapter.supportsPasswordRecovery).thenReturn(true);

      expect(repository.supportsRegistration, isTrue);
      expect(repository.supportsPasswordRecovery, isTrue);
    });
  });

  group('password recovery', () {
    const data = AuthCredentials(<String, Object?>{'email': 'a@b.co'});

    test('passes requests through to the adapter', () async {
      when(() => adapter.requestPasswordReset(any())).thenAnswer((_) async {});
      when(() => adapter.confirmPasswordReset(any())).thenAnswer((_) async {});

      expect((await repository.requestPasswordReset(data)).isSuccess, isTrue);
      expect((await repository.confirmPasswordReset(data)).isSuccess, isTrue);
      verify(() => adapter.requestPasswordReset(data)).called(1);
      verify(() => adapter.confirmPasswordReset(data)).called(1);
    });

    test('returns failures as results', () async {
      const failure = ValidationFailure('Invalid code');
      when(() => adapter.confirmPasswordReset(any()))
          .thenAnswer((_) => Future<void>.error(failure));

      final result = await repository.confirmPasswordReset(data);

      expect(result, const Result<void>.failure(failure));
    });
  });

  group('updateSession', () {
    test('fails without an active session', () async {
      final result = await repository.updateSession(testSession());

      expect(result.failureOrNull, isA<AuthFailure>());
    });

    test('replaces and persists the active session', () async {
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());
      await repository.login(const AuthCredentials(<String, Object?>{}));
      final updated = testSession(
        user: adminUser.copyWith(displayName: 'Ada Lovelace'),
      );

      final result = await repository.updateSession(updated);

      expect(result.isSuccess, isTrue);
      expect(repository.currentSession, updated);
      final persisted = await readPersistedSession(keyValueStorage);
      expect(persisted?.user?.displayName, 'Ada Lovelace');
    });
  });

  test('clearSession removes the session without contacting the backend',
      () async {
    when(() => adapter.login(any())).thenAnswer((_) async => testSession());
    await repository.login(const AuthCredentials(<String, Object?>{}));

    await repository.clearSession();

    expect(repository.currentSession, isNull);
    expect(await readPersistedSession(keyValueStorage), isNull);
    verifyNever(() => adapter.logout(any()));
  });
}
