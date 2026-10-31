import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/symphony_radius.dart';

/// Themed text form field with an outlined border that follows the theme
/// corner radius (`SymphonyRadius.medium`).
///
/// It is a thin wrapper around [TextFormField], so it participates in [Form]
/// validation and saving:
///
/// ```dart
/// SymphonyTextField(
///   label: 'E-mail',
///   prefixIcon: Icons.alternate_email,
///   keyboardType: TextInputType.emailAddress,
///   textInputAction: TextInputAction.next,
///   autofillHints: const <String>[AutofillHints.email],
///   validator: SymphonyValidators.compose(<FormFieldValidator<String>>[
///     SymphonyValidators.required(),
///     SymphonyValidators.email(),
///   ]),
/// );
/// ```
///
/// When [obscureText] is true the field is forced to a single line and
/// auto-correction / suggestions are disabled.
class SymphonyTextField extends StatelessWidget {
  /// Creates a text field.
  const SymphonyTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.autofillHints,
    this.inputFormatters,
    this.focusNode,
    this.autovalidateMode,
    this.onEditingComplete,
    this.onSaved,
    this.prefixText,
    this.suffixText,
    this.counterText,
    this.style,
    this.textAlign = TextAlign.start,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.filled,
    this.fillColor,
    this.isDense,
    this.errorMaxLines = 2,
    this.helperMaxLines = 2,
    this.restorationId,
  }) : assert(
          initialValue == null || controller == null,
          'Provide either a controller or an initialValue, not both.',
        );

  /// Controls the text. Do not combine with [initialValue].
  final TextEditingController? controller;

  /// Initial text when no [controller] is given.
  final String? initialValue;

  /// Floating label.
  final String? label;

  /// Placeholder text.
  final String? hint;

  /// Helper text below the field.
  final String? helperText;

  /// Error text below the field (overrides [validator] output).
  final String? errorText;

  /// Leading icon.
  final IconData? prefixIcon;

  /// Trailing widget (typically an [IconButton]).
  final Widget? suffix;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Keyboard action button.
  final TextInputAction? textInputAction;

  /// Capitalization behaviour.
  final TextCapitalization textCapitalization;

  /// Form validator.
  final FormFieldValidator<String>? validator;

  /// Called on every change.
  final ValueChanged<String>? onChanged;

  /// Called when the keyboard action is triggered.
  final ValueChanged<String>? onSubmitted;

  /// Called when the field is tapped.
  final VoidCallback? onTap;

  /// Hides the text (passwords).
  final bool obscureText;

  /// Whether the field accepts input.
  final bool enabled;

  /// Whether the text can be selected but not edited.
  final bool readOnly;

  /// Requests focus on first build.
  final bool autofocus;

  /// Maximum number of lines. `null` grows without limit.
  final int? maxLines;

  /// Minimum number of lines.
  final int? minLines;

  /// Maximum number of characters. Displays a counter below the field.
  final int? maxLength;

  /// Autofill hints (e.g. `AutofillHints.email`).
  final Iterable<String>? autofillHints;

  /// Input formatters.
  final List<TextInputFormatter>? inputFormatters;

  /// Focus node.
  final FocusNode? focusNode;

  /// When to run [validator].
  final AutovalidateMode? autovalidateMode;

  /// Called when the user finishes editing (before [onSubmitted]).
  final VoidCallback? onEditingComplete;

  /// Called by `FormState.save` with the current value.
  final FormFieldSetter<String>? onSaved;

  /// Text displayed before the input (e.g. a currency symbol).
  final String? prefixText;

  /// Text displayed after the input (e.g. a unit).
  final String? suffixText;

  /// Replaces the character counter shown when [maxLength] is set. An empty
  /// string hides the counter.
  final String? counterText;

  /// Style of the input text. Defaults to the theme `bodyLarge` style.
  final TextStyle? style;

  /// Horizontal alignment of the input text.
  final TextAlign textAlign;

  /// Whether auto-correction is enabled (always disabled when
  /// [obscureText] is true).
  final bool autocorrect;

  /// Whether keyboard suggestions are shown (always disabled when
  /// [obscureText] is true).
  final bool enableSuggestions;

  /// Whether the field background is filled. Defaults to the ambient
  /// input decoration theme.
  final bool? filled;

  /// Background colour used when [filled] is true.
  final Color? fillColor;

  /// Uses less vertical space, for dense forms and filters.
  final bool? isDense;

  /// Maximum number of lines of the error text.
  final int? errorMaxLines;

  /// Maximum number of lines of the helper text.
  final int? helperMaxLines;

  /// Restoration id used to save and restore the text.
  final String? restorationId;

  @override
  Widget build(BuildContext context) {
    final radius = SymphonyRadius.of(context);
    final icon = prefixIcon;
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      focusNode: focusNode,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        helperMaxLines: helperMaxLines,
        errorText: errorText,
        errorMaxLines: errorMaxLines,
        prefixIcon: icon == null ? null : Icon(icon),
        prefixText: prefixText,
        suffixIcon: suffix,
        suffixText: suffixText,
        counterText: counterText,
        filled: filled,
        fillColor: fillColor,
        isDense: isDense,
        border: OutlineInputBorder(borderRadius: radius.mediumBorderRadius),
      ),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      style: style,
      textAlign: textAlign,
      autofocus: autofocus,
      readOnly: readOnly,
      obscureText: obscureText,
      autocorrect: autocorrect && !obscureText,
      enableSuggestions: enableSuggestions && !obscureText,
      maxLines: obscureText ? 1 : maxLines,
      minLines: obscureText ? null : minLines,
      maxLength: maxLength,
      onChanged: onChanged,
      onTap: onTap,
      onEditingComplete: onEditingComplete,
      onFieldSubmitted: onSubmitted,
      onSaved: onSaved,
      validator: validator,
      inputFormatters: inputFormatters,
      enabled: enabled,
      autofillHints: autofillHints,
      autovalidateMode: autovalidateMode,
      restorationId: restorationId,
    );
  }
}
