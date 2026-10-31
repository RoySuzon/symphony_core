import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The corner radius scale of the symphony_core theme.
///
/// [SymphonyTheme] registers a scale derived from
/// [SymphonyThemeConfig.cornerRadius] as a [ThemeExtension], so components
/// that are not covered by a Material component theme (text fields, cards,
/// overlays...) can follow the configured shape:
///
/// ```dart
/// final radius = SymphonyRadius.of(context);
/// DecoratedBox(
///   decoration: BoxDecoration(borderRadius: radius.mediumBorderRadius),
/// );
/// ```
///
/// When the ambient theme has no [SymphonyRadius] extension (an application
/// that does not use [SymphonyTheme]), [of] returns [standard].
@immutable
class SymphonyRadius extends ThemeExtension<SymphonyRadius> {
  /// Creates a radius scale. All values must be non-negative.
  const SymphonyRadius({
    this.small = 8,
    this.medium = 12,
    this.large = 16,
    this.extraLarge = 28,
  }) : assert(small >= 0),
       assert(medium >= 0),
       assert(large >= 0),
       assert(extraLarge >= 0);

  /// Derives a harmonious scale from a [base] radius, used as [medium].
  ///
  /// [small] is two thirds of the base, [large] four thirds and
  /// [extraLarge] seven thirds (8 / 12 / 16 / 28 for the default base 12).
  /// A base of `0` produces square corners everywhere.
  factory SymphonyRadius.fromBase(double base) {
    assert(base >= 0, 'The base radius must be non-negative.');
    return SymphonyRadius(
      small: base * 2 / 3,
      medium: base,
      large: base * 4 / 3,
      extraLarge: base * 7 / 3,
    );
  }

  /// The default scale (8 / 12 / 16 / 28).
  static const SymphonyRadius standard = SymphonyRadius();

  /// A radius large enough to fully round (stadium / pill shape) any
  /// component.
  static const double full = 999;

  /// Radius of small elements: chips, badges, snack bars, tooltips.
  final double small;

  /// Radius of regular elements: buttons, text fields, list tiles.
  final double medium;

  /// Radius of large elements: cards, menus, floating action buttons.
  final double large;

  /// Radius of very large surfaces: dialogs, bottom sheets.
  final double extraLarge;

  /// [small] as a [BorderRadius].
  BorderRadius get smallBorderRadius => BorderRadius.circular(small);

  /// [medium] as a [BorderRadius].
  BorderRadius get mediumBorderRadius => BorderRadius.circular(medium);

  /// [large] as a [BorderRadius].
  BorderRadius get largeBorderRadius => BorderRadius.circular(large);

  /// [extraLarge] as a [BorderRadius].
  BorderRadius get extraLargeBorderRadius => BorderRadius.circular(extraLarge);

  /// Returns the scale registered in the ambient [Theme], or [standard] when
  /// the theme does not contain a [SymphonyRadius] extension.
  static SymphonyRadius of(BuildContext context) =>
      Theme.of(context).extension<SymphonyRadius>() ?? standard;

  @override
  SymphonyRadius copyWith({
    double? small,
    double? medium,
    double? large,
    double? extraLarge,
  }) {
    return SymphonyRadius(
      small: small ?? this.small,
      medium: medium ?? this.medium,
      large: large ?? this.large,
      extraLarge: extraLarge ?? this.extraLarge,
    );
  }

  @override
  SymphonyRadius lerp(SymphonyRadius? other, double t) {
    if (other == null) return this;
    return SymphonyRadius(
      small: lerpDouble(small, other.small, t)!,
      medium: lerpDouble(medium, other.medium, t)!,
      large: lerpDouble(large, other.large, t)!,
      extraLarge: lerpDouble(extraLarge, other.extraLarge, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SymphonyRadius &&
      other.small == small &&
      other.medium == medium &&
      other.large == large &&
      other.extraLarge == extraLarge;

  @override
  int get hashCode => Object.hash(small, medium, large, extraLarge);

  @override
  String toString() =>
      'SymphonyRadius(small: $small, medium: $medium, '
      'large: $large, extraLarge: $extraLarge)';
}
