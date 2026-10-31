import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

import '../helpers/storage_test_helpers.dart';

void main() {
  late InMemoryKeyValueStorage inner;
  late PrefixedKeyValueStorage storage;

  setUp(() {
    inner = InMemoryKeyValueStorage(<String, String>{
      'user.name': 'Ada',
      'user.theme': 'dark',
      'app.version': '1',
    });
    storage = PrefixedKeyValueStorage(inner, 'user.');
  });

  test('exposes the decorated storage and prefix', () {
    expect(storage.inner, same(inner));
    expect(storage.prefix, 'user.');
  });

  test('reads, writes, checks and deletes prefixed keys', () async {
    await storage.write('locale', 'fr');

    expect(await inner.read('user.locale'), 'fr');
    expect(await inner.containsKey('locale'), isFalse);
    expect(await storage.read('locale'), 'fr');
    expect(await storage.read('name'), 'Ada');
    expect(await storage.read('version'), isNull);
    expect(await storage.containsKey('theme'), isTrue);
    expect(await storage.containsKey('app.version'), isFalse);

    await storage.delete('name');

    expect(await inner.containsKey('user.name'), isFalse);
  });

  test('readAll only returns the prefixed entries without prefix', () async {
    final all = await storage.readAll();

    expect(all, <String, String>{'name': 'Ada', 'theme': 'dark'});
    expect(() => all['x'] = 'y', throwsUnsupportedError);
  });

  test('clear only removes the prefixed entries', () async {
    await storage.clear();

    expect(await storage.readAll(), isEmpty);
    expect(await inner.readAll(), <String, String>{'app.version': '1'});
  });

  test('an empty prefix is a transparent pass-through', () async {
    final passThrough = PrefixedKeyValueStorage(inner, '');

    expect(await passThrough.read('app.version'), '1');
    expect(await passThrough.readAll(), await inner.readAll());

    await passThrough.clear();

    expect(await inner.readAll(), isEmpty);
  });

  test('prefixes can be nested', () async {
    final nested = PrefixedKeyValueStorage(storage, 'settings.');

    await nested.write('font', 'large');

    expect(await inner.read('user.settings.font'), 'large');
    expect(await nested.readAll(), <String, String>{'font': 'large'});
    expect(await storage.readAll(), containsPair('settings.font', 'large'));

    await nested.clear();

    expect(await storage.readAll(), <String, String>{
      'name': 'Ada',
      'theme': 'dark',
    });
  });

  test('propagates the errors of the decorated storage unchanged', () async {
    final failing = MockKeyValueStorage();
    const failure = StorageFailure('boom', code: StorageFailureCodes.read);
    when(() => failing.read(any())).thenAnswer(
      (_) => Future<String?>.error(failure),
    );

    await expectLater(
      PrefixedKeyValueStorage(failing, 'p.').read('key'),
      throwsA(same(failure)),
    );
    verify(() => failing.read('p.key')).called(1);
  });
}
