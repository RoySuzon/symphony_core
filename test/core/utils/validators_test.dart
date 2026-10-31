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
        expect(validator(value), 'Enter a valid e-mail address.',
            reason: value);
      }
      expect(SymphonyValidators.email(message: 'Bad')('x'), 'Bad');
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
