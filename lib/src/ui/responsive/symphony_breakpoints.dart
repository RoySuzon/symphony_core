import 'package:flutter/widgets.dart';

/// Material 3 window size classes, from the narrowest to the widest.
enum ScreenSizeClass {
  /// Phones in portrait (width < 600 by default).
  compact,

  /// Tablets in portrait, foldables (600 <= width < 840 by default).
  medium,

  /// Tablets in landscape, small desktops (840 <= width < 1200 by default).
  expanded,

  /// Desktops and large screens (width >= 1200 by default).
  large;

  /// Whether this class is the same as or wider than [other].
  bool isAtLeast(ScreenSizeClass other) => index >= other.index;

  /// Whether this class is the same as or narrower than [other].
  bool isAtMost(ScreenSizeClass other) => index <= other.index;
}

/// Width thresholds (in logical pixels) separating the [ScreenSizeClass]es.
///
/// The defaults follow the Material 3 window size classes: compact `< 600`,
/// medium `< 840`, expanded `< 1200`, large `>= 1200`. Provide custom values
/// app-wide with [SymphonyBreakpointsScope], or per widget through the
/// `breakpoints` parameters of the responsive widgets.
///
/// ```dart
/// const breakpoints = SymphonyBreakpoints(medium: 700);
/// breakpoints.classify(650); // ScreenSizeClass.compact
/// ```
@immutable
class SymphonyBreakpoints {
  /// Creates breakpoints. Thresholds must be positive and increasing.
  const SymphonyBreakpoints({
    this.medium = 600,
    this.expanded = 840,
    this.large = 1200,
  })  : assert(medium > 0, 'medium must be positive.'),
        assert(medium < expanded, 'medium must be smaller than expanded.'),
        assert(expanded < large, 'expanded must be smaller than large.');

  /// The Material 3 breakpoints (600 / 840 / 1200).
  static const SymphonyBreakpoints standard = SymphonyBreakpoints();

  /// Minimum width (inclusive) of [ScreenSizeClass.medium].
  final double medium;

  /// Minimum width (inclusive) of [ScreenSizeClass.expanded].
  final double expanded;

  /// Minimum width (inclusive) of [ScreenSizeClass.large].
  final double large;

  /// Returns the size class of a layout [width].
  ScreenSizeClass classify(double width) {
    if (width >= large) return ScreenSizeClass.large;
    if (width >= expanded) return ScreenSizeClass.expanded;
    if (width >= medium) return ScreenSizeClass.medium;
    return ScreenSizeClass.compact;
  }

  /// The breakpoints of the nearest [SymphonyBreakpointsScope], or
  /// [standard] when there is none.
  static SymphonyBreakpoints of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SymphonyBreakpointsScope>()
          ?.breakpoints ??
      standard;

  @override
  bool operator ==(Object other) =>
      other is SymphonyBreakpoints &&
      other.medium == medium &&
      other.expanded == expanded &&
      other.large == large;

  @override
  int get hashCode => Object.hash(medium, expanded, large);

  @override
  String toString() => 'SymphonyBreakpoints(medium: $medium, '
      'expanded: $expanded, large: $large)';
}

/// Provides custom [SymphonyBreakpoints] to every responsive helper below
/// it (`ResponsiveBuilder`, `ResponsiveLayout`, `ResponsiveValue`,
/// `context.screenSizeClass`...).
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => SymphonyBreakpointsScope(
///     breakpoints: const SymphonyBreakpoints(medium: 720),
///     child: child!,
///   ),
/// );
/// ```
class SymphonyBreakpointsScope extends InheritedWidget {
  /// Creates a breakpoints scope.
  const SymphonyBreakpointsScope({
    super.key,
    required this.breakpoints,
    required super.child,
  });

  /// The breakpoints exposed to descendants.
  final SymphonyBreakpoints breakpoints;

  @override
  bool updateShouldNotify(SymphonyBreakpointsScope oldWidget) =>
      breakpoints != oldWidget.breakpoints;
}
