import 'package:flutter/material.dart';

/// Shortcuts for theme lookups and focus handling on a [BuildContext].
///
/// ```dart
/// Text(
///   'Welcome',
///   style: context.textTheme.titleLarge?.copyWith(
///     color: context.colorScheme.primary,
///   ),
/// );
/// ```
///
/// Responsive helpers (screen size, breakpoints) live in the UI module.
extension SymphonyContextX on BuildContext {
  /// The [ThemeData] of the closest [Theme] ancestor (`Theme.of(context)`).
  ///
  /// Like [Theme.of], reading it from a `build` method rebuilds the widget
  /// when the theme changes.
  ThemeData get theme => Theme.of(this);

  /// The [ColorScheme] of the current [theme].
  ColorScheme get colorScheme => theme.colorScheme;

  /// The [TextTheme] of the current [theme].
  TextTheme get textTheme => theme.textTheme;

  /// Whether the current [theme] uses a dark color scheme.
  bool get isDarkMode => theme.brightness == Brightness.dark;

  /// Removes the focus from the currently focused widget, which dismisses the
  /// on-screen keyboard of a focused text field. Does nothing when no widget
  /// has the focus.
  void unfocus() => FocusManager.instance.primaryFocus?.unfocus();
}
