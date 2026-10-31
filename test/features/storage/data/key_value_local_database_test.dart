import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../helpers/storage_test_helpers.dart';

void main() {
  late InMemoryKeyValueStorage storage;

  setUp(() {
    storage = InMemoryKeyValueStorage();
  });

  KeyValueLocalStore<Todo> createStore({StorageCodec<Todo>? codec}) =>
      KeyValueLocalStore<Todo>(
        storage,
        key: 'todos',
        codec: codec ?? todoCodec,
      );

  group('KeyValueLocalStore', () {
    test('exposes its configuration', () {
      final store = createStore();

      expect(store.storage, same(storage));
      expect(store.key, 'todos');
      expect(store.codec, same(todoCodec));
      expect(store.failureMessage, 'Unable to access the local data.');
      expect(
        () => KeyValueLocalStore<Todo>(storage, key: '', codec: todoCodec),
        throwsArgumentError,
      );
    });

    test('supports CRUD operations', () async {
      final store = createStore();

      expect(await store.get('1'), isNull);
      expect(await store.getAll(), isEmpty);
      expect(await store.count(), 0);

      await store.put('1', milk);
      await store.putAll(<String, Todo>{'2': bread, '3': call});

      expect(await store.get('1'), milk);
      expect(await store.get('missing'), isNull);
      expect(await store.getAll(), <Todo>[milk, bread, call]);
      expect(await store.count(), 3);

      final updated = Todo(id: '2', title: bread.title, done: true);
      await store.put('2', updated);
      expect(await store.getAll(), <Todo>[milk, updated, call]);

      await store.delete('1');
      await store.delete('missing');
      expect(await store.getAll(), <Todo>[updated, call]);

      await store.clear();
      expect(await store.getAll(), isEmpty);
      expect(await store.count(), 0);
    });

    test('persists the collection as a JSON array of entries', () async {
      final store = createStore();

      await store.put('1', milk);
      await store.put('2', bread);

      expect(jsonDecode((await storage.read('todos'))!), <Object?>[
        <String, Object?>{'id': '1', 'value': milk.toJson()},
        <String, Object?>{'id': '2', 'value': bread.toJson()},
      ]);
    });

    test('removes the key when the collection becomes empty', () async {
      final store = createStore();
      await store.put('1', milk);

      await store.delete('1');

      expect(await storage.containsKey('todos'), isFalse);
    });

    test('keeps insertion order, even for numeric ids', () async {
      final store = createStore();
      const ten = Todo(id: '10', title: 'ten');
      const two = Todo(id: '2', title: 'two');
      const one = Todo(id: '1', title: 'one');

      await store.putAll(<String, Todo>{'10': ten, '2': two});
      await store.put('1', one);

      expect(await createStore().getAll(), <Todo>[ten, two, one]);
    });

    test('persists data across instances', () async {
      await createStore().putAll(<String, Todo>{'1': milk, '2': bread});

      final reopened = createStore();

      expect(await reopened.getAll(), <Todo>[milk, bread]);
      expect(await reopened.get('2'), bread);
      expect(await reopened.count(), 2);
    });

    test('concurrent writes never lose updates', () async {
      final store = createStore();

      await Future.wait(<Future<void>>[
        for (var i = 0; i < 25; i++)
          store.put('$i', Todo(id: '$i', title: 'Todo $i')),
      ]);

      expect(await store.count(), 25);
      expect(await createStore().count(), 25);
    });

    test('rejects values that are not JSON-encodable', () async {
      await createStore().put('1', milk);
      final store = createStore(codec: nonJsonTodoCodec);

      await expectLater(
        store.put('2', bread),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.encode,
            cause: isA<JsonUnsupportedObjectError>(),
          ),
        ),
      );
      expect(await createStore().getAll(), <Todo>[milk]);
    });

    test('putAll is all or nothing', () async {
      final store = createStore(
        codec: StorageCodec<Todo>.json(
          fromJson: Todo.fromJson,
          toJson: (todo) =>
              todo.id == '3' ? throw StateError('bad todo') : todo.toJson(),
        ),
      );

      await expectLater(
        store.putAll(<String, Todo>{'1': milk, '3': call}),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.encode,
            cause: isStateError,
          ),
        ),
      );
      expect(await storage.containsKey('todos'), isFalse);
    });

    group('corrupted data', () {
      test('an invalid document fails every read and write but clear',
          () async {
        await storage.write('todos', '[{"id": "1", "value": ');
        final store = createStore();
        final isDecodeFailure = throwsA(
          isStorageFailure(
            code: StorageFailureCodes.decode,
            message: 'Unable to access the local data.',
          ),
        );

        await expectLater(store.get('1'), isDecodeFailure);
        await expectLater(store.getAll(), isDecodeFailure);
        await expectLater(store.count(), isDecodeFailure);
        await expectLater(store.put('1', milk), isDecodeFailure);
        await expectLater(store.delete('1'), isDecodeFailure);
        expect(
          await storage.read('todos'),
          '[{"id": "1", "value": ',
          reason: 'corrupted data is left untouched',
        );

        await store.clear();

        expect(await store.getAll(), isEmpty);
        await store.put('1', milk);
        expect(await store.getAll(), <Todo>[milk]);
      });

      for (final document in <String>[
        '{"1": {"id": "1"}}',
        '[1, 2]',
        '[{"value": {}}]',
        '[{"id": 1, "value": {}}]',
      ]) {
        test('an unexpected structure fails to decode: $document', () async {
          await storage.write('todos', document);

          await expectLater(
            createStore().getAll(),
            throwsA(
              isStorageFailure(
                code: StorageFailureCodes.decode,
                cause: isFormatException,
              ),
            ),
          );
        });
      }

      test('an undecodable value only affects that value', () async {
        final store = createStore();
        await store.put('1', milk);
        await storage.write(
          'todos',
          jsonEncode(<Object?>[
            <String, Object?>{'id': '1', 'value': milk.toJson()},
            <String, Object?>{
              'id': '2',
              'value': <String, Object?>{'id': '2', 'title': 42},
            },
          ]),
        );

        expect(await store.get('1'), milk);
        await expectLater(
          store.get('2'),
          throwsA(isStorageFailure(code: StorageFailureCodes.decode)),
        );
        await expectLater(
          store.getAll(),
          throwsA(isStorageFailure(code: StorageFailureCodes.decode)),
        );

        await store.put('3', call);

        final raw = jsonDecode((await storage.read('todos'))!) as List<Object?>;
        expect(raw, hasLength(3), reason: 'the undecodable value is kept');
        expect(await store.count(), 3);
      });
    });

    group('backend errors', () {
      late MockKeyValueStorage failing;

      setUp(() {
        failing = MockKeyValueStorage();
      });

      test('are wrapped into StorageFailures with the custom message',
          () async {
        final error = StateError('disk full');
        when(() => failing.read(any())).thenAnswer((_) async => null);
        when(() => failing.write(any(), any())).thenThrow(error);
        final store = KeyValueLocalStore<Todo>(
          failing,
          key: 'todos',
          codec: todoCodec,
          failureMessage: 'Données locales indisponibles.',
        );

        await expectLater(
          store.put('1', milk),
          throwsA(
            isStorageFailure(
              code: StorageFailureCodes.write,
              cause: same(error),
              message: 'Données locales indisponibles.',
            ),
          ),
        );
      });

      test('Failures are propagated unchanged', () async {
        const failure = StorageFailure('locked', code: 'custom');
        when(() => failing.read(any())).thenAnswer(
          (_) => Future<String?>.error(failure),
        );
        final store = KeyValueLocalStore<Todo>(
          failing,
          key: 'todos',
          codec: todoCodec,
        );

        await expectLater(store.getAll(), throwsA(same(failure)));
      });

      test('a failed operation does not block the next ones', () async {
        var calls = 0;
        when(() => failing.read(any())).thenAnswer((_) async {
          calls++;
          if (calls == 1) throw StateError('transient');
          return null;
        });
        final store = KeyValueLocalStore<Todo>(
          failing,
          key: 'todos',
          codec: todoCodec,
        );

        final first = store.getAll();
        final second = store.getAll();

        await expectLater(
          first,
          throwsA(isStorageFailure(code: StorageFailureCodes.read)),
        );
        expect(await second, isEmpty);
      });
    });

    group('watchAll', () {
      test('emits the current values, then every change', () async {
        await createStore().put('1', milk);
        final store = createStore();
        final emissions = <List<Todo>>[];

        final subscription = store.watchAll().listen(emissions.add);
        addTearDown(() => subscription.cancel());
        // Not awaited on purpose: the initial snapshot must come first.
        unawaited(store.put('2', bread));
        await store.putAll(<String, Todo>{'3': call});
        await store.delete('1');
        await store.delete('missing');
        await store.clear();
        await store.clear();
        await settle();

        expect(emissions, <List<Todo>>[
          <Todo>[milk],
          <Todo>[milk, bread],
          <Todo>[milk, bread, call],
          <Todo>[bread, call],
          <Todo>[],
        ]);
      });

      test('emits values exactly as later reads decode them', () async {
        // The encoded map holds an object with a toJson() method: it only
        // decodes once it went through JSON, like persisted data.
        final store = createStore(
          codec: StorageCodec<Todo>.json(
            fromJson: (json) => Todo.fromJson(
              json['payload']! as Map<String, Object?>,
            ),
            toJson: (todo) => <String, Object?>{'payload': _JsonBox(todo)},
          ),
        );
        final emissions = <List<Todo>>[];
        final errors = <Object>[];
        final subscription = store.watchAll().listen(
              emissions.add,
              onError: errors.add,
            );
        addTearDown(() => subscription.cancel());

        await store.put('1', milk);
        await settle();

        expect(errors, isEmpty);
        expect(emissions, <List<Todo>>[
          <Todo>[],
          <Todo>[milk],
        ]);
        expect(await store.getAll(), <Todo>[milk]);
      });

      test('the stream can be listened to several times', () async {
        final store = createStore();
        final stream = store.watchAll();
        final first = <List<Todo>>[];
        final second = <List<Todo>>[];

        final firstSubscription = stream.listen(first.add);
        addTearDown(() => firstSubscription.cancel());
        await store.put('1', milk);
        final secondSubscription = stream.listen(second.add);
        addTearDown(() => secondSubscription.cancel());
        await store.put('2', bread);
        await settle();

        expect(first, <List<Todo>>[
          <Todo>[],
          <Todo>[milk],
          <Todo>[milk, bread],
        ]);
        expect(second, <List<Todo>>[
          <Todo>[milk],
          <Todo>[milk, bread],
        ]);
      });

      test('reports read errors and recovers after clear', () async {
        await storage.write('todos', 'corrupted');
        final store = createStore();
        final emissions = <List<Todo>>[];
        final errors = <Object>[];

        final subscription = store.watchAll().listen(
              emissions.add,
              onError: errors.add,
            );
        addTearDown(() => subscription.cancel());
        await settle();
        await store.clear();
        await store.put('1', milk);
        await settle();

        expect(errors, <Object>[
          isStorageFailure(code: StorageFailureCodes.decode),
        ]);
        expect(emissions, <List<Todo>>[
          <Todo>[],
          <Todo>[milk],
        ]);
      });

      test('a listener cancelled before its first value is ignored', () async {
        final store = createStore();
        final emissions = <List<Todo>>[];

        final subscription = store.watchAll().listen(emissions.add);
        await subscription.cancel();
        await store.put('1', milk);
        await settle();

        expect(emissions, isEmpty);
      });
    });
  });

  group('KeyValueLocalDatabase', () {
    late KeyValueLocalDatabase database;

    setUp(() {
      database = KeyValueLocalDatabase(storage);
    });

    test('persists each store under a prefixed key', () async {
      expect(database.storage, same(storage));
      expect(database.keyPrefix, 'symphony.db.');
      expect(database.keyFor('todos'), 'symphony.db.todos');

      await database.store<Todo>('todos', todoCodec).put('1', milk);
      await database.store<Todo>('archive', todoCodec).put('2', bread);

      expect(
        (await storage.readAll()).keys,
        unorderedEquals(<String>['symphony.db.todos', 'symphony.db.archive']),
      );
      expect(
        await database.store<Todo>('todos', todoCodec).getAll(),
        <Todo>[milk],
      );
    });

    test('uses the custom key prefix and failure message', () async {
      final custom = KeyValueLocalDatabase(
        storage,
        keyPrefix: 'cache/',
        failureMessage: 'Cache indisponible.',
      );
      final store = custom.store<Todo>('todos', todoCodec);
      await store.put('1', milk);

      expect(await storage.containsKey('cache/todos'), isTrue);
      expect(store, isA<KeyValueLocalStore<Todo>>());
      expect(
        (store as KeyValueLocalStore<Todo>).failureMessage,
        'Cache indisponible.',
      );
    });

    test('persists data across database instances', () async {
      await database.store<Todo>('todos', todoCodec).putAll(
        <String, Todo>{'1': milk, '2': bread},
      );
      await database.close();

      final reopened = KeyValueLocalDatabase(storage);

      expect(
        await reopened.store<Todo>('todos', todoCodec).getAll(),
        <Todo>[milk, bread],
      );
    });

    test('returns the same store for the same name', () {
      final todos = database.store<Todo>('todos', todoCodec);

      expect(database.store<Todo>('todos', todoCodec), same(todos));
    });

    test('rejects an empty name or a different value type', () {
      database.store<Todo>('todos', todoCodec);

      expect(() => database.store<Todo>('', todoCodec), throwsArgumentError);
      expect(
        () => database.store<String>(
          'todos',
          StorageCodec<String>.json(
            fromJson: (json) => json['value'] as String,
            toJson: (value) => <String, Object?>{'value': value},
          ),
        ),
        throwsStateError,
      );
    });

    test('opens on demand and closes', () async {
      expect(database.isOpen, isFalse);

      await database.open();
      expect(database.isOpen, isTrue);

      await database.close();
      expect(database.isOpen, isFalse);

      await database.store<Todo>('todos', todoCodec).count();
      expect(database.isOpen, isTrue, reason: 'stores open the database');
    });

    test('close waits for pending writes and completes the streams', () async {
      final todos = database.store<Todo>('todos', todoCodec);
      var done = false;
      final subscription = todos.watchAll().listen(
            (_) {},
            onDone: () => done = true,
          );
      addTearDown(() => subscription.cancel());

      unawaited(todos.putAll(<String, Todo>{'1': milk, '2': bread}));
      await database.close();

      expect(database.isOpen, isFalse);
      expect(await storage.containsKey('symphony.db.todos'), isTrue);
      await settle();
      expect(done, isTrue);
    });
  });
}

/// Wraps a [Todo] in an object that is only JSON-encodable through toJson().
class _JsonBox {
  const _JsonBox(this.todo);

  final Todo todo;

  Map<String, Object?> toJson() => todo.toJson();
}
