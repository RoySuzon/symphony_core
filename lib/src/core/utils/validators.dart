import 'package:flutter/widgets.dart';

/// Reusable form field validators.
///
/// Every validator returns `null` when the value is valid and an error message
/// otherwise. Messages are overridable so applications can localize them.
///
/// ```dart
/// SymphonyTextField(
///   validator: SymphonyValidators.compose([
///     SymphonyValidators.required(),
///     SymphonyValidators.email(),
///   ]),
/// );
/// ```
abstract final class SymphonyValidators {
  // Dot-separated parts that are never empty: no leading, trailing or
  // consecutive dot in the local part or in the domain, at least two domain
  // labels and a top-level domain of 2+ characters. Any other non-space
  // character is accepted (internationalized addresses).
  static final RegExp _emailPattern = RegExp(
    r'^[^\s@.]+(?:\.[^\s@.]+)*@(?:[^\s@.]+\.)+[^\s@.]{2,}$',
    caseSensitive: false,
  );

  static final RegExp _phonePattern = RegExp(r'^\+?[0-9 ()\-]{6,20}$');

  static final RegExp _digit = RegExp('[0-9]');

  /// Minimum number of digits of a plausible phone number.
  static const int _minPhoneDigits = 6;

  /// Fails when the value is null, empty or only whitespace.
  static FormFieldValidator<String> required({
    String message = 'This field is required.',
  }) =>
      (value) => value == null || value.trim().isEmpty ? message : null;

  /// Fails when a non-empty value is not a valid e-mail address.
  static FormFieldValidator<String> email({
    String message = 'Enter a valid e-mail address.',
  }) =>
      (value) {
        if (value == null || value.trim().isEmpty) return null;
        return _emailPattern.hasMatch(value.trim()) ? null : message;
      };

  /// Fails when a non-empty value is not a plausible phone number: 6 to 20
  /// characters made of digits, spaces, parentheses and hyphens (optionally
  /// after a leading `+`), at least 6 of them digits.
  static FormFieldValidator<String> phone({
    String message = 'Enter a valid phone number.',
  }) =>
      (value) {
        if (value == null || value.trim().isEmpty) return null;
        final text = value.trim();
        final plausible = _phonePattern.hasMatch(text) &&
            _digit.allMatches(text).length >= _minPhoneDigits;
        return plausible ? null : message;
      };

  /// Fails when a non-empty value is shorter than [length] characters.
  ///
  /// Characters are counted as user-perceived characters (grapheme
  /// clusters), like the `maxLength` counter of text fields: an emoji or a
  /// letter with a combining accent counts as one.
  static FormFieldValidator<String> minLength(int length, {String? message}) =>
      (value) {
        if (value == null || value.isEmpty) return null;
        return value.characters.length < length
            ? (message ?? 'Must be at least $length characters.')
            : null;
      };

  /// Fails when the value is longer than [length] characters.
  ///
  /// Characters are counted as user-perceived characters (grapheme
  /// clusters), like the `maxLength` counter of text fields.
  static FormFieldValidator<String> maxLength(int length, {String? message}) =>
      (value) {
        if (value == null) return null;
        return value.characters.length > length
            ? (message ?? 'Must be at most $length characters.')
            : null;
      };

  /// Fails when a non-empty value does not match [pattern].
  static FormFieldValidator<String> pattern(
    RegExp pattern, {
    String message = 'Invalid format.',
  }) =>
      (value) {
        if (value == null || value.isEmpty) return null;
        return pattern.hasMatch(value) ? null : message;
      };

  /// Fails when a non-empty value is not a finite decimal number.
  ///
  /// Accepted values are exactly those that `double.parse` turns into a
  /// finite number (`42`, `-3.5`, `.5`, `1e3`...); `NaN`, `Infinity` and
  /// hexadecimal literals are rejected.
  static FormFieldValidator<String> numeric({
    String message = 'Enter a valid number.',
  }) =>
      (value) {
        if (value == null || value.trim().isEmpty) return null;
        final number = double.tryParse(value.trim());
        return number == null || !number.isFinite ? message : null;
      };

  /// Fails when the value differs from the one returned by [other] (for
  /// example a password confirmation).
  static FormFieldValidator<String> match(
    String? Function() other, {
    String message = 'Values do not match.',
  }) =>
      (value) => value == other() ? null : message;

  /// Runs [validators] in order and returns the first error.
  static FormFieldValidator<String> compose(
    List<FormFieldValidator<String>> validators,
  ) =>
      (value) {
        for (final validator in validators) {
          final error = validator(value);
          if (error != null) return error;
        }
        return null;
      };
}
