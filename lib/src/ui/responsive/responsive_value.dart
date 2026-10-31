import 'package:flutter/widgets.dart';

import 'responsive_context.dart';
import 'symphony_breakpoints.dart';

/// A value that depends on the [ScreenSizeClass] of the screen.
///
/// Missing values fall back to the next smaller one: a `large` screen uses
/// [large], else [expanded], else [medium], else [compact].
///
/// ```dart
/// const padding = ResponsiveValue<double>(compact: 16, medium: 24, large: 32);
/// Padding(padding: EdgeInsets.all(padding.resolve(context)), child: child);
/// ```
@immutable
class ResponsiveValue<T> {
  /// Creates a responsive value.
  const ResponsiveValue({
    required this.compact,
    this.medium,
    this.expanded,
    this.large,
  });

  /// A value that is the same for every size class.
  const ResponsiveValue.all(T value)
      : compact = value,
        medium = null,
        expanded = null,
        large = null;

  /// Value for [ScreenSizeClass.compact] (and the final fallback).
  final T compact;

  /// Value for [ScreenSizeClass.medium].
  final T? medium;

  /// Value for [ScreenSizeClass.expanded].
  final T? expanded;

  /// Value for [ScreenSizeClass.large].
  final T? large;

  /// The value for [sizeClass], applying the fallback rules.
  T resolveFor(ScreenSizeClass sizeClass) => switch (sizeClass) {
        ScreenSizeClass.compact => compact,
        ScreenSizeClass.medium => medium ?? compact,
        ScreenSizeClass.expanded => expanded ?? medium ?? compact,
        ScreenSizeClass.large => large ?? expanded ?? medium ?? compact,
      };

  /// The value for the size class of the screen (`MediaQuery` width), using
  /// [breakpoints] or [SymphonyBreakpoints.of] the context.
  T resolve(BuildContext context, {SymphonyBreakpoints? breakpoints}) {
    final sizeClass = breakpoints == null
        ? context.screenSizeClass
        : breakpoints.classify(MediaQuery.sizeOf(context).width);
    return resolveFor(sizeClass);
  }

  @override
  bool operator ==(Object other) =>
      other is ResponsiveValue<T> &&
      other.compact == compact &&
      other.medium == medium &&
      other.expanded == expanded &&
      other.large == large;

  @override
  int get hashCode => Object.hash(compact, medium, expanded, large);

  @override
  String toString() => 'ResponsiveValue<$T>(compact: $compact, '
      'medium: $medium, expanded: $expanded, large: $large)';
}
