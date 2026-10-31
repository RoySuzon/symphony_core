import 'package:flutter/material.dart';

import '../../theme/symphony_spacing.dart';

/// Centered circular progress indicator with an optional message.
///
/// ```dart
/// const SymphonyLoadingIndicator(message: 'Loading your dashboard…');
/// ```
///
/// Set [adaptive] to render the platform indicator (Cupertino activity
/// indicator on iOS and macOS).
class SymphonyLoadingIndicator extends StatelessWidget {
  /// Creates a loading indicator.
  const SymphonyLoadingIndicator({
    super.key,
    this.message,
    this.size = 36,
    this.color,
    this.adaptive = false,
    this.strokeWidth,
    this.semanticsLabel,
  }) : assert(size > 0, 'size must be positive.');

  /// Text displayed below the indicator.
  final String? message;

  /// Diameter of the indicator.
  final double size;

  /// Color of the indicator (defaults to the theme's progress indicator
  /// colour, then to the primary colour).
  final Color? color;

  /// Uses `CircularProgressIndicator.adaptive` (platform specific look).
  final bool adaptive;

  /// Width of the indicator ring. Defaults to a value proportional to [size].
  final double? strokeWidth;

  /// Accessibility label of the indicator. Defaults to [message], or to
  /// `'Loading'` when there is no message.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor =
        color ??
        theme.progressIndicatorTheme.color ??
        theme.colorScheme.primary;
    final effectiveStrokeWidth =
        strokeWidth ?? (size / 9).clamp(2.0, 4.0).toDouble();
    final text = message;
    // The message is read by screen readers through the indicator label so
    // the text itself is excluded to avoid announcing it twice.
    final label = semanticsLabel ?? text ?? 'Loading';

    final indicator =
        adaptive
            ? CircularProgressIndicator.adaptive(
              valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
              strokeWidth: effectiveStrokeWidth,
              semanticsLabel: label,
            )
            : CircularProgressIndicator(
              color: effectiveColor,
              strokeWidth: effectiveStrokeWidth,
              semanticsLabel: label,
            );

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox.square(dimension: size, child: indicator),
          if (text != null) ...<Widget>[
            const SizedBox(height: SymphonySpacing.md),
            ExcludeSemantics(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
