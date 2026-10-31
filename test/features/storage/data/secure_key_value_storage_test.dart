import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../helpers/storage_test_helpers.dart';

void main() {
  late MockFlutterSecureStorage plugin;

  setUp(() {
    plugin = MockFlutterSecureStorage();
  });

  test('defaults to a const FlutterSecureStorage without prefix', () {
    const storage = SecureKeyValueStorage();

    expect(storage.storage, isA<FlutterSecureStorage>());
    expect(storage.keyPrefix, isEmpty);
    expect(storage.failureMessage, 'Unable to access the secure storage.');
  });

  group('without key prefix', () {
    late Map<String, String> backend;
    late SecureKeyValueStorage storage;

    setUp(() {
      backend = backWithMap(plugin, <String, String>{'existing': 'value'});
      storage = SecureKeyValueStorage(storage: plugin);
    });

    test('reads, writes, checks and deletes keys unchanged', () async {
      await storage.write('token', 'abc');

      expect(backend['token'], 'abc');
      expect(await storage.read('token'), 'abc');
      expect(await storage.read('missing'), isNull);
      expect(await storage.containsKey('token'), isTrue);
      expect(await storage.containsKey('missing'), isFalse);

      await storage.delete('token');

      expect(backend.containsKey('token'), isFalse);
      verify(() => plugin.write(key: 'token', value: 'abc')).called(1);
      verify(() => plugin.read(key: 'token')).called(1);
      verify(() => plugin.containsKey(key: 'token')).called(1);
      verify(() => plugin.delete(key: 'token')).called(1);
    });

    test('readAll returns every entry as an unmodifiable map', () async {
      await storage.write('other', '2');

      final all = await storage.readAll();

      expect(all, <String, String>{'existing': 'value', 'other': '2'});
      expect(() => all['x'] = 'y', throwsUnsupportedError);
    });

    test('clear deletes everything with deleteAll', () async {
      await storage.clear();

      expect(backend, isEmpty);
      verify(() => plugin.deleteAll()).called(1);
      verifyNever(() => plugin.delete(key: any(named: 'key')));
    });
  });

  group('with key prefix', () {
    late Map<String, String> backend;
    late SecureKeyValueStorage storage;

    setUp(() {
      backend = backWithMap(plugin, <String, String>{
        'app.a': '1',
        'app.b': '2',
        'other.a': '3',
        'plain': '4',
      });
      storage = SecureKeyValueStorage(storage: plugin, keyPrefix: 'app.');
    });

    test('prefixes every key', () async {
      await storage.write('token', 'abc');

      expect(backend['app.token'], 'abc');
      expect(backend.containsKey('token'), isFalse);
      expect(await storage.read('token'), 'abc');
      expect(await storage.read('a'), '1');
      expect(await storage.read('plain'), isNull);
      expect(await storage.containsKey('b'), isTrue);
      expect(await storage.containsKey('plain'), isFalse);

      await storage.delete('a');

      expect(backend.containsKey('app.a'), isFalse);
      verify(() => plugin.write(key: 'app.token', value: 'abc')).called(1);
      verify(() => plugin.delete(key: 'app.a')).called(1);
    });

    test('readAll only returns prefixed entries without the prefix', () async {
      final all = await storage.readAll();

      expect(all, <String, String>{'a': '1', 'b': '2'});
    });

    test('clear only deletes the prefixed entries', () async {
      await storage.clear();

      expect(backend, <String, String>{'other.a': '3', 'plain': '4'});
      verifyNever(() => plugin.deleteAll());
      verify(() => plugin.delete(key: 'app.a')).called(1);
      verify(() => plugin.delete(key: 'app.b')).called(1);
    });
  });

  group('errors', () {
    late SecureKeyValueStorage storage;
    final platformError = PlatformException(code: 'keystore_failure');

    setUp(() {
      storage = SecureKeyValueStorage(storage: plugin, keyPrefix: 'app.');
    });

    test('a synchronous plugin throw becomes a StorageFailure', () async {
      when(() => plugin.read(key: any(named: 'key'))).thenThrow(platformError);

      await expectLater(
        storage.read('token'),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.read,
            cause: same(platformError),
            message: 'Unable to access the secure storage.',
          ).having((f) => f.stackTrace, 'stackTrace', isNotNull),
        ),
      );
    });

    test('an asynchronous plugin error becomes a StorageFailure', () async {
      when(
        () => plugin.write(key: any(named: 'key'), value: any(named: 'value')),
      ).thenAnswer((_) => Future<void>.error(platformError));

      await expectLater(
        storage.write('token', 'abc'),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.write,
            cause: same(platformError),
          ),
        ),
      );
    });

    test('errors (not only exceptions) are wrapped too', () async {
      when(() => plugin.readAll()).thenThrow(UnsupportedError('platform'));
      when(
        () => plugin.containsKey(key: any(named: 'key')),
      ).thenThrow(MissingPluginException());

      await expectLater(
        storage.readAll(),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.read,
            cause: isA<UnsupportedError>(),
          ),
        ),
      );
      await expectLater(
        storage.containsKey('token'),
        throwsA(
          isStorageFailure(
            code: StorageFailureCodes.read,
            cause: isA<MissingPluginException>(),
          ),
        ),
      );
    });

    test('delete and clear failures carry their own codes', () async {
      when(
        () => plugin.delete(key: any(named: 'key')),
      ).thenThrow(platformError);
      when(
        () => plugin.readAll(),
      ).thenAnswer((_) async => <String, String>{'app.a': '1'});
      when(() => plugin.deleteAll()).thenThrow(platformError);

      await expectLater(
        storage.delete('a'),
        throwsA(isStorageFailure(code: StorageFailureCodes.delete)),
      );
      await expectLater(
        storage.clear(),
        throwsA(isStorageFailure(code: StorageFailureCodes.clear)),
      );
      await expectLater(
        SecureKeyValueStorage(storage: plugin).clear(),
        throwsA(isStorageFailure(code: StorageFailureCodes.clear)),
      );
    });

    test('uses the custom failure message', () async {
      when(() => plugin.read(key: any(named: 'key'))).thenThrow(platformError);
      final localized = SecureKeyValueStorage(
        storage: plugin,
        failureMessage: 'Stockage sécurisé indisponible.',
      );

      await expectLater(
        localized.read('token'),
        throwsA(isStorageFailure(message: 'Stockage sécurisé indisponible.')),
      );
    });

    test('failures thrown by the backend are not wrapped twice', () async {
      const failure = StorageFailure('already mapped', code: 'custom');
      when(() => plugin.read(key: any(named: 'key'))).thenThrow(failure);

      await expectLater(storage.read('token'), throwsA(same(failure)));
    });
  });
}
