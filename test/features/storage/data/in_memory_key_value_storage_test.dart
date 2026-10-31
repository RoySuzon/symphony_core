import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/storage/storage.dart';

void main() {
  group('InMemoryKeyValueStorage', () {
    test('starts with a copy of the initial values', () async {
      final initial = <String, String>{'a': '1'};
      final storage = InMemoryKeyValueStorage(initial);
      initial['b'] = '2';

      expect(await storage.readAll(), <String, String>{'a': '1'});
      expect(await InMemoryKeyValueStorage().readAll(), isEmpty);
    });

    test('reads, writes, checks and deletes values', () async {
      final storage = InMemoryKeyValueStorage();

      await storage.write('key', 'value');
      expect(await storage.read('key'), 'value');
      expect(await storage.containsKey('key'), isTrue);

      await storage.write('key', 'updated');
      expect(await storage.read('key'), 'updated');

      await storage.delete('key');
      await storage.delete('missing');
      expect(await storage.read('key'), isNull);
      expect(await storage.containsKey('key'), isFalse);
    });

    test('readAll returns an unmodifiable snapshot', () async {
      final storage = InMemoryKeyValueStorage(<String, String>{'a': '1'});

      final snapshot = await storage.readAll();
      await storage.write('b', '2');

      expect(snapshot, <String, String>{'a': '1'});
      expect(() => snapshot['c'] = '3', throwsUnsupportedError);
      expect(await storage.readAll(), <String, String>{'a': '1', 'b': '2'});
    });

    test('clear removes every value', () async {
      final storage = InMemoryKeyValueStorage(
        <String, String>{'a': '1', 'b': '2'},
      );

      await storage.clear();

      expect(await storage.readAll(), isEmpty);
    });
  });
}
