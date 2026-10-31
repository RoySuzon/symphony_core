import 'package:flutter/material.dart';

import '../../theme/symphony_colors.dart';
import '../../theme/symphony_spacing.dart';
import '../../utils/password_strength.dart';

/// A four segment meter visualizing a [PasswordStrengthResult].
///
/// Used by `SymphonyPasswordField(showStrengthIndicator: true)`, and usable
/// on its own:
///
/// ```dart
/// SymphonyPasswordStrengthMeter(
///   result: const PasswordStrengthEvaluator().evaluate(password),
/// );
/// ```
///
/// A `null` [result] (nothing typed yet) renders empty segments without a
/// label, so the layout does not jump when the user starts typing.
class SymphonyPasswordStrengthMeter extends StatelessWidget {
  /// Creates a strength meter.
  const SymphonyPasswordStrengthMeter({
    super.key,
    required this.result,
    this.labels,
    this.showLabel = true,
    this.semanticsLabel = 'Password strength',
  });

  /// English labels used when [labels] does not provide one.
  static const Map<PasswordStrength, String> defaultLabels =
      <PasswordStrength, String>{
    PasswordStrength.weak: 'Weak',
    PasswordStrength.fair: 'Fair',
    PasswordStrength.good: 'Good',
    PasswordStrength.strong: 'Strong',
  };

  /// The evaluation to display, or `null` when the password is empty.
  final PasswordStrengthResult? result;

  /// Overrides the label of each level (missing entries fall back to
  /// [defaultLabels]).
  final Map<PasswordStrength, String>? labels;

  /// Whether the level label is displayed next to the segments.
  final bool showLabel;

  /// Accessibility label of the meter; the level label is its value.
  final String semanticsLabel;

  /// The label displayed for [strength], taking [labels] into account.
  String labelFor(PasswordStrength strength) =>
      labels?[strength] ?? defaultLabels[strength]!;

  /// The colour representing [strength] in [theme].
  static Color colorFor(PasswordStrength strength, ThemeData theme) {
    final colors = theme.extension<SymphonyColors>() ??
        SymphonyColors.fallback(theme.brightness);
    return switch (strength) {
      PasswordStrength.weak => theme.colorScheme.error,
      PasswordStrength.fair => colors.warning,
      PasswordStrength.good => Color.lerp(colors.warning, colors.success, 0.5)!,
      PasswordStrength.strong => colors.success,
    };
  }

  static const int _segments = 4;
  static const Duration _animationDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = result;
    final activeSegments = current == null ? 0 : current.strength.index + 1;
    final activeColor = current == null
        ? theme.colorScheme.outlineVariant
        : colorFor(current.strength, theme);
    final label = current == null ? null : labelFor(current.strength);

    final segments = Row(
      children: <Widget>[
        for (var i = 0; i < _segments; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: SymphonySpacing.xs),
          Expanded(
            child: AnimatedContainer(
              duration: _animationDuration,
              height: 4,
              decoration: BoxDecoration(
                color: i < activeSegments
                    ? activeColor
                    : theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      container: true,
      label: semanticsLabel,
      value: label,
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Expanded(child: segments),
          if (showLabel && label != null) ...<Widget>[
            const SizedBox(width: SymphonySpacing.sm),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: activeColor),
            ),
          ],
        ],
      ),
    );
  }
}
