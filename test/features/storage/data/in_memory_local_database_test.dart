import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../helpers/storage_test_helpers.dart';

void main() {
  group('StorageCodec.json', () {
    test('delegates to the given functions', () {
      final json = todoCodec.encode(bread);

      expect(json, <String, Object?>{
        'id': '2',
        'title': 'Buy bread',
        'done': false,
        'tags': <String>['food'],
      });
      expect(todoCodec.decode(json), bread);
    });
  });

  group('InMemoryLocalStore', () {
    for (final withCodec in <bool>[false, true]) {
      group(withCodec ? 'with a codec' : 'without codec', () {
        late InMemoryLocalStore<Todo> store;

        setUp(() {
          store = InMemoryLocalStore<Todo>(codec: withCodec ? todoCodec : null);
        });

        test('supports CRUD operations', () async {
          expect(await store.get('1'), isNull);
          expect(await store.getAll(), isEmpty);
          expect(await store.count(), 0);

          await store.put('1', milk);
          await store.putAll(<String, Todo>{'2': bread, '3': call});

          expect(await store.get('1'), milk);
          expect(await store.getAll(), <Todo>[milk, bread, call]);
          expect(await store.count(), 3);

          final updated = Todo(id: '1', title: milk.title, done: true);
          await store.put('1', updated);
          expect(await store.get('1'), updated);
          expect(await store.getAll(), <Todo>[
            updated,
            bread,
            call,
          ], reason: 'updating a value keeps its position');

          await store.delete('2');
          await store.delete('missing');
          expect(await store.getAll(), <Todo>[updated, call]);

          await store.clear();
          expect(await store.getAll(), isEmpty);
          expect(await store.count(), 0);
        });

        test('getAll returns an unmodifiable list', () async {
          await store.put('1', milk);

          final all = await store.getAll();

          expect(() => all.add(bread), throwsUnsupportedError);
        });
      });
    }

    test('starts with the initial values', () async {
      final store = InMemoryLocalStore<Todo>(
        codec: todoCodec,
        initialValues: <String, Todo>{'1': milk, '2': bread},
      );

      expect(await store.getAll(), <Todo>[milk, bread]);
    });

    test('with a codec, values are copies that went through JSON', () async {
      final store = InMemoryLocalStore<Todo>(codec: todoCodec);
      final tags = <String>['a'];
      final todo = Todo(id: '1', title: 'Mutable tags', tags: tags);

      await store.put('1', todo);
      tags.add('b');
      final restored = await store.get('1');

      expect(restored, isNot(same(todo)));
      expect(restored!.tags, <String>['a']);
    });

    test('without codec, values are kept as-is', () async {
      final store = InMemoryLocalStore<Todo>();

      await store.put('1', milk);

      expect(await store.get('1'), same(milk));
      expect(store.codec, isNull);
    });

    test('rejects values that are not JSON-encodable', () async {
      final store = InMemoryLocalStore<Todo>(codec: nonJsonTodoCodec);

      await expectLater(
        store.put('1', milk),
        throwsA(isStorageFailure(code: StorageFailureCodes.encode)),
      );
      expect(
        () => InMemoryLocalStore<Todo>(
          codec: nonJsonTodoCodec,
          initialValues: <String, Todo>{'1': milk},
        ),
        throwsA(isStorageFailure(code: StorageFailureCodes.encode)),
      );
      expect(await store.count(), 0);
    });

    test('putAll is all or nothing', () async {
      final store = InMemoryLocalStore<Todo>(
        codec: StorageCodec<Todo>.json(
          fromJson: Todo.fromJson,
          toJson:
              (todo) =>
                  todo.id == '2'
                      ? <String, Object?>{'at': DateTime(2024)}
                      : todo.toJson(),
        ),
      );

      await expectLater(
        store.putAll(<String, Todo>{'1': milk, '2': bread}),
        throwsA(isStorageFailure(code: StorageFailureCodes.encode)),
      );
      expect(await store.count(), 0);
    });

    test('reports decoding errors as StorageFailures', () async {
      final store = InMemoryLocalStore<Todo>(codec: undecodableTodoCodec);
      await store.put('1', milk);

      await expectLater(
        store.get('1'),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.decode,
            cause: isFormatException,
            message: 'Unable to process the stored data.',
          ),
        ),
      );
      await expectLater(
        store.getAll(),
        throwsA(isStorageFailure(code: StorageFailureCodes.decode)),
      );
      expect(await store.count(), 1);
    });

    group('watchAll', () {
      late InMemoryLocalStore<Todo> store;

      setUp(() {
        store = InMemoryLocalStore<Todo>(
          codec: todoCodec,
          initialValues: <String, Todo>{'1': milk},
        );
      });

      test('emits the current values, then every change', () async {
        final emissions = <List<Todo>>[];
        final subscription = store.watchAll().listen(emissions.add);
        addTearDown(() => subscription.cancel());

        await settle();
        expect(emissions, <List<Todo>>[
          <Todo>[milk],
        ]);

        await store.put('2', bread);
        await store.putAll(<String, Todo>{'3': call});
        await store.delete('1');
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

      test('does not emit for operations that change nothing', () async {
        final emissions = <List<Todo>>[];
        final subscription = store.watchAll().listen(emissions.add);
        addTearDown(() => subscription.cancel());
        await settle();

        await store.delete('missing');
        await store.putAll(<String, Todo>{});
        await store.clear();
        await store.clear();
        await settle();

        expect(emissions, <List<Todo>>[
          <Todo>[milk],
          <Todo>[],
        ]);
      });

      test('each listener receives the current values first', () async {
        final stream = store.watchAll();
        final first = <List<Todo>>[];
        final second = <List<Todo>>[];

        final firstSubscription = stream.listen(first.add);
        addTearDown(() => firstSubscription.cancel());
        await settle();
        await store.put('2', bread);
        final secondSubscription = stream.listen(second.add);
        addTearDown(() => secondSubscription.cancel());
        await settle();

        expect(first, <List<Todo>>[
          <Todo>[milk],
          <Todo>[milk, bread],
        ]);
        expect(second, <List<Todo>>[
          <Todo>[milk, bread],
        ]);
      });

      test('stops emitting once cancelled', () async {
        final emissions = <List<Todo>>[];
        final subscription = store.watchAll().listen(emissions.add);
        await settle();

        await subscription.cancel();
        await store.put('2', bread);
        await settle();

        expect(emissions, hasLength(1));
      });

      test('emits decoding errors', () async {
        final broken = InMemoryLocalStore<Todo>(codec: undecodableTodoCodec);
        await broken.put('1', milk);
        final errors = <Object>[];
        final subscription = broken.watchAll().listen(
          (_) {},
          onError: errors.add,
        );
        addTearDown(() => subscription.cancel());

        await settle();
        await broken.put('2', bread);
        await settle();

        expect(errors, <Object>[
          isStorageFailure(code: StorageFailureCodes.decode),
          isStorageFailure(code: StorageFailureCodes.decode),
        ]);
      });
    });
  });

  group('InMemoryLocalDatabase', () {
    late InMemoryLocalDatabase database;

    setUp(() {
      database = InMemoryLocalDatabase();
    });

    test('returns the same store for the same name', () async {
      final todos = database.store<Todo>('todos', todoCodec);
      await todos.put('1', milk);

      final again = database.store<Todo>('todos', todoCodec);

      expect(again, same(todos));
      expect(await again.getAll(), <Todo>[milk]);
    });

    test('isolates stores by name', () async {
      await database.store<Todo>('todos', todoCodec).put('1', milk);

      expect(await database.store<Todo>('archive', todoCodec).count(), 0);
    });

    test('creates stores that copy values through their codec', () async {
      final store = database.store<Todo>('todos', todoCodec);

      expect(store, isA<InMemoryLocalStore<Todo>>());
      expect((store as InMemoryLocalStore<Todo>).codec, same(todoCodec));
    });

    test('passes the custom failure message to its stores', () async {
      final localized = InMemoryLocalDatabase(
        failureMessage: 'Données illisibles.',
      );
      final store = localized.store<Todo>('todos', undecodableTodoCodec);
      await store.put('1', milk);

      expect(localized.failureMessage, 'Données illisibles.');
      await expectLater(
        store.getAll(),
        throwsA(isStorageFailure(message: 'Données illisibles.')),
      );
    });

    test('rejects an empty name or a different value type', () {
      database.store<Todo>('todos', todoCodec);

      expect(() => database.store<Todo>('', todoCodec), throwsArgumentError);
      expect(
        () => database.store<Map<String, Object?>>(
          'todos',
          StorageCodec<Map<String, Object?>>.json(
            fromJson: (json) => json,
            toJson: (value) => value,
          ),
        ),
        throwsStateError,
      );
    });

    test('opens on demand and closes', () async {
      expect(database.isOpen, isFalse);

      await database.open();
      await database.open();
      expect(database.isOpen, isTrue);

      await database.close();
      await database.close();
      expect(database.isOpen, isFalse);

      await database.store<Todo>('todos', todoCodec).count();
      expect(database.isOpen, isTrue, reason: 'stores open the database');
    });

    test('close completes the watchAll streams and keeps the data', () async {
      final todos = database.store<Todo>('todos', todoCodec);
      await todos.put('1', milk);
      var done = false;
      final subscription = todos.watchAll().listen(
        (_) {},
        onDone: () => done = true,
      );
      addTearDown(() => subscription.cancel());
      await settle();

      await database.close();
      await settle();

      expect(done, isTrue);
      expect(await todos.getAll(), <Todo>[milk]);
      expect(database.isOpen, isTrue, reason: 'reopened by the last read');
    });
  });
}
