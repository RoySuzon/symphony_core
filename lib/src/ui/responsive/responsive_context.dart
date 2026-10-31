import 'package:flutter/widgets.dart';

import 'symphony_breakpoints.dart';

/// Screen size class helpers on [BuildContext].
///
/// The size class is computed from the screen width (`MediaQuery.sizeOf`)
/// with [SymphonyBreakpoints.of] the context. Use `ResponsiveBuilder` to adapt
/// to the space available to a widget instead.
///
/// ```dart
/// final columns = context.isExpandedOrLarger ? 3 : 1;
/// ```
extension SymphonyResponsiveContextX on BuildContext {
  /// The [ScreenSizeClass] of the screen width.
  ScreenSizeClass get screenSizeClass =>
      SymphonyBreakpoints.of(this).classify(MediaQuery.sizeOf(this).width);

  /// Whether the screen is [ScreenSizeClass.compact] (phones in portrait).
  bool get isCompact => screenSizeClass == ScreenSizeClass.compact;

  /// Whether the screen is [ScreenSizeClass.medium] or wider.
  bool get isMediumOrLarger =>
      screenSizeClass.isAtLeast(ScreenSizeClass.medium);

  /// Whether the screen is [ScreenSizeClass.expanded] or wider.
  bool get isExpandedOrLarger =>
      screenSizeClass.isAtLeast(ScreenSizeClass.expanded);
}
