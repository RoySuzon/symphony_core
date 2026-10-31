import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/auth/domain/entities/auth_tokens.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../helpers/storage_test_helpers.dart';

void main() {
  final tokens = AuthTokens(
    accessToken: 'access-123',
    refreshToken: 'refresh-456',
    tokenType: 'Bearer',
    expiresAt: DateTime.utc(2030, 1, 2, 3, 4, 5),
    extra: const <String, Object?>{
      'idToken': 'id-789',
      'scopes': <Object?>['read', 'write'],
    },
  );

  group('with a working storage', () {
    late InMemoryKeyValueStorage storage;
    late SecureSessionStorage session;

    setUp(() {
      storage = InMemoryKeyValueStorage(<String, String>{'unrelated': 'keep'});
      session = SecureSessionStorage(storage);
    });

    test('uses namespaced keys', () {
      expect(session.namespace, 'symphony');
      expect(session.tokensKey, 'symphony.session.tokens');
      expect(session.userKey, 'symphony.session.user');

      final custom = SecureSessionStorage(storage, namespace: 'my_app');
      expect(custom.tokensKey, 'my_app.session.tokens');
      expect(custom.userKey, 'my_app.session.user');
    });

    test('returns null when nothing is stored', () async {
      expect(await session.readTokens(), isNull);
      expect(await session.readUser(), isNull);
    });

    test('round trips tokens including expiresAt and extra', () async {
      await session.writeTokens(tokens);

      expect(await storage.containsKey('symphony.session.tokens'), isTrue);
      final restored = await session.readTokens();
      expect(restored, tokens);
      expect(restored!.expiresAt, DateTime.utc(2030, 1, 2, 3, 4, 5));
      expect(restored.extra, tokens.extra);
    });

    test('round trips tokens with only an access token', () async {
      await session.writeTokens(const AuthTokens(accessToken: 'only'));

      final restored = await session.readTokens();
      expect(restored, const AuthTokens(accessToken: 'only'));
      expect(restored!.refreshToken, isNull);
      expect(restored.expiresAt, isNull);
      expect(restored.extra, isEmpty);
    });

    test('replaces previous tokens', () async {
      await session.writeTokens(tokens);
      await session.writeTokens(const AuthTokens(accessToken: 'new'));

      expect(await session.readTokens(), const AuthTokens(accessToken: 'new'));
    });

    test('round trips the user payload', () async {
      final user = <String, Object?>{
        'id': 'u1',
        'roles': <Object?>['admin'],
        'profile': <String, Object?>{'name': 'Ada'},
      };

      await session.writeUser(user);

      expect(await session.readUser(), user);
    });

    test('clear removes the session only', () async {
      await session.writeTokens(tokens);
      await session.writeUser(<String, Object?>{'id': 'u1'});

      await session.clear();

      expect(await session.readTokens(), isNull);
      expect(await session.readUser(), isNull);
      expect(await storage.readAll(), <String, String>{'unrelated': 'keep'});
    });

    group('corrupted payloads are deleted and reported as no session', () {
      Future<void> expectTokensCleanedUp(String raw) async {
        await storage.write(session.tokensKey, raw);

        expect(await session.readTokens(), isNull);
        expect(await storage.containsKey(session.tokensKey), isFalse);
      }

      test('invalid JSON', () => expectTokensCleanedUp('{"accessToken": '));

      test('not a JSON object', () => expectTokensCleanedUp('["a", "b"]'));

      test(
        'missing access token',
        () => expectTokensCleanedUp(jsonEncode({'refreshToken': 'r'})),
      );

      test(
        'field of the wrong type',
        () => expectTokensCleanedUp(
          jsonEncode({'accessToken': 'a', 'refreshToken': 42}),
        ),
      );

      test('corrupted user payload', () async {
        await storage.write(session.userKey, 'not json');

        expect(await session.readUser(), isNull);
        expect(await storage.containsKey(session.userKey), isFalse);
      });
    });

    test('rejects tokens whose extra values are not JSON-encodable', () async {
      final invalid = AuthTokens(
        accessToken: 'a',
        extra: <String, Object?>{'issuedAt': DateTime(2024)},
      );

      await expectLater(
        session.writeTokens(invalid),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.encode,
            message: 'Unable to access the session storage.',
          ),
        ),
      );
      expect(await storage.containsKey(session.tokensKey), isFalse);
    });
  });

  group('with a failing storage', () {
    late MockKeyValueStorage storage;
    late SecureSessionStorage session;

    setUp(() {
      storage = MockKeyValueStorage();
      session = SecureSessionStorage(storage);
    });

    test('wraps backend errors into StorageFailures', () async {
      final error = StateError('backend down');
      when(() => storage.read(any())).thenThrow(error);
      when(
        () => storage.write(any(), any()),
      ).thenAnswer((_) => Future<void>.error(error));

      await expectLater(
        session.readTokens(),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.read,
            cause: same(error),
            message: 'Unable to access the session storage.',
          ),
        ),
      );
      await expectLater(
        session.readUser(),
        throwsA(isStorageFailure(code: StorageFailureCodes.read)),
      );
      await expectLater(
        session.writeTokens(tokens),
        throwsA(isStorageFailure(code: StorageFailureCodes.write)),
      );
      await expectLater(
        session.writeUser(<String, Object?>{'id': 'u1'}),
        throwsA(isStorageFailure(code: StorageFailureCodes.write)),
      );
    });

    test('uses the custom failure message', () async {
      when(() => storage.read(any())).thenThrow(StateError('backend down'));
      final localized = SecureSessionStorage(
        storage,
        failureMessage: 'Session indisponible.',
      );

      await expectLater(
        localized.readTokens(),
        throwsA(isStorageFailure(message: 'Session indisponible.')),
      );
    });

    test('propagates Failures thrown by the storage unchanged', () async {
      const failure = StorageFailure('secure storage down', code: 'custom');
      when(
        () => storage.read(any()),
      ).thenAnswer((_) => Future<String?>.error(failure));

      await expectLater(session.readTokens(), throwsA(same(failure)));
    });

    test('clear attempts both keys and rethrows the first error', () async {
      final error = StateError('cannot delete');
      when(() => storage.delete('symphony.session.tokens')).thenThrow(error);
      when(
        () => storage.delete('symphony.session.user'),
      ).thenAnswer((_) async {});

      await expectLater(
        session.clear(),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.delete,
            cause: same(error),
          ),
        ),
      );
      verify(() => storage.delete('symphony.session.tokens')).called(1);
      verify(() => storage.delete('symphony.session.user')).called(1);
    });

    test('ignores cleanup errors of corrupted payloads', () async {
      when(() => storage.read(any())).thenAnswer((_) async => 'corrupted');
      when(() => storage.delete(any())).thenThrow(StateError('read-only'));

      expect(await session.readTokens(), isNull);
      expect(await session.readUser(), isNull);
    });
  });
}
