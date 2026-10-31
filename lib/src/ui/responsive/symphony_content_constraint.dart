import 'package:flutter/widgets.dart';

/// Limits the width of its [child] (forms, articles, settings pages) so that
/// content stays readable on wide screens.
///
/// The child takes the available width up to [maxWidth] and is positioned
/// with [alignment] inside the remaining space.
///
/// ```dart
/// SymphonyContentConstraint(
///   padding: SymphonySpacing.screen,
///   child: SignInForm(),
/// );
/// ```
class SymphonyContentConstraint extends StatelessWidget {
  /// Creates a content constraint.
  const SymphonyContentConstraint({
    super.key,
    required this.child,
    this.maxWidth = 600,
    this.alignment = Alignment.topCenter,
    this.padding,
  }) : assert(maxWidth > 0, 'maxWidth must be positive.');

  /// The constrained content.
  final Widget child;

  /// Maximum width of the content (padding included).
  final double maxWidth;

  /// Position of the content inside the available space.
  final AlignmentGeometry alignment;

  /// Optional padding applied inside the constrained area.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final insets = padding;
    final content =
        insets == null ? child : Padding(padding: insets, child: child);
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: content),
      ),
    );
  }
}
