import 'package:flutter/widgets.dart';

import 'responsive_builder.dart';
import 'symphony_breakpoints.dart';

/// Displays one of several layouts depending on the [ScreenSizeClass] of the
/// available width.
///
/// Missing layouts fall back to the next smaller one: a `large` screen uses
/// [large], else [expanded], else [medium], else [compact].
///
/// ```dart
/// ResponsiveLayout(
///   compact: const OrdersList(),
///   expanded: const OrdersMasterDetail(),
/// );
/// ```
class ResponsiveLayout extends StatelessWidget {
  /// Creates a responsive layout.
  const ResponsiveLayout({
    super.key,
    required this.compact,
    this.medium,
    this.expanded,
    this.large,
    this.breakpoints,
  });

  /// Layout for [ScreenSizeClass.compact] (and the final fallback).
  final Widget compact;

  /// Layout for [ScreenSizeClass.medium].
  final Widget? medium;

  /// Layout for [ScreenSizeClass.expanded].
  final Widget? expanded;

  /// Layout for [ScreenSizeClass.large].
  final Widget? large;

  /// Breakpoints used to classify the width. Defaults to
  /// [SymphonyBreakpoints.of] the context.
  final SymphonyBreakpoints? breakpoints;

  /// The layout displayed for [sizeClass], applying the fallback rules.
  Widget layoutFor(ScreenSizeClass sizeClass) => switch (sizeClass) {
    ScreenSizeClass.compact => compact,
    ScreenSizeClass.medium => medium ?? compact,
    ScreenSizeClass.expanded => expanded ?? medium ?? compact,
    ScreenSizeClass.large => large ?? expanded ?? medium ?? compact,
  };

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      breakpoints: breakpoints,
      builder: (context, sizeClass, _) => layoutFor(sizeClass),
    );
  }
}
