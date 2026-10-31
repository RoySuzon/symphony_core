import 'package:flutter/widgets.dart' show StringCharacters;

/// Blank checks for optional strings.
///
/// ```dart
/// String? name = '  ';
/// name.isBlank;              // true
/// name.nullIfBlank ?? 'Anonymous'; // 'Anonymous'
/// ```
extension SymphonyNullableStringX on String? {
  /// Whether this string is `null`, empty or contains only whitespace.
  bool get isBlank {
    final value = this;
    return value == null || value.trim().isEmpty;
  }

  /// Whether this string contains at least one non-whitespace character.
  bool get isNotBlank => !isBlank;

  /// This string unchanged, or `null` when it [isBlank].
  String? get nullIfBlank => isBlank ? null : this;
}

/// Display helpers for strings.
///
/// Lengths are measured in user-perceived characters (grapheme clusters), so
/// emoji, flags and combining marks are never split.
extension SymphonyStringX on String {
  /// Returns this string with its first character in upper case; the rest is
  /// left unchanged (`'hello world'` → `'Hello world'`).
  String capitalize() {
    if (isEmpty) return this;
    final chars = characters;
    return '${chars.first.toUpperCase()}${chars.skip(1)}';
  }

  /// Shortens this string to at most [max] characters.
  ///
  /// Strings of at most [max] characters are returned unchanged. Longer ones
  /// are cut and end with [ellipsis] (whitespace before the ellipsis is
  /// removed), so the result never exceeds [max] characters. When [max] is
  /// not larger than the ellipsis itself, the string is cut to [max]
  /// characters without an ellipsis.
  ///
  /// ```dart
  /// 'Hello wonderful world'.truncate(10); // 'Hello won…'
  /// ```
  ///
  /// Throws a [RangeError] when [max] is negative.
  String truncate(int max, {String ellipsis = '…'}) {
    RangeError.checkNotNegative(max, 'max');
    final chars = characters;
    if (chars.length <= max) return this;
    final ellipsisLength = ellipsis.characters.length;
    if (ellipsisLength >= max) return chars.take(max).toString();
    final kept = chars.take(max - ellipsisLength).toString().trimRight();
    return '$kept$ellipsis';
  }
}
