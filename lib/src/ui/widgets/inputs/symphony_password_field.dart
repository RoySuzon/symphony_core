import 'package:flutter/material.dart';

import '../../theme/symphony_spacing.dart';
import '../../utils/password_strength.dart';
import 'symphony_password_strength_meter.dart';
import 'symphony_text_field.dart';

/// Password field with a show / hide toggle and an optional strength meter.
///
/// ```dart
/// SymphonyPasswordField(
///   controller: passwordController,
///   textInputAction: TextInputAction.done,
///   showStrengthIndicator: true,
///   validator: SymphonyValidators.minLength(8),
///   onSubmitted: (_) => submit(),
/// );
/// ```
///
/// The toggle button exposes [showPasswordTooltip] / [hidePasswordTooltip] as
/// tooltip and accessibility label. The strength is computed with
/// [strengthEvaluator] (a pure [PasswordStrengthEvaluator]); its level labels
/// can be localized with [strengthLabels].
class SymphonyPasswordField extends StatefulWidget {
  /// Creates a password field.
  const SymphonyPasswordField({
    super.key,
    this.controller,
    this.label = 'Password',
    this.hint,
    this.errorText,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.enabled = true,
    this.autofocus = false,
    this.autofillHints = const <String>[AutofillHints.password],
    this.focusNode,
    this.autovalidateMode,
    this.showStrengthIndicator = false,
    this.helperText,
    this.prefixIcon = Icons.lock_outline,
    this.showPasswordTooltip = 'Show password',
    this.hidePasswordTooltip = 'Hide password',
    this.strengthEvaluator = const PasswordStrengthEvaluator(),
    this.strengthLabels,
    this.strengthSemanticsLabel = 'Password strength',
    this.onStrengthChanged,
    this.onSaved,
  });

  /// Controls the text. An internal controller is used when `null`.
  final TextEditingController? controller;

  /// Floating label.
  final String? label;

  /// Placeholder text.
  final String? hint;

  /// Error text below the field.
  final String? errorText;

  /// Form validator.
  final FormFieldValidator<String>? validator;

  /// Called on every change.
  final ValueChanged<String>? onChanged;

  /// Called when the keyboard action is triggered.
  final ValueChanged<String>? onSubmitted;

  /// Keyboard action button.
  final TextInputAction? textInputAction;

  /// Whether the field accepts input.
  final bool enabled;

  /// Requests focus on first build.
  final bool autofocus;

  /// Autofill hints. Use `AutofillHints.newPassword` on sign-up forms.
  final Iterable<String>? autofillHints;

  /// Focus node.
  final FocusNode? focusNode;

  /// When to run [validator].
  final AutovalidateMode? autovalidateMode;

  /// Displays a password strength meter below the field.
  final bool showStrengthIndicator;

  /// Helper text below the field.
  final String? helperText;

  /// Leading icon. `null` removes it.
  final IconData? prefixIcon;

  /// Tooltip / accessibility label of the toggle while the text is hidden.
  final String showPasswordTooltip;

  /// Tooltip / accessibility label of the toggle while the text is visible.
  final String hidePasswordTooltip;

  /// Computes the strength shown by the meter and passed to
  /// [onStrengthChanged].
  final PasswordStrengthEvaluator strengthEvaluator;

  /// Overrides the meter label of each strength level.
  final Map<PasswordStrength, String>? strengthLabels;

  /// Accessibility label of the strength meter.
  final String strengthSemanticsLabel;

  /// Called whenever the evaluated strength changes (an empty password
  /// reports [PasswordStrengthResult.empty]).
  final ValueChanged<PasswordStrengthResult>? onStrengthChanged;

  /// Called by `FormState.save` with the current value.
  final FormFieldSetter<String>? onSaved;

  @override
  State<SymphonyPasswordField> createState() => _SymphonyPasswordFieldState();
}

class _SymphonyPasswordFieldState extends State<SymphonyPasswordField> {
  TextEditingController? _internalController;
  bool _obscured = true;
  PasswordStrengthResult _strength = PasswordStrengthResult.empty;
  bool _isEmpty = true;

  TextEditingController get _controller =>
      widget.controller ?? (_internalController ??= TextEditingController());

  bool get _tracksStrength =>
      widget.showStrengthIndicator || widget.onStrengthChanged != null;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    _recomputeStrength(notify: false);
  }

  @override
  void didUpdateWidget(SymphonyPasswordField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final previous = oldWidget.controller ?? _internalController;
      previous?.removeListener(_handleTextChanged);
      if (widget.controller != null) {
        _internalController?.dispose();
        _internalController = null;
      } else {
        _internalController =
            TextEditingController(text: oldWidget.controller?.text);
      }
      _controller.addListener(_handleTextChanged);
      // Never notify listeners while the framework is building.
      _recomputeStrength(notify: false);
    } else if (oldWidget.strengthEvaluator != widget.strengthEvaluator ||
        oldWidget.showStrengthIndicator != widget.showStrengthIndicator ||
        (oldWidget.onStrengthChanged == null) !=
            (widget.onStrengthChanged == null)) {
      _recomputeStrength(notify: false);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _internalController?.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    final previousStrength = _strength;
    final wasEmpty = _isEmpty;
    _recomputeStrength(notify: true);
    final meterChanged = previousStrength != _strength || wasEmpty != _isEmpty;
    if (widget.showStrengthIndicator && meterChanged) {
      setState(() {});
    }
  }

  /// Updates [_strength] / [_isEmpty] from the controller text. When
  /// [notify] is true, [SymphonyPasswordField.onStrengthChanged] is called if
  /// the strength changed.
  void _recomputeStrength({required bool notify}) {
    final text = _controller.text;
    _isEmpty = text.isEmpty;
    if (!_tracksStrength) return;
    final next = widget.strengthEvaluator.evaluate(text);
    final changed = next != _strength;
    _strength = next;
    if (notify && changed) widget.onStrengthChanged?.call(next);
  }

  void _toggleObscured() => setState(() => _obscured = !_obscured);

  @override
  Widget build(BuildContext context) {
    final field = SymphonyTextField(
      controller: _controller,
      label: widget.label,
      hint: widget.hint,
      helperText: widget.helperText,
      errorText: widget.errorText,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onSaved: widget.onSaved,
      textInputAction: widget.textInputAction,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      autofillHints: widget.autofillHints,
      focusNode: widget.focusNode,
      autovalidateMode: widget.autovalidateMode,
      obscureText: _obscured,
      keyboardType: TextInputType.visiblePassword,
      autocorrect: false,
      enableSuggestions: false,
      prefixIcon: widget.prefixIcon,
      suffix: IconButton(
        tooltip:
            _obscured ? widget.showPasswordTooltip : widget.hidePasswordTooltip,
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        onPressed: widget.enabled ? _toggleObscured : null,
      ),
    );

    // The column is always present so that toggling the indicator keeps the
    // form field state.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        field,
        if (widget.showStrengthIndicator)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SymphonySpacing.xs,
              SymphonySpacing.sm,
              SymphonySpacing.xs,
              0,
            ),
            child: SymphonyPasswordStrengthMeter(
              result: _isEmpty ? null : _strength,
              labels: widget.strengthLabels,
              semanticsLabel: widget.strengthSemanticsLabel,
            ),
          ),
      ],
    );
  }
}
