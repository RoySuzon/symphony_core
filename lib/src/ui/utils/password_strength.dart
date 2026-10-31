import 'dart:math' as math;

/// Qualitative strength of a password, from the weakest to the strongest.
enum PasswordStrength {
  /// Easy to guess: too short, common or highly repetitive.
  weak,

  /// Acceptable only for low value accounts.
  fair,

  /// Reasonably hard to guess.
  good,

  /// Long and varied.
  strong;

  /// Whether this level is the same as or stronger than [other].
  bool isAtLeast(PasswordStrength other) => index >= other.index;
}

/// The outcome of [PasswordStrengthEvaluator.evaluate]: a [strength] level
/// and the underlying [score] between 0 and 100.
class PasswordStrengthResult {
  /// Creates a result. [score] must be between 0 and 100.
  const PasswordStrengthResult({required this.strength, required this.score})
      : assert(score >= 0 && score <= 100, 'score must be within 0..100.');

  /// The result of an empty password.
  static const PasswordStrengthResult empty =
      PasswordStrengthResult(strength: PasswordStrength.weak, score: 0);

  /// The qualitative level derived from [score].
  final PasswordStrength strength;

  /// The numeric score, from 0 (weakest) to 100 (strongest).
  final int score;

  /// [score] normalized to `0.0..1.0`, convenient for progress indicators.
  double get fraction => score / 100;

  @override
  bool operator ==(Object other) =>
      other is PasswordStrengthResult &&
      other.strength == strength &&
      other.score == score;

  @override
  int get hashCode => Object.hash(strength, score);

  @override
  String toString() => 'PasswordStrengthResult($strength, score: $score)';
}

/// Estimates how hard a password is to guess.
///
/// The evaluator is pure Dart, deterministic and has no dependencies, so it
/// can be used anywhere (widgets, form validators, tests). The score adds
/// points for length (weighted by character diversity) and for each extra
/// character class (lower case, upper case, digits, symbols), subtracts
/// points for repeated characters (`aaa`), sequences (`abc`, `4321`) and
/// common words, and is capped for passwords shorter than [minLength] or
/// found in [commonPasswords].
///
/// | score    | strength                  |
/// |----------|---------------------------|
/// | 0 - 34   | [PasswordStrength.weak]   |
/// | 35 - 54  | [PasswordStrength.fair]   |
/// | 55 - 74  | [PasswordStrength.good]   |
/// | 75 - 100 | [PasswordStrength.strong] |
///
/// ```dart
/// const evaluator = PasswordStrengthEvaluator();
/// evaluator.evaluate('password').strength; // PasswordStrength.weak
/// evaluator.evaluate('Sunflower7!').strength; // PasswordStrength.good
/// ```
///
/// Subclass it and override [evaluate] to plug in another algorithm.
class PasswordStrengthEvaluator {
  /// Creates an evaluator.
  const PasswordStrengthEvaluator({
    this.minLength = 8,
    this.commonPasswords = defaultCommonPasswords,
  }) : assert(minLength >= 0, 'minLength must be non-negative.');

  /// Passwords (lower case) that are always rated [PasswordStrength.weak],
  /// including their simple variants (`Password1!`, `p@ssw0rd`).
  static const Set<String> defaultCommonPasswords = <String>{
    '000000',
    '111111',
    '121212',
    '123123',
    '123456',
    '1234567',
    '12345678',
    '123456789',
    '1234567890',
    '654321',
    '666666',
    '1q2w3e4r',
    'abc',
    'abc123',
    'admin',
    'administrator',
    'asdfgh',
    'asdfghjkl',
    'baseball',
    'changeme',
    'default',
    'dragon',
    'football',
    'freedom',
    'guest',
    'hello',
    'iloveyou',
    'letmein',
    'login',
    'master',
    'monkey',
    'pass',
    'password',
    'princess',
    'qazwsx',
    'qwerty',
    'qwertyuiop',
    'root',
    'secret',
    'shadow',
    'starwars',
    'sunshine',
    'superman',
    'test',
    'trustno1',
    'user',
    'welcome',
    'whatever',
    'zaq12wsx',
    'zxcvbnm',
  };

  static const int _maxScore = 100;
  static const int _shortPasswordCap = 30;
  static const int _commonPasswordCap = 15;
  static const int _commonWordPenalty = 15;
  static const int _minCommonWordLength = 5;

  static const Map<String, String> _leetSubstitutions = <String, String>{
    '0': 'o',
    '1': 'i',
    '3': 'e',
    '4': 'a',
    '5': 's',
    '7': 't',
    '@': 'a',
    r'$': 's',
    '!': 'i',
  };

  /// Passwords shorter than this (in Unicode code points) are capped to a
  /// weak score.
  final int minLength;

  /// Lower case passwords considered too common to be safe.
  final Set<String> commonPasswords;

  /// Maps a numeric [score] (0..100) to its [PasswordStrength] level.
  static PasswordStrength strengthForScore(int score) {
    if (score >= 75) return PasswordStrength.strong;
    if (score >= 55) return PasswordStrength.good;
    if (score >= 35) return PasswordStrength.fair;
    return PasswordStrength.weak;
  }

  /// Evaluates [password]. An empty password yields
  /// [PasswordStrengthResult.empty].
  PasswordStrengthResult evaluate(String password) {
    if (password.isEmpty) return PasswordStrengthResult.empty;

    final runes = password.runes.toList(growable: false);
    final length = runes.length;
    final distinct = runes.toSet().length;

    // Length, weighted by how many different characters are used so that
    // `aaaaaaaaaaaa` does not score like a random 12 character password.
    final double diversity = math.min(1.0, distinct / math.min(length, 10));
    double score = math.min(length * 3, 75) * diversity;

    // Variety: 12 points for each character class beyond the first.
    score += (_characterClasses(runes) - 1) * 12;

    score -= _repeatPenalty(runes);
    score -= _sequencePenalty(runes);
    if (_containsCommonWord(password.toLowerCase())) {
      score -= _commonWordPenalty;
    }

    var result = math.max(0, math.min(_maxScore, score.round()));
    if (length < minLength) {
      result = math.min(result, _shortPasswordCap);
    }
    if (_isCommon(password.toLowerCase())) {
      result = math.min(result, _commonPasswordCap);
    }
    return PasswordStrengthResult(
      strength: strengthForScore(result),
      score: result,
    );
  }

  static int _characterClasses(List<int> runes) {
    var lower = false;
    var upper = false;
    var digit = false;
    var other = false;
    for (final rune in runes) {
      if (rune >= 0x61 && rune <= 0x7A) {
        lower = true;
      } else if (rune >= 0x41 && rune <= 0x5A) {
        upper = true;
      } else if (rune >= 0x30 && rune <= 0x39) {
        digit = true;
      } else {
        other = true;
      }
    }
    return <bool>[lower, upper, digit, other].where((used) => used).length;
  }

  /// 5 points for every character of a run of 3+ identical characters
  /// beyond the second one.
  static int _repeatPenalty(List<int> runes) {
    var penalty = 0;
    var run = 1;
    for (var i = 1; i <= runes.length; i++) {
      if (i < runes.length && runes[i] == runes[i - 1]) {
        run++;
        continue;
      }
      if (run >= 3) penalty += (run - 2) * 5;
      run = 1;
    }
    return penalty;
  }

  /// 4 points for every character of an ascending or descending sequence of
  /// 3+ characters (`abc`, `CBA`, `789`) beyond the second one.
  static int _sequencePenalty(List<int> runes) {
    final normalized = runes.map(_toLowerAscii).toList(growable: false);
    var penalty = 0;
    var run = 1;
    var step = 0;
    for (var i = 1; i <= normalized.length; i++) {
      final delta =
          i < normalized.length ? normalized[i] - normalized[i - 1] : 0;
      final continues =
          (delta == 1 || delta == -1) && (run == 1 || delta == step);
      if (continues) {
        step = delta;
        run++;
        continue;
      }
      if (run >= 3) penalty += (run - 2) * 4;
      // A broken sequence can start a new one with the current character.
      if (delta == 1 || delta == -1) {
        run = 2;
        step = delta;
      } else {
        run = 1;
        step = 0;
      }
    }
    return penalty;
  }

  static int _toLowerAscii(int rune) =>
      rune >= 0x41 && rune <= 0x5A ? rune + 0x20 : rune;

  bool _isCommon(String lower) {
    final stripped = _stripTrailingNonLetters(lower);
    final candidates = <String>{
      lower,
      _unleet(lower),
      if (stripped.isNotEmpty) stripped,
      if (stripped.isNotEmpty) _unleet(stripped),
    };
    return candidates.any(commonPasswords.contains);
  }

  bool _containsCommonWord(String lower) {
    final normalized = _unleet(lower);
    for (final word in commonPasswords) {
      if (word.length < _minCommonWordLength) continue;
      if (lower.contains(word) || normalized.contains(word)) return true;
    }
    return false;
  }

  static String _stripTrailingNonLetters(String value) {
    var end = value.length;
    while (end > 0) {
      final unit = value.codeUnitAt(end - 1);
      final isLetter = unit >= 0x61 && unit <= 0x7A;
      if (isLetter) break;
      end--;
    }
    return value.substring(0, end);
  }

  static String _unleet(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_leetSubstitutions[char] ?? char);
    }
    return buffer.toString();
  }
}
