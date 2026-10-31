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
  static final RegExp _emailPattern =
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$', caseSensitive: false);

  static final RegExp _phonePattern = RegExp(r'^\+?[0-9 ()\-]{6,20}$');

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

  /// Fails when a non-empty value is not a plausible phone number.
  static FormFieldValidator<String> phone({
    String message = 'Enter a valid phone number.',
  }) =>
      (value) {
        if (value == null || value.trim().isEmpty) return null;
        return _phonePattern.hasMatch(value.trim()) ? null : message;
      };

  /// Fails when a non-empty value is shorter than [length] characters.
  static FormFieldValidator<String> minLength(int length, {String? message}) =>
      (value) {
        if (value == null || value.isEmpty) return null;
        return value.length < length
            ? (message ?? 'Must be at least $length characters.')
            : null;
      };

  /// Fails when the value is longer than [length] characters.
  static FormFieldValidator<String> maxLength(int length, {String? message}) =>
      (value) {
        if (value == null) return null;
        return value.length > length
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

  /// Fails when a non-empty value is not a number.
  static FormFieldValidator<String> numeric({
    String message = 'Enter a valid number.',
  }) =>
      (value) {
        if (value == null || value.trim().isEmpty) return null;
        return num.tryParse(value.trim()) == null ? message : null;
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
