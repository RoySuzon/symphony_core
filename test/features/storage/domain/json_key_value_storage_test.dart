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

  group('readJson / writeJson', () {
    test('round trips a JSON object', () async {
      final value = <String, Object?>{
        'name': 'Ada',
        'age': 36,
        'ratio': 0.5,
        'admin': true,
        'nickname': null,
        'roles': <Object?>['admin', 'editor'],
        'address': <String, Object?>{'city': 'London'},
      };

      await storage.writeJson('profile', value);

      expect(await storage.read('profile'), jsonEncode(value));
      expect(await storage.readJson('profile'), value);
    });

    test('returns null for a missing or empty value', () async {
      await storage.write('empty', '');

      expect(await storage.readJson('missing'), isNull);
      expect(await storage.readJson('empty'), isNull);
    });

    test('returns null for corrupted JSON and leaves it untouched', () async {
      await storage.write('profile', '{"name": "Ada"');

      expect(await storage.readJson('profile'), isNull);
      expect(await storage.read('profile'), '{"name": "Ada"');
    });

    test('returns null when the value is not a JSON object', () async {
      await storage.write('list', '[1, 2]');
      await storage.write('number', '42');

      expect(await storage.readJson('list'), isNull);
      expect(await storage.readJson('number'), isNull);
    });

    test('throws an encode StorageFailure for unsupported values', () async {
      await expectLater(
        storage.writeJson('profile', <String, Object?>{'at': DateTime(2024)}),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.encode,
            cause: isA<JsonUnsupportedObjectError>(),
          ),
        ),
      );
      expect(await storage.containsKey('profile'), isFalse);
    });
  });

  group('readJsonList / writeJsonList', () {
    test('round trips a JSON array', () async {
      final value = <Object?>[
        'flutter',
        1,
        null,
        <String, Object?>{'id': 1},
        <Object?>[true],
      ];

      await storage.writeJsonList('items', value);

      expect(await storage.readJsonList('items'), value);
    });

    test('returns null for missing, corrupted or non-array values', () async {
      await storage.write('corrupted', '[1, 2');
      await storage.write('object', '{"a": 1}');

      expect(await storage.readJsonList('missing'), isNull);
      expect(await storage.readJsonList('corrupted'), isNull);
      expect(await storage.readJsonList('object'), isNull);
    });

    test('throws an encode StorageFailure for unsupported values', () async {
      await expectLater(
        storage.writeJsonList('items', <Object?>[Object()]),
        throwsA(isStorageFailure(code: StorageFailureCodes.encode)),
      );
      expect(await storage.containsKey('items'), isFalse);
    });
  });

  test('backend failures are propagated', () async {
    final failing = MockKeyValueStorage();
    const failure = StorageFailure('boom', code: StorageFailureCodes.read);
    when(
      () => failing.read(any()),
    ).thenAnswer((_) => Future<String?>.error(failure));

    await expectLater(failing.readJson('key'), throwsA(same(failure)));
    await expectLater(failing.readJsonList('key'), throwsA(same(failure)));
  });
}
