import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/core/result/result.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../support/auth_test_support.dart';

/// Regression tests for races between session transitions of
/// `AuthRepositoryImpl` (restoration, sign-in, refresh, profile updates).
void main() {
  setUpAll(registerAuthFallbacks);

  const credentials = AuthCredentials(<String, Object?>{'email': 'a@b.c'});

  late MockAuthAdapter adapter;
  late InMemoryKeyValueStorage keyValueStorage;
  late GatedSessionStorage storage;
  late AuthRepositoryImpl repository;

  setUp(() {
    adapter = MockAuthAdapter();
    stubAdapterDefaults(adapter);
    keyValueStorage = InMemoryKeyValueStorage();
    storage = GatedSessionStorage(SecureSessionStorage(keyValueStorage));
    repository = AuthRepositoryImpl(
      adapter: adapter,
      storage: storage,
      clock: () => testNow,
    );
  });

  group('restoration racing a sign-in', () {
    test(
      'never reports a sign-in session that is still being validated',
      () async {
        final validation = Completer<void>();
        when(() => adapter.login(any())).thenAnswer((_) async => testSession());
        when(
          () => adapter.validateSession(any()),
        ).thenAnswer((_) => validation.future);
        final readGate = storage.readGate = Completer<void>();

        final restoring = repository.restoreSession();
        final signingIn = repository.login(credentials);
        await flushMicrotasks();
        readGate.complete();
        await flushMicrotasks();
        validation.completeError(const AuthFailure('Account disabled'));

        // Nothing was persisted and the sign-in was rejected: the restoration
        // must report "no session", not the session of the rejected sign-in.
        expect(await restoring, const Result<AuthSession?>.success(null));
        expect(
          (await signingIn).failureOrNull,
          const AuthFailure('Account disabled'),
        );
        expect(repository.currentSession, isNull);
        expect(await readPersistedSession(keyValueStorage), isNull);
      },
    );

    test(
      'a rejected sign-in does not cancel the restoration it overtook',
      () async {
        await persistSession(keyValueStorage, testSession(user: plainUser));
        when(() => adapter.login(any())).thenAnswer(
          (_) async => testSession(tokens: testTokens(access: 'access-new')),
        );
        when(() => adapter.validateSession(any())).thenAnswer((
          invocation,
        ) async {
          final session = invocation.positionalArguments.first as AuthSession;
          if (session.tokens.accessToken == 'access-new') {
            throw const AuthFailure('Account disabled');
          }
        });
        final readGate = storage.readGate = Completer<void>();

        final restoring = repository.restoreSession();
        final result = await repository.login(credentials);
        readGate.complete();
        final restored = (await restoring).valueOrNull;

        expect(result.failureOrNull, const AuthFailure('Account disabled'));
        expect(restored?.tokens.accessToken, 'access-1');
        expect(restored?.user, plainUser);
        expect(repository.currentSession, restored);
      },
    );

    test('a sign-in is not delayed by the restoration and wins', () async {
      await persistSession(keyValueStorage, testSession(user: plainUser));
      final signedIn = testSession(
        tokens: testTokens(access: 'access-new', refresh: 'refresh-new'),
      );
      when(() => adapter.login(any())).thenAnswer((_) async => signedIn);
      final readGate = storage.readGate = Completer<void>();

      final restoring = repository.restoreSession();
      final result = await repository.login(credentials);
      readGate.complete();

      expect(result.valueOrNull, signedIn);
      expect((await restoring).valueOrNull, signedIn);
      expect(repository.currentSession, signedIn);
      expect(
        (await readPersistedSession(keyValueStorage))?.tokens.accessToken,
        'access-new',
      );
    });
  });

  group('updateSession racing a token refresh', () {
    final renewed = testTokens(access: 'access-2', refresh: 'refresh-2');

    setUp(() async {
      when(
        () => adapter.login(any()),
      ).thenAnswer((_) async => testSession(user: plainUser));
      when(() => adapter.refresh(any())).thenAnswer((_) async => renewed);
      await repository.login(credentials);
    });

    test('keeps the tokens of a refresh still being persisted', () async {
      final beforeRefresh = repository.currentSession!;
      final writeGate = storage.writeGate = Completer<void>();

      final refreshing = repository.refreshTokens();
      await flushMicrotasks();
      // A caller still holding the pre-refresh session updates the profile.
      final updating = repository.updateSession(
        beforeRefresh.copyWith(user: adminUser),
      );
      storage.writeGate = null;
      writeGate.complete();

      expect(await refreshing, renewed);
      expect((await updating).isSuccess, isTrue);
      expect(repository.currentSession?.tokens, renewed);
      expect(repository.currentSession?.user, adminUser);
      final persisted = await readPersistedSession(keyValueStorage);
      expect(persisted?.tokens, renewed);
      expect(persisted?.user, adminUser);
    });

    test('never reinstates tokens replaced by a completed refresh', () async {
      final stale = repository.currentSession!;
      expect(await repository.refreshTokens(), renewed);

      final result = await repository.updateSession(
        stale.copyWith(user: adminUser),
      );

      expect(result.isSuccess, isTrue);
      expect(repository.currentSession?.tokens, renewed);
      expect(repository.currentSession?.user, adminUser);
      expect((await readPersistedSession(keyValueStorage))?.tokens, renewed);
    });

    test('still accepts brand new tokens', () async {
      final current = repository.currentSession!;
      final elevated = testTokens(access: 'access-mfa', refresh: 'refresh-mfa');

      await repository.updateSession(current.copyWith(tokens: elevated));

      expect(repository.currentSession?.tokens, elevated);
      expect((await readPersistedSession(keyValueStorage))?.tokens, elevated);
    });
  });

  test(
    'a refresh of a previous session is not shared with the next one',
    () async {
      final staleRefresh = Completer<AuthTokens>();
      final renewedB = testTokens(access: 'access-B2', refresh: 'refresh-B2');
      when(() => adapter.refresh(any())).thenAnswer((invocation) {
        final current = invocation.positionalArguments.first as AuthTokens;
        return current.accessToken == 'access-1'
            ? staleRefresh.future
            : Future<AuthTokens>.value(renewedB);
      });
      when(() => adapter.login(any())).thenAnswer((_) async => testSession());
      await repository.login(credentials);

      final first = repository.refreshTokens();
      await repository.clearSession();
      when(() => adapter.login(any())).thenAnswer(
        (_) async => testSession(
          tokens: testTokens(access: 'access-B', refresh: 'refresh-B'),
          user: plainUser,
        ),
      );
      await repository.login(credentials);

      final second = repository.refreshTokens();
      staleRefresh.complete(testTokens(access: 'access-A2'));

      expect(await first, isNull);
      expect(await second, renewedB);
      expect(repository.currentSession?.tokens, renewedB);
      expect(repository.currentSession?.user, plainUser);
    },
  );
}

/// A [SessionStorage] whose token reads and writes can be held back.
class GatedSessionStorage extends SessionStorage {
  GatedSessionStorage(this.delegate);

  final SessionStorage delegate;

  /// When set, [readTokens] waits for it.
  Completer<void>? readGate;

  /// When set, [writeTokens] waits for it.
  Completer<void>? writeGate;

  @override
  Future<AuthTokens?> readTokens() async {
    final gate = readGate;
    if (gate != null) await gate.future;
    return delegate.readTokens();
  }

  @override
  Future<void> writeTokens(AuthTokens tokens) async {
    final gate = writeGate;
    if (gate != null) await gate.future;
    return delegate.writeTokens(tokens);
  }

  @override
  Future<Map<String, Object?>?> readUser() => delegate.readUser();

  @override
  Future<void> writeUser(Map<String, Object?> user) => delegate.writeUser(user);

  @override
  Future<void> clear() => delegate.clear();
}
