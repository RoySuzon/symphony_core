import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

void main() {
  final json = jsonDecode('''
{
  "data": {
    "user": {"name": "Ada", "age": 36, "roles": ["admin", "editor", 7]},
    "items": [{"id": 1}, {"id": 2, "tags": ["a", "b"]}],
    "empty": null
  },
  "meta.version": "2"
}
''');

  group('JsonReader.readPath', () {
    test('follows map keys and list indices', () {
      expect(JsonReader.readPath(json, 'data.user.name'), 'Ada');
      expect(JsonReader.readPath(json, 'data.items.0.id'), 1);
      expect(JsonReader.readPath(json, 'data.items.1.tags.1'), 'b');
      expect(JsonReader.readPath(json, 'data.user.roles'), hasLength(3));
    });

    test('an empty path returns the input', () {
      expect(JsonReader.readPath(json, ''), same(json));
      expect(JsonReader.readPath(42, ''), 42);
    });

    test('returns null when the path cannot be followed', () {
      for (final path in <String>[
        'missing',
        'data.user.missing',
        'data.items.5.id',
        'data.items.-1',
        'data.items.first',
        'data.user.name.length',
        'data.empty.anything',
        'data..user',
        'meta.version',
      ]) {
        expect(JsonReader.readPath(json, path), isNull, reason: path);
      }
      expect(JsonReader.readPath(null, 'a'), isNull);
      expect(JsonReader.readPath('text', 'a'), isNull);
    });

    test('matches integer keys of non-JSON maps', () {
      final map = <Object, Object?>{
        1: 'one',
        'list': <Object?>[
          <int, String>{0: 'zero'},
        ],
      };

      expect(JsonReader.readPath(map, '1'), 'one');
      expect(JsonReader.readPath(map, 'list.0.0'), 'zero');
    });
  });

  group('JsonReader.readSegments', () {
    test('addresses keys containing dots and accepts int indices', () {
      expect(JsonReader.readSegments(json, <Object>['meta.version']), '2');
      expect(
        JsonReader.readSegments(json, <Object>['data', 'items', 1, 'id']),
        2,
      );
      expect(JsonReader.readSegments(json, const <Object>[]), same(json));
      expect(JsonReader.readSegments(json, <Object>['data', 9]), isNull);
    });

    test('converts non-string segments to match string keys', () {
      final map = <String, Object?>{'7': 'seven'};

      expect(JsonReader.readSegments(map, <Object>[7]), 'seven');
    });
  });

  group('JsonReader.asString', () {
    test('converts scalars and rejects other values', () {
      expect(JsonReader.asString('a'), 'a');
      expect(JsonReader.asString(''), '');
      expect(JsonReader.asString(3), '3');
      expect(JsonReader.asString(2.5), '2.5');
      expect(JsonReader.asString(true), 'true');
      expect(JsonReader.asString(null), isNull);
      expect(JsonReader.asString(<Object?>[]), isNull);
      expect(JsonReader.asString(<String, Object?>{}), isNull);
    });
  });

  group('JsonReader.asInt', () {
    test('accepts lossless conversions', () {
      expect(JsonReader.asInt(3), 3);
      expect(JsonReader.asInt(-3), -3);
      expect(JsonReader.asInt(3.0), 3);
      expect(JsonReader.asInt(' 42 '), 42);
      expect(JsonReader.asInt('42.0'), 42);
      expect(JsonReader.asInt('-7'), -7);
    });

    test('rejects lossy or invalid values', () {
      expect(JsonReader.asInt(3.5), isNull);
      expect(JsonReader.asInt('3.5'), isNull);
      expect(JsonReader.asInt(double.nan), isNull);
      expect(JsonReader.asInt(double.infinity), isNull);
      expect(JsonReader.asInt(1e300), isNull);
      expect(JsonReader.asInt('abc'), isNull);
      expect(JsonReader.asInt(''), isNull);
      expect(JsonReader.asInt(true), isNull);
      expect(JsonReader.asInt(null), isNull);
      expect(JsonReader.asInt(<Object?>[1]), isNull);
    });

    test('reads strings as decimal numbers only, like asDouble', () {
      // int.parse accepts Dart hexadecimal literals, double.parse does not.
      for (final value in <String>['0x1F', '-0x1F', '+0X10', ' 0xff ']) {
        expect(JsonReader.asInt(value), isNull, reason: value);
        expect(JsonReader.asDouble(value), isNull, reason: value);
        expect(JsonReader.asDateTime(value), isNull, reason: value);
      }
      expect(JsonReader.asInt('+42'), 42);
      expect(JsonReader.asInt('0042'), 42);
    });
  });

  group('JsonReader.asDouble', () {
    test('accepts numbers and numeric strings', () {
      expect(JsonReader.asDouble(2), 2.0);
      expect(JsonReader.asDouble(2.5), 2.5);
      expect(JsonReader.asDouble(' 2.5 '), 2.5);
      expect(JsonReader.asDouble('-1e3'), -1000.0);
    });

    test('rejects non-finite and invalid values', () {
      expect(JsonReader.asDouble(double.nan), isNull);
      expect(JsonReader.asDouble('NaN'), isNull);
      expect(JsonReader.asDouble('Infinity'), isNull);
      expect(JsonReader.asDouble('1,5'), isNull);
      expect(JsonReader.asDouble(false), isNull);
      expect(JsonReader.asDouble(null), isNull);
    });
  });

  group('JsonReader.asBool', () {
    test('accepts booleans, 0/1 and common words', () {
      expect(JsonReader.asBool(true), isTrue);
      expect(JsonReader.asBool(false), isFalse);
      expect(JsonReader.asBool(1), isTrue);
      expect(JsonReader.asBool(0), isFalse);
      expect(JsonReader.asBool(1.0), isTrue);
      for (final value in <String>['true', 'TRUE', ' yes ', '1', 'On']) {
        expect(JsonReader.asBool(value), isTrue, reason: value);
      }
      for (final value in <String>['false', 'False', 'no', '0', 'OFF']) {
        expect(JsonReader.asBool(value), isFalse, reason: value);
      }
    });

    test('rejects other values', () {
      expect(JsonReader.asBool(2), isNull);
      expect(JsonReader.asBool('maybe'), isNull);
      expect(JsonReader.asBool(''), isNull);
      expect(JsonReader.asBool(null), isNull);
      expect(JsonReader.asBool(<Object?>[]), isNull);
    });
  });

  group('JsonReader.asDateTime', () {
    final instant = DateTime.utc(2023, 11, 14, 22, 13, 20);
    const seconds = 1700000000;

    test('parses ISO-8601 strings', () {
      expect(
        JsonReader.asDateTime('2023-11-14T22:13:20Z'),
        instant,
      );
      expect(JsonReader.asDateTime('2023-11-14T22:13:20Z')!.isUtc, isTrue);
      expect(
        JsonReader.asDateTime('2024-05-01'),
        DateTime(2024, 5),
      );
      expect(JsonReader.asDateTime('20240501'), DateTime(2024, 5));
      expect(
        JsonReader.asDateTime('2023-11-14T23:13:20+01:00'),
        instant,
      );
    });

    test('accepts DateTime instances', () {
      final now = DateTime.now();

      expect(JsonReader.asDateTime(now), same(now));
    });

    test('infers the unit of epoch timestamps', () {
      expect(JsonReader.asDateTime(seconds), instant.toLocal());
      expect(JsonReader.asDateTime(seconds * 1000), instant.toLocal());
      expect(JsonReader.asDateTime(seconds * 1000000), instant.toLocal());
      expect(JsonReader.asDateTime('$seconds'), instant.toLocal());
      expect(JsonReader.asDateTime(' ${seconds * 1000} '), instant.toLocal());
      expect(
        JsonReader.asDateTime(seconds + 0.5),
        instant.add(const Duration(milliseconds: 500)).toLocal(),
      );
      expect(
          JsonReader.asDateTime(-86400), DateTime.utc(1969, 12, 31).toLocal());
    });

    test('isUtc returns UTC values', () {
      final fromEpoch = JsonReader.asDateTime(seconds, isUtc: true);
      final fromOffset = JsonReader.asDateTime(
        '2023-11-14T23:13:20+01:00',
        isUtc: true,
      );
      final fromLocal = JsonReader.asDateTime(
        DateTime(2024),
        isUtc: true,
      );

      expect(fromEpoch, instant);
      expect(fromEpoch!.isUtc, isTrue);
      expect(fromOffset!.isUtc, isTrue);
      expect(fromLocal!.isUtc, isTrue);
      expect(fromLocal, DateTime(2024).toUtc());
    });

    test('rejects invalid values instead of throwing', () {
      expect(JsonReader.asDateTime('not a date'), isNull);
      expect(JsonReader.asDateTime(''), isNull);
      expect(JsonReader.asDateTime(double.nan), isNull);
      expect(JsonReader.asDateTime(9e18), isNull, reason: 'out of range');
      expect(JsonReader.asDateTime(true), isNull);
      expect(JsonReader.asDateTime(null), isNull);
      expect(JsonReader.asDateTime(<Object?>[]), isNull);
    });
  });

  group('JsonReader.asMap', () {
    test('returns string-keyed maps as they are', () {
      final map = <String, Object?>{'a': 1};

      expect(JsonReader.asMap(map), same(map));
      expect(
        JsonReader.asMap(JsonReader.readPath(json, 'data.user')),
        containsPair('name', 'Ada'),
      );
    });

    test('copies other maps with string keys', () {
      expect(
        JsonReader.asMap(<Object?, Object?>{1: 'one', null: 'nothing'}),
        <String, Object?>{'1': 'one', 'null': 'nothing'},
      );
    });

    test('rejects non-maps', () {
      expect(JsonReader.asMap(<Object?>[]), isNull);
      expect(JsonReader.asMap('{"a": 1}'), isNull);
      expect(JsonReader.asMap(null), isNull);
    });
  });

  group('JsonReader.asList / asListOf', () {
    test('asList returns lists and copies other iterables', () {
      final list = <Object?>[1, 'two'];

      expect(JsonReader.asList(list), same(list));
      expect(JsonReader.asList(<int>{1, 2}), <Object?>[1, 2]);
      expect(JsonReader.asList('abc'), isNull);
      expect(JsonReader.asList(<String, Object?>{}), isNull);
      expect(JsonReader.asList(null), isNull);
    });

    test('asListOf converts elements and drops failures', () {
      expect(
        JsonReader.asListOf<int>(
            <Object?>[1, '2', 3.0, 'x', null, 4.5], JsonReader.asInt),
        <int>[1, 2, 3],
      );
      expect(
        JsonReader.asListOf<Map<String, Object?>>(
          JsonReader.readPath(json, 'data.items'),
          JsonReader.asMap,
        ),
        hasLength(2),
      );
      expect(JsonReader.asListOf<int>('nope', JsonReader.asInt), isNull);
    });
  });

  group('JsonReader.asStringSet', () {
    test('converts iterables element by element', () {
      expect(
        JsonReader.asStringSet(JsonReader.readPath(json, 'data.user.roles')),
        <String>{'admin', 'editor', '7'},
      );
      expect(
        JsonReader.asStringSet(<Object?>['a', null, <Object?>[], 'a']),
        <String>{'a'},
      );
    });

    test('turns a single string into a one-element set', () {
      expect(JsonReader.asStringSet(' admin '), <String>{'admin'});
      expect(JsonReader.asStringSet('  '), isEmpty);
    });

    test('rejects other values', () {
      expect(JsonReader.asStringSet(42), isNull);
      expect(JsonReader.asStringSet(null), isNull);
      expect(JsonReader.asStringSet(<String, Object?>{}), isNull);
    });
  });
}
