import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

void main() {
  group('SymphonyNullableStringX', () {
    test('isBlank / isNotBlank', () {
      const String? missing = null;

      expect(missing.isBlank, isTrue);
      expect(''.isBlank, isTrue);
      expect(' \t\n'.isBlank, isTrue);
      expect(' '.isBlank, isTrue, reason: 'non-breaking space');
      expect(' a '.isBlank, isFalse);

      expect(missing.isNotBlank, isFalse);
      expect('  '.isNotBlank, isFalse);
      expect('x'.isNotBlank, isTrue);
    });

    test('nullIfBlank keeps non-blank strings unchanged', () {
      const String? missing = null;

      expect(missing.nullIfBlank, isNull);
      expect('   '.nullIfBlank, isNull);
      expect(' value '.nullIfBlank, ' value ');
      expect('   '.nullIfBlank ?? 'fallback', 'fallback');
    });
  });

  group('SymphonyStringX.capitalize', () {
    test('upper-cases the first character only', () {
      expect('hello world'.capitalize(), 'Hello world');
      expect('hELLO'.capitalize(), 'HELLO');
      expect('Already'.capitalize(), 'Already');
      expect('a'.capitalize(), 'A');
      expect(''.capitalize(), '');
      expect('élan'.capitalize(), 'Élan');
      expect('1st'.capitalize(), '1st');
    });

    test('never splits a user-perceived character', () {
      expect('👍🏽 ok'.capitalize(), '👍🏽 ok');
      expect('école'.capitalize(), 'École');
    });
  });

  group('SymphonyStringX.truncate', () {
    test('returns short strings unchanged', () {
      expect('hello'.truncate(5), 'hello');
      expect('hello'.truncate(10), 'hello');
      expect(''.truncate(0), '');
    });

    test('cuts long strings and appends the ellipsis', () {
      expect('Hello wonderful world'.truncate(10), 'Hello won…');
      expect('abcdefgh'.truncate(5), 'abcd…');
      expect('abcdefgh'.truncate(5, ellipsis: '...'), 'ab...');
      expect('abcdefgh'.truncate(4, ellipsis: ''), 'abcd');
    });

    test('removes whitespace before the ellipsis', () {
      expect('Hello world'.truncate(7), 'Hello…');
    });

    test('cuts without ellipsis when max is too small for it', () {
      expect('abcdef'.truncate(1), 'a');
      expect('abcdef'.truncate(2, ellipsis: '...'), 'ab');
      expect('abcdef'.truncate(0), '');
    });

    test('counts user-perceived characters', () {
      expect('👍🏽👍🏽👍🏽'.truncate(3), '👍🏽👍🏽👍🏽');
      expect('👍🏽👍🏽👍🏽👍🏽'.truncate(3), '👍🏽👍🏽…');
      expect('🇫🇷🇩🇪🇮🇹'.truncate(2), '🇫🇷…');
    });

    test('rejects a negative max', () {
      expect(() => 'abc'.truncate(-1), throwsRangeError);
    });
  });
}
