import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

/// Mocktail mock of the secure storage plugin.
class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

/// Mocktail mock of a [KeyValueStorage] backend.
class MockKeyValueStorage extends Mock implements KeyValueStorage {}

/// Stubs every method of [mock] used by `SecureKeyValueStorage` so that it
/// behaves like a real secure storage backed by the returned map.
Map<String, String> backWithMap(
  MockFlutterSecureStorage mock, [
  Map<String, String> initialValues = const <String, String>{},
]) {
  final values = Map<String, String>.of(initialValues);
  String keyOf(Invocation invocation) =>
      invocation.namedArguments[#key]! as String;

  when(() => mock.read(key: any(named: 'key'))).thenAnswer(
    (invocation) async => values[keyOf(invocation)],
  );
  when(
    () => mock.write(key: any(named: 'key'), value: any(named: 'value')),
  ).thenAnswer((invocation) async {
    final value = invocation.namedArguments[#value] as String?;
    if (value == null) {
      values.remove(keyOf(invocation));
    } else {
      values[keyOf(invocation)] = value;
    }
  });
  when(() => mock.delete(key: any(named: 'key'))).thenAnswer(
    (invocation) async {
      values.remove(keyOf(invocation));
    },
  );
  when(() => mock.containsKey(key: any(named: 'key'))).thenAnswer(
    (invocation) async => values.containsKey(keyOf(invocation)),
  );
  when(() => mock.readAll()).thenAnswer(
    (_) async => Map<String, String>.of(values),
  );
  when(() => mock.deleteAll()).thenAnswer((_) async => values.clear());
  return values;
}

/// Lets every pending microtask and timer-free async callback run.
Future<void> settle() => pumpEventQueue();

/// Matches a [StorageFailure] with the given [code], [cause] (value or
/// matcher) and [message].
TypeMatcher<StorageFailure> isStorageFailure({
  String? code,
  Object? cause,
  String? message,
}) {
  var matcher = isA<StorageFailure>();
  if (code != null) {
    matcher = matcher.having((failure) => failure.code, 'code', code);
  }
  if (cause != null) {
    matcher = matcher.having((failure) => failure.cause, 'cause', cause);
  }
  if (message != null) {
    matcher = matcher.having((failure) => failure.message, 'message', message);
  }
  return matcher;
}

/// Simple immutable model used by the local database tests.
@immutable
class Todo {
  const Todo({
    required this.id,
    required this.title,
    this.done = false,
    this.tags = const <String>[],
  });

  factory Todo.fromJson(Map<String, Object?> json) => Todo(
        id: json['id'] as String,
        title: json['title'] as String,
        done: json['done'] as bool? ?? false,
        tags: <String>[
          for (final tag in json['tags'] as List<Object?>? ?? const <Object?>[])
            tag as String,
        ],
      );

  final String id;
  final String title;
  final bool done;
  final List<String> tags;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'done': done,
        'tags': tags,
      };

  @override
  bool operator ==(Object other) =>
      other is Todo &&
      other.id == id &&
      other.title == title &&
      other.done == done &&
      listEquals(other.tags, tags);

  @override
  int get hashCode => Object.hash(id, title, done, Object.hashAll(tags));

  @override
  String toString() => 'Todo($id, $title)';
}

/// Codec of [Todo].
final StorageCodec<Todo> todoCodec = StorageCodec<Todo>.json(
  fromJson: Todo.fromJson,
  toJson: (todo) => todo.toJson(),
);

/// Codec whose encoded maps are not JSON-encodable.
final StorageCodec<Todo> nonJsonTodoCodec = StorageCodec<Todo>.json(
  fromJson: Todo.fromJson,
  toJson: (todo) => <String, Object?>{'id': todo.id, 'at': DateTime(2024)},
);

/// Codec that cannot decode anything.
final StorageCodec<Todo> undecodableTodoCodec = StorageCodec<Todo>.json(
  fromJson: (_) => throw const FormatException('Unsupported payload'),
  toJson: (todo) => todo.toJson(),
);

const Todo milk = Todo(id: '1', title: 'Buy milk');
const Todo bread = Todo(id: '2', title: 'Buy bread', tags: <String>['food']);
const Todo call = Todo(id: '3', title: 'Call mom', done: true);
