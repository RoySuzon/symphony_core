import 'package:flutter/widgets.dart';

import 'symphony_breakpoints.dart';

/// Signature of [ResponsiveBuilder.builder].
typedef SymphonyResponsiveWidgetBuilder = Widget Function(
  BuildContext context,
  ScreenSizeClass sizeClass,
  BoxConstraints constraints,
);

/// Builds a widget from the [ScreenSizeClass] of the space available to it.
///
/// The size class is computed from the incoming layout constraints (not the
/// screen), so the builder adapts correctly inside split views, dialogs and
/// side panels. When the available width is unbounded (inside a horizontal
/// scroll view) the screen width from [MediaQuery] is used instead.
///
/// ```dart
/// ResponsiveBuilder(
///   builder: (context, sizeClass, constraints) =>
///       sizeClass.isAtLeast(ScreenSizeClass.expanded)
///           ? const TwoPaneLayout()
///           : const SinglePaneLayout(),
/// );
/// ```
class ResponsiveBuilder extends StatelessWidget {
  /// Creates a responsive builder.
  const ResponsiveBuilder({
    super.key,
    required this.builder,
    this.breakpoints,
  });

  /// Builds the content for the current size class.
  final SymphonyResponsiveWidgetBuilder builder;

  /// Breakpoints used to classify the width. Defaults to
  /// [SymphonyBreakpoints.of] the context.
  final SymphonyBreakpoints? breakpoints;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveBreakpoints =
            breakpoints ?? SymphonyBreakpoints.of(context);
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.maybeSizeOf(context)?.width ?? 0;
        return builder(
          context,
          effectiveBreakpoints.classify(width),
          constraints,
        );
      },
    );
  }
}
