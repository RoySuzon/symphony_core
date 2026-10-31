import 'package:flutter/material.dart';

import 'symphony_colors.dart';
import 'symphony_radius.dart';
import 'symphony_theme_config.dart';

/// Builds Material 3 [ThemeData] for applications using symphony_core.
///
/// The themes are generated with `ColorScheme.fromSeed` (unless explicit
/// schemes are configured), apply [SymphonyThemeConfig.cornerRadius] to the
/// button shapes and register the [SymphonyColors] and [SymphonyRadius]
/// extensions read by the symphony_core widgets.
///
/// ```dart
/// MaterialApp(
///   theme: SymphonyTheme.light(),
///   darkTheme: SymphonyTheme.dark(),
///   themeMode: ThemeMode.system,
/// );
/// ```
///
/// Only component themes whose types are stable across all supported Flutter
/// versions are configured; customize the result further with
/// `ThemeData.copyWith`.
abstract final class SymphonyTheme {
  /// A light Material 3 theme built from [config].
  static ThemeData light([
    SymphonyThemeConfig config = const SymphonyThemeConfig(),
  ]) =>
      _build(config, Brightness.light);

  /// A dark Material 3 theme built from [config].
  static ThemeData dark([
    SymphonyThemeConfig config = const SymphonyThemeConfig(),
  ]) =>
      _build(config, Brightness.dark);

  static ThemeData _build(SymphonyThemeConfig config, Brightness brightness) {
    final explicitScheme = brightness == Brightness.dark
        ? config.darkColorScheme
        : config.lightColorScheme;
    final scheme = explicitScheme ??
        ColorScheme.fromSeed(
          seedColor: config.seedColor,
          brightness: brightness,
        );
    final radius = SymphonyRadius.fromBase(config.cornerRadius);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: radius.mediumBorderRadius,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: config.fontFamily,
      visualDensity: config.visualDensity,
      scaffoldBackgroundColor: scheme.surface,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: buttonShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: buttonShape),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: buttonShape),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: buttonShape),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: radius.largeBorderRadius),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        actionTextColor: scheme.inversePrimary,
        closeIconColor: scheme.onInverseSurface,
        shape: RoundedRectangleBorder(borderRadius: radius.smallBorderRadius),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer,
      ),
      extensions: _extensions(
        _statusColors(config, brightness),
        radius,
        config.extensions,
      ),
    );
  }

  /// The built-in extensions followed by the configured ones (later entries
  /// of the same type win in [ThemeData]).
  ///
  /// A generator is used on purpose: spreading `ThemeExtension<dynamic>`
  /// values into a `<ThemeExtension<dynamic>>[]` literal is rejected by the
  /// Dart compiler because of the F-bounded type parameter.
  static Iterable<ThemeExtension<dynamic>> _extensions(
    SymphonyColors colors,
    SymphonyRadius radius,
    Iterable<ThemeExtension<dynamic>> additional,
  ) sync* {
    yield colors;
    yield radius;
    yield* additional;
  }

  static SymphonyColors _statusColors(
    SymphonyThemeConfig config,
    Brightness brightness,
  ) {
    final success = config.successColor;
    final warning = config.warningColor;
    final info = config.infoColor;
    return SymphonyColors.fallback(brightness).copyWith(
      success: success,
      onSuccess: success == null ? null : SymphonyColors.foregroundFor(success),
      warning: warning,
      onWarning: warning == null ? null : SymphonyColors.foregroundFor(warning),
      info: info,
      onInfo: info == null ? null : SymphonyColors.foregroundFor(info),
    );
  }
}
