import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/features/auth/domain/entities/auth_tokens.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../helpers/storage_test_helpers.dart';

void main() {
  const tokens = AuthTokens(accessToken: 'access', refreshToken: 'refresh');

  late MockFlutterSecureStorage plugin;

  setUp(() {
    plugin = MockFlutterSecureStorage();
  });

  // `Override` is not exported by `flutter_riverpod.dart` in Riverpod 3, so
  // override lists are inferred from `ProviderContainer.overrides` instead of
  // being typed explicitly.
  ProviderContainer track(ProviderContainer container) {
    addTearDown(container.dispose);
    return container;
  }

  ProviderContainer createContainer() => track(
        ProviderContainer(
          overrides: [flutterSecureStorageProvider.overrideWithValue(plugin)],
        ),
      );

  test('flutterSecureStorageProvider defaults to FlutterSecureStorage', () {
    final container = track(ProviderContainer());

    expect(
      container.read(flutterSecureStorageProvider),
      isA<FlutterSecureStorage>(),
    );
  });

  group('secureStorageProvider', () {
    test('wraps the plugin of flutterSecureStorageProvider', () {
      final container = createContainer();

      expect(
        container.read(secureStorageProvider),
        isA<SecureKeyValueStorage>()
            .having((storage) => storage.storage, 'storage', same(plugin))
            .having((storage) => storage.keyPrefix, 'keyPrefix', isEmpty),
      );
    });

    test('reads and writes through the plugin', () async {
      final backend = backWithMap(plugin);
      final storage = createContainer().read(secureStorageProvider);

      await storage.write('api_key', 'secret');

      expect(backend, <String, String>{'api_key': 'secret'});
      expect(await storage.read('api_key'), 'secret');
      verify(() => plugin.write(key: 'api_key', value: 'secret')).called(1);
    });

    test('can be overridden, for example in tests', () async {
      final memory = InMemoryKeyValueStorage();
      final container = track(
        ProviderContainer(
          overrides: [secureStorageProvider.overrideWithValue(memory)],
        ),
      );

      await container.read(sessionStorageProvider).writeTokens(tokens);

      expect(await memory.containsKey('symphony.session.tokens'), isTrue);
      verifyZeroInteractions(plugin);
    });
  });

  group('sessionStorageProvider', () {
    test('persists the session in the secure storage', () async {
      final backend = backWithMap(plugin);
      final container = createContainer();
      final session = container.read(sessionStorageProvider);

      expect(
        session,
        isA<SecureSessionStorage>().having(
          (session) => session.storage,
          'storage',
          same(container.read(secureStorageProvider)),
        ),
      );

      await session.writeTokens(tokens);
      await session.writeUser(<String, Object?>{'id': 'u1'});

      expect(
        backend.keys,
        unorderedEquals(<String>[
          'symphony.session.tokens',
          'symphony.session.user',
        ]),
      );
      expect(await session.readTokens(), tokens);
      expect(await session.readUser(), <String, Object?>{'id': 'u1'});

      await session.clear();

      expect(backend, isEmpty);
    });

    test('reports platform errors as StorageFailures', () async {
      final error = PlatformException(code: 'keychain_locked');
      when(() => plugin.read(key: any(named: 'key'))).thenThrow(error);

      await expectLater(
        createContainer().read(sessionStorageProvider).readTokens(),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.read,
            cause: same(error),
          ),
        ),
      );
    });
  });

  group('localDatabaseProvider', () {
    test('defaults to an in-memory database closed on dispose', () async {
      final container = ProviderContainer();
      final database = container.read(localDatabaseProvider);

      expect(database, isA<InMemoryLocalDatabase>());
      expect(container.read(localDatabaseProvider), same(database));

      final todos = database.store<Todo>('todos', todoCodec);
      await todos.put('1', milk);
      var done = false;
      final subscription = todos.watchAll().listen(
            (_) {},
            onDone: () => done = true,
          );
      addTearDown(() => subscription.cancel());
      await settle();
      expect(database.isOpen, isTrue);

      container.dispose();
      await settle();

      expect(database.isOpen, isFalse);
      expect(done, isTrue);
    });

    test('can be overridden with a persistent database', () async {
      final memory = InMemoryKeyValueStorage();
      final container = track(
        ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWithValue(memory),
            localDatabaseProvider.overrideWith((ref) {
              final database = KeyValueLocalDatabase(
                ref.watch(secureStorageProvider),
              );
              ref.onDispose(() => unawaited(database.close()));
              return database;
            }),
          ],
        ),
      );

      final database = container.read(localDatabaseProvider);
      await database.store<Todo>('todos', todoCodec).put('1', milk);

      expect(database, isA<KeyValueLocalDatabase>());
      expect(await memory.containsKey('symphony.db.todos'), isTrue);
      expect(
        await KeyValueLocalDatabase(memory)
            .store<Todo>('todos', todoCodec)
            .getAll(),
        <Todo>[milk],
      );
    });
  });
}
