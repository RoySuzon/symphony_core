import 'package:flutter/widgets.dart';

/// The spacing scale used by every symphony_core widget, in logical pixels.
///
/// The scale follows a 4 point grid. Use the raw values for gaps and the
/// [EdgeInsets] helpers for paddings so layouts stay consistent across
/// screens and applications:
///
/// ```dart
/// Padding(
///   padding: SymphonySpacing.allLg,
///   child: Column(
///     children: <Widget>[
///       title,
///       const SizedBox(height: SymphonySpacing.sm),
///       body,
///     ],
///   ),
/// );
/// ```
abstract final class SymphonySpacing {
  /// No spacing (0).
  static const double none = 0;

  /// Hairline spacing (2).
  static const double xxs = 2;

  /// Extra small spacing (4).
  static const double xs = 4;

  /// Small spacing (8).
  static const double sm = 8;

  /// Medium spacing (12).
  static const double md = 12;

  /// Large spacing (16), the default content padding.
  static const double lg = 16;

  /// Extra large spacing (24).
  static const double xl = 24;

  /// Double extra large spacing (32).
  static const double xxl = 32;

  /// [xxs] on every side.
  static const EdgeInsets allXxs = EdgeInsets.all(xxs);

  /// [xs] on every side.
  static const EdgeInsets allXs = EdgeInsets.all(xs);

  /// [sm] on every side.
  static const EdgeInsets allSm = EdgeInsets.all(sm);

  /// [md] on every side.
  static const EdgeInsets allMd = EdgeInsets.all(md);

  /// [lg] on every side.
  static const EdgeInsets allLg = EdgeInsets.all(lg);

  /// [xl] on every side.
  static const EdgeInsets allXl = EdgeInsets.all(xl);

  /// [xxl] on every side.
  static const EdgeInsets allXxl = EdgeInsets.all(xxl);

  /// [xxs] on the left and right.
  static const EdgeInsets horizontalXxs = EdgeInsets.symmetric(horizontal: xxs);

  /// [xs] on the left and right.
  static const EdgeInsets horizontalXs = EdgeInsets.symmetric(horizontal: xs);

  /// [sm] on the left and right.
  static const EdgeInsets horizontalSm = EdgeInsets.symmetric(horizontal: sm);

  /// [md] on the left and right.
  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(horizontal: md);

  /// [lg] on the left and right.
  static const EdgeInsets horizontalLg = EdgeInsets.symmetric(horizontal: lg);

  /// [xl] on the left and right.
  static const EdgeInsets horizontalXl = EdgeInsets.symmetric(horizontal: xl);

  /// [xxl] on the left and right.
  static const EdgeInsets horizontalXxl = EdgeInsets.symmetric(horizontal: xxl);

  /// [xxs] on the top and bottom.
  static const EdgeInsets verticalXxs = EdgeInsets.symmetric(vertical: xxs);

  /// [xs] on the top and bottom.
  static const EdgeInsets verticalXs = EdgeInsets.symmetric(vertical: xs);

  /// [sm] on the top and bottom.
  static const EdgeInsets verticalSm = EdgeInsets.symmetric(vertical: sm);

  /// [md] on the top and bottom.
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(vertical: md);

  /// [lg] on the top and bottom.
  static const EdgeInsets verticalLg = EdgeInsets.symmetric(vertical: lg);

  /// [xl] on the top and bottom.
  static const EdgeInsets verticalXl = EdgeInsets.symmetric(vertical: xl);

  /// [xxl] on the top and bottom.
  static const EdgeInsets verticalXxl = EdgeInsets.symmetric(vertical: xxl);

  /// Default padding around the content of a screen ([lg] on every side).
  static const EdgeInsets screen = EdgeInsets.all(lg);
}
