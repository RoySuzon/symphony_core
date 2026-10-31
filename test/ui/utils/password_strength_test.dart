import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

void main() {
  const evaluator = PasswordStrengthEvaluator();

  PasswordStrength strengthOf(String password) =>
      evaluator.evaluate(password).strength;

  group('PasswordStrengthEvaluator', () {
    test('rates an empty password as empty', () {
      expect(evaluator.evaluate(''), PasswordStrengthResult.empty);
      expect(PasswordStrengthResult.empty.score, 0);
      expect(PasswordStrengthResult.empty.strength, PasswordStrength.weak);
    });

    test('rates short, repetitive and sequential passwords as weak', () {
      expect(strengthOf('a'), PasswordStrength.weak);
      expect(strengthOf('abc'), PasswordStrength.weak);
      expect(strengthOf('aaaaaaaaaaaa'), PasswordStrength.weak);
      expect(strengthOf('abcdefgh'), PasswordStrength.weak);
      expect(strengthOf('abababababababab'), PasswordStrength.weak);
      expect(strengthOf('zebracat'), PasswordStrength.weak);
    });

    test('rates common passwords and their variants as weak', () {
      for (final password in <String>[
        'password',
        'Password1!',
        'P@ssw0rd!',
        'qwerty',
        '123456789',
        'Hello123!',
        'letmein2024',
      ]) {
        final result = evaluator.evaluate(password);
        expect(result.strength, PasswordStrength.weak, reason: password);
        expect(result.score, lessThanOrEqualTo(15), reason: password);
      }
    });

    test('rates each level', () {
      expect(strengthOf('Zebracat9'), PasswordStrength.fair);
      expect(strengthOf('Abcd1234!'), PasswordStrength.fair);
      expect(strengthOf('Zebra-cat9'), PasswordStrength.good);
      expect(strengthOf('Sunflower7!'), PasswordStrength.good);
      expect(strengthOf('Zebra-cat9-Moon'), PasswordStrength.strong);
      expect(strengthOf(r'Xk9#mP2$vL7!qR4&'), PasswordStrength.strong);
      expect(
        strengthOf('correct horse battery staple'),
        PasswordStrength.strong,
      );
    });

    test('is deterministic and produces scores within 0..100', () {
      for (final password in <String>[
        'x',
        'Zebra-cat9',
        r'Xk9#mP2$vL7!qR4&Xk9#mP2$vL7!qR4&',
        'ü§¶‍♂️ émoji pässwörd 🚀',
      ]) {
        final first = evaluator.evaluate(password);
        final second = evaluator.evaluate(password);
        expect(first, second);
        expect(first.score, inInclusiveRange(0, 100));
        expect(first.fraction, inInclusiveRange(0.0, 1.0));
      }
    });

    test('longer and more varied passwords never score lower', () {
      final base = evaluator.evaluate('Zebracat').score;
      expect(evaluator.evaluate('Zebracat9').score, greaterThan(base));
      expect(
        evaluator.evaluate('Zebra-cat9').score,
        greaterThan(evaluator.evaluate('Zebracat9').score),
      );
    });

    test('caps passwords shorter than minLength', () {
      const strict = PasswordStrengthEvaluator(minLength: 20);
      final result = strict.evaluate(r'Xk9#mP2$vL7!qR4&');

      expect(result.score, lessThanOrEqualTo(30));
      expect(result.strength, PasswordStrength.weak);
    });

    test('supports a custom list of common passwords', () {
      const custom = PasswordStrengthEvaluator(
        commonPasswords: <String>{'symphony'},
      );

      expect(custom.evaluate('Symphony2024!').strength, PasswordStrength.weak);
      expect(
        custom.evaluate('password').strength,
        isNot(PasswordStrength.good),
      );
    });

    test('strengthForScore maps the score thresholds', () {
      expect(
        PasswordStrengthEvaluator.strengthForScore(0),
        PasswordStrength.weak,
      );
      expect(
        PasswordStrengthEvaluator.strengthForScore(34),
        PasswordStrength.weak,
      );
      expect(
        PasswordStrengthEvaluator.strengthForScore(35),
        PasswordStrength.fair,
      );
      expect(
        PasswordStrengthEvaluator.strengthForScore(55),
        PasswordStrength.good,
      );
      expect(
        PasswordStrengthEvaluator.strengthForScore(75),
        PasswordStrength.strong,
      );
      expect(
        PasswordStrengthEvaluator.strengthForScore(100),
        PasswordStrength.strong,
      );
    });
  });

  group('PasswordStrength', () {
    test('isAtLeast compares levels', () {
      expect(PasswordStrength.good.isAtLeast(PasswordStrength.fair), isTrue);
      expect(PasswordStrength.good.isAtLeast(PasswordStrength.good), isTrue);
      expect(PasswordStrength.fair.isAtLeast(PasswordStrength.strong), isFalse);
    });
  });

  group('PasswordStrengthResult', () {
    test('implements value equality and exposes a fraction', () {
      const a = PasswordStrengthResult(
        strength: PasswordStrength.good,
        score: 60,
      );
      const b = PasswordStrengthResult(
        strength: PasswordStrength.good,
        score: 60,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.fraction, 0.6);
      expect(a.toString(), contains('60'));
    });
  });
}
