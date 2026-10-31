import 'package:flutter/material.dart';

/// Semantic status colours (success, warning, info) that complement the
/// Material [ColorScheme] (which already provides `error` / `onError`).
///
/// [SymphonyTheme] registers [light] / [dark] (or the colours configured in
/// [SymphonyThemeConfig]) as a [ThemeExtension]. Read them with [of], which
/// falls back to the defaults matching the theme brightness when the
/// extension is missing:
///
/// ```dart
/// final colors = SymphonyColors.of(context);
/// Icon(Icons.check_circle_outline, color: colors.success);
/// ```
///
/// Applications can override the colours by passing their own instance in
/// `ThemeData.extensions` (or in [SymphonyThemeConfig.extensions]).
@immutable
class SymphonyColors extends ThemeExtension<SymphonyColors> {
  /// Creates a set of status colours.
  const SymphonyColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.info,
    required this.onInfo,
  });

  /// Creates status colours from three accent colours, choosing a black or
  /// white foreground for each one with [foregroundFor].
  factory SymphonyColors.fromAccents({
    required Color success,
    required Color warning,
    required Color info,
  }) {
    return SymphonyColors(
      success: success,
      onSuccess: foregroundFor(success),
      warning: warning,
      onWarning: foregroundFor(warning),
      info: info,
      onInfo: foregroundFor(info),
    );
  }

  /// Default colours for light themes (all foregrounds meet WCAG AA contrast).
  static const SymphonyColors light = SymphonyColors(
    success: Color(0xFF2E7D32),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFFB45309),
    onWarning: Color(0xFFFFFFFF),
    info: Color(0xFF0277BD),
    onInfo: Color(0xFFFFFFFF),
  );

  /// Default colours for dark themes (all foregrounds meet WCAG AA contrast).
  static const SymphonyColors dark = SymphonyColors(
    success: Color(0xFF81C784),
    onSuccess: Color(0xFF00390A),
    warning: Color(0xFFFFB74D),
    onWarning: Color(0xFF452B00),
    info: Color(0xFF81D4FA),
    onInfo: Color(0xFF003549),
  );

  /// Colour of positive outcomes (saved, completed, online...).
  final Color success;

  /// Foreground (text / icons) drawn on top of [success].
  final Color onSuccess;

  /// Colour of situations that need attention but are not errors.
  final Color warning;

  /// Foreground (text / icons) drawn on top of [warning].
  final Color onWarning;

  /// Colour of neutral, informative messages.
  final Color info;

  /// Foreground (text / icons) drawn on top of [info].
  final Color onInfo;

  /// The default colours for [brightness]: [dark] or [light].
  static SymphonyColors fallback(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Returns the colours registered in the ambient [Theme], or
  /// [fallback] for the theme brightness when the extension is missing.
  static SymphonyColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SymphonyColors>() ?? fallback(theme.brightness);
  }

  /// Returns white or black, whichever has the higher WCAG 2 contrast ratio
  /// with [background].
  ///
  /// Unlike `ThemeData.estimateBrightnessForColor`, which deliberately
  /// favours white text, mid-tone colours such as `Color(0xFF4CAF50)` get
  /// black text (7.6:1) instead of white text (2.8:1, below the 4.5:1 AA
  /// minimum).
  static Color foregroundFor(Color background) {
    final luminance = background.computeLuminance();
    // Contrast ratio = (lighter + 0.05) / (darker + 0.05).
    final contrastWithWhite = 1.05 / (luminance + 0.05);
    final contrastWithBlack = (luminance + 0.05) / 0.05;
    return contrastWithBlack > contrastWithWhite
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
  }

  @override
  SymphonyColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? info,
    Color? onInfo,
  }) {
    return SymphonyColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
    );
  }

  @override
  SymphonyColors lerp(SymphonyColors? other, double t) {
    if (other == null) return this;
    return SymphonyColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SymphonyColors &&
      other.success == success &&
      other.onSuccess == onSuccess &&
      other.warning == warning &&
      other.onWarning == onWarning &&
      other.info == info &&
      other.onInfo == onInfo;

  @override
  int get hashCode =>
      Object.hash(success, onSuccess, warning, onWarning, info, onInfo);

  @override
  String toString() => 'SymphonyColors(success: $success, '
      'onSuccess: $onSuccess, warning: $warning, onWarning: $onWarning, '
      'info: $info, onInfo: $onInfo)';
}
