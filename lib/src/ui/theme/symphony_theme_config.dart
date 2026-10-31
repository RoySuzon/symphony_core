import 'package:flutter/material.dart';

/// Configuration consumed by [SymphonyTheme.light] and [SymphonyTheme.dark].
///
/// Every value is optional; the defaults produce a neutral Material 3 theme.
/// Light and dark themes can receive different configurations:
///
/// ```dart
/// MaterialApp(
///   theme: SymphonyTheme.light(
///     const SymphonyThemeConfig(seedColor: Color(0xFF00796B)),
///   ),
///   darkTheme: SymphonyTheme.dark(
///     const SymphonyThemeConfig(seedColor: Color(0xFF00796B)),
///   ),
/// );
/// ```
@immutable
class SymphonyThemeConfig {
  /// Creates a theme configuration.
  const SymphonyThemeConfig({
    this.seedColor = defaultSeedColor,
    this.lightColorScheme,
    this.darkColorScheme,
    this.fontFamily,
    this.cornerRadius = 12,
    this.visualDensity,
    this.successColor,
    this.warningColor,
    this.infoColor,
    this.extensions = const <ThemeExtension<dynamic>>[],
  }) : assert(cornerRadius >= 0, 'cornerRadius must be non-negative.');

  /// The seed colour used when no explicit colour scheme is provided.
  static const Color defaultSeedColor = Color(0xFF3F51B5);

  /// Seed of the generated Material 3 colour schemes
  /// (`ColorScheme.fromSeed`).
  final Color seedColor;

  /// Explicit colour scheme of the light theme. Overrides [seedColor].
  final ColorScheme? lightColorScheme;

  /// Explicit colour scheme of the dark theme. Overrides [seedColor].
  final ColorScheme? darkColorScheme;

  /// Font family applied to every text style (the font must be bundled by
  /// the application). `null` keeps the platform default.
  final String? fontFamily;

  /// Base corner radius of buttons and text fields. The other radii of
  /// `SymphonyRadius` are derived from it. Defaults to 12.
  final double cornerRadius;

  /// Visual density of the theme. `null` uses the adaptive platform density.
  final VisualDensity? visualDensity;

  /// Overrides the success colour of `SymphonyColors`. Its foreground is
  /// computed automatically.
  final Color? successColor;

  /// Overrides the warning colour of `SymphonyColors`. Its foreground is
  /// computed automatically.
  final Color? warningColor;

  /// Overrides the info colour of `SymphonyColors`. Its foreground is
  /// computed automatically.
  final Color? infoColor;

  /// Additional theme extensions registered after the built-in ones. An
  /// extension of the same type (for example a custom `SymphonyColors`)
  /// replaces the built-in one.
  final Iterable<ThemeExtension<dynamic>> extensions;

  /// Returns a copy of this configuration with the given fields replaced.
  SymphonyThemeConfig copyWith({
    Color? seedColor,
    ColorScheme? lightColorScheme,
    ColorScheme? darkColorScheme,
    String? fontFamily,
    double? cornerRadius,
    VisualDensity? visualDensity,
    Color? successColor,
    Color? warningColor,
    Color? infoColor,
    Iterable<ThemeExtension<dynamic>>? extensions,
  }) {
    return SymphonyThemeConfig(
      seedColor: seedColor ?? this.seedColor,
      lightColorScheme: lightColorScheme ?? this.lightColorScheme,
      darkColorScheme: darkColorScheme ?? this.darkColorScheme,
      fontFamily: fontFamily ?? this.fontFamily,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      visualDensity: visualDensity ?? this.visualDensity,
      successColor: successColor ?? this.successColor,
      warningColor: warningColor ?? this.warningColor,
      infoColor: infoColor ?? this.infoColor,
      extensions: extensions ?? this.extensions,
    );
  }
}
