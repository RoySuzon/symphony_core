import 'package:flutter/widgets.dart' show FormFieldValidator;
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

void main() {
  group('SymphonyValidators.required', () {
    final validator = SymphonyValidators.required();

    test('fails for null, empty and blank values', () {
      expect(validator(null), 'This field is required.');
      expect(validator(''), 'This field is required.');
      expect(validator('   '), 'This field is required.');
    });

    test('accepts non-blank values and uses custom messages', () {
      expect(validator(' a '), isNull);
      expect(SymphonyValidators.required(message: 'Requis')(null), 'Requis');
    });
  });

  group('SymphonyValidators.email', () {
    final validator = SymphonyValidators.email();

    test('accepts valid addresses and empty values', () {
      for (final value in <String?>[
        null,
        '',
        '  ',
        'ada@example.com',
        ' ada.lovelace+test@sub.example.org ',
        'UPPER@EXAMPLE.COM',
      ]) {
        expect(validator(value), isNull, reason: '$value');
      }
    });

    test('rejects invalid addresses', () {
      for (final value in <String>[
        'ada',
        'ada@',
        '@example.com',
        'ada@example',
        'ada@example.c',
        'ada @example.com',
        'ada@@example.com',
      ]) {
        expect(
          validator(value),
          'Enter a valid e-mail address.',
          reason: value,
        );
      }
      expect(SymphonyValidators.email(message: 'Bad')('x'), 'Bad');
    });

    test('rejects misplaced dots', () {
      for (final value in <String>[
        '.ada@example.com',
        'ada.@example.com',
        'ada..lovelace@example.com',
        'ada@.example.com',
        'ada@example..com',
        'ada@example.com.',
      ]) {
        expect(
          validator(value),
          'Enter a valid e-mail address.',
          reason: value,
        );
      }
    });

    test('accepts internationalized addresses', () {
      for (final value in <String>[
        'ada.lovelace@sub.domain.example.co.uk',
        'José.Pérez@correo.example.es',
        'গৌতম@উদাহরণ.বাংলা',
      ]) {
        expect(validator(value), isNull, reason: value);
      }
    });
  });

  group('SymphonyValidators.phone', () {
    final validator = SymphonyValidators.phone();

    test('accepts plausible numbers and empty values', () {
      for (final value in <String?>[
        null,
        '',
        '+33 6 12 34 56 78',
        '(555) 123-4567',
        '0612345678',
      ]) {
        expect(validator(value), isNull, reason: '$value');
      }
    });

    test('rejects implausible numbers', () {
      for (final value in <String>['12345', 'phone', '+33 6 12 AB', '1' * 21]) {
        expect(validator(value), 'Enter a valid phone number.', reason: value);
      }
      expect(SymphonyValidators.phone(message: 'Bad')('x'), 'Bad');
    });

    test('rejects values made of formatting characters only', () {
      for (final value in <String>[
        '((((((',
        '------',
        '()()()',
        '+ - ( )',
        '(1) - -',
        '12 - 345',
      ]) {
        expect(validator(value), 'Enter a valid phone number.', reason: value);
      }
      expect(validator('123456'), isNull);
      expect(validator('+1 (2) 3-4 5 6'), isNull);
    });
  });

  group('SymphonyValidators.minLength / maxLength', () {
    test('minLength ignores empty values and checks the length', () {
      final validator = SymphonyValidators.minLength(3);

      expect(validator(null), isNull);
      expect(validator(''), isNull);
      expect(validator('ab'), 'Must be at least 3 characters.');
      expect(validator('abc'), isNull);
      expect(
        SymphonyValidators.minLength(8, message: 'Too short')('abc'),
        'Too short',
      );
    });

    test('maxLength checks the length', () {
      final validator = SymphonyValidators.maxLength(3);

      expect(validator(null), isNull);
      expect(validator(''), isNull);
      expect(validator('abc'), isNull);
      expect(validator('abcd'), 'Must be at most 3 characters.');
      expect(
        SymphonyValidators.maxLength(1, message: 'Too long')('ab'),
        'Too long',
      );
    });

    test('count user-perceived characters, like TextField.maxLength', () {
      // One character each, made of several UTF-16 code units (grapheme
      // cluster rules that are stable across Unicode versions).
      const emoji = '😀'; // surrogate pair
      const thumbsUp = '👍🏽'; // emoji + skin tone modifier
      const flag = '🇧🇩'; // two regional indicators
      const combining = 'é'; // e + combining acute accent
      const bengali = 'কি'; // consonant + dependent vowel sign

      for (final character in <String>[
        emoji,
        thumbsUp,
        flag,
        combining,
        bengali,
      ]) {
        expect(
          SymphonyValidators.maxLength(1)(character),
          isNull,
          reason: '$character (${character.length} code units)',
        );
        expect(
          SymphonyValidators.minLength(2)(character),
          'Must be at least 2 characters.',
          reason: character,
        );
      }
      expect(
        SymphonyValidators.maxLength(2)('$emoji$flag$combining'),
        'Must be at most 2 characters.',
      );
      expect(SymphonyValidators.minLength(2)('$emoji$thumbsUp'), isNull);
    });
  });

  group('SymphonyValidators.pattern', () {
    final validator = SymphonyValidators.pattern(RegExp(r'^[A-Z]{3}$'));

    test('validates non-empty values against the pattern', () {
      expect(validator(null), isNull);
      expect(validator(''), isNull);
      expect(validator('ABC'), isNull);
      expect(validator('abc'), 'Invalid format.');
      expect(
        SymphonyValidators.pattern(RegExp(r'^\d+$'), message: 'Digits')('x'),
        'Digits',
      );
    });
  });

  group('SymphonyValidators.numeric', () {
    final validator = SymphonyValidators.numeric();

    test('accepts numbers and empty values', () {
      for (final value in <String?>[null, '', ' ', '42', '-3.5', ' 1e3 ']) {
        expect(validator(value), isNull, reason: '$value');
      }
    });

    test('rejects other values', () {
      expect(validator('abc'), 'Enter a valid number.');
      expect(validator('1,5'), 'Enter a valid number.');
      expect(SymphonyValidators.numeric(message: 'NaN')('x'), 'NaN');
    });

    test('accepts only finite decimal numbers that double.parse accepts', () {
      // NaN / Infinity cannot be JSON encoded; hexadecimal literals are
      // rejected by double.parse.
      for (final value in <String>[
        'NaN',
        '-NaN',
        'Infinity',
        '-Infinity',
        '0x1F',
      ]) {
        expect(validator(value), 'Enter a valid number.', reason: value);
      }
      for (final value in <String>['+5', '.5', '5.', '-0', '1E-3', '12']) {
        expect(validator(value), isNull, reason: value);
        expect(double.tryParse(value.trim()), isNotNull, reason: value);
      }
    });
  });

  group('SymphonyValidators.match', () {
    test('compares with the current value of the other field', () {
      var password = 'secret';
      final validator = SymphonyValidators.match(() => password);

      expect(validator('secret'), isNull);
      expect(validator('other'), 'Values do not match.');

      password = 'other';
      expect(validator('other'), isNull);
      expect(
        SymphonyValidators.match(() => 'a', message: 'Mismatch')('b'),
        'Mismatch',
      );
    });
  });

  group('SymphonyValidators.compose', () {
    test('returns the first error in order', () {
      final validator = SymphonyValidators.compose(<FormFieldValidator<String>>[
        SymphonyValidators.required(message: 'required'),
        SymphonyValidators.email(message: 'email'),
        SymphonyValidators.maxLength(10, message: 'length'),
      ]);

      expect(validator(''), 'required');
      expect(validator('nope'), 'email');
      expect(validator('ada@example.com'), 'length');
      expect(validator('a@b.co'), isNull);
    });

    test('an empty composition accepts everything', () {
      expect(SymphonyValidators.compose(const [])(null), isNull);
    });
  });
}
