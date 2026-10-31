import 'package:flutter/material.dart';

import '../../../core/error/failure.dart';
import '../../theme/symphony_colors.dart';
import '../../theme/symphony_radius.dart';
import '../../theme/symphony_spacing.dart';

/// Semantic type of a snack bar shown with [SymphonySnackbar].
enum SymphonySnackbarType {
  /// Neutral information (uses `SymphonyColors.info`).
  info,

  /// Positive outcome (uses `SymphonyColors.success`).
  success,

  /// Something needs attention (uses `SymphonyColors.warning`).
  warning,

  /// An operation failed (uses `ColorScheme.error`).
  error,
}

/// Shows floating, themed snack bars through the nearest
/// [ScaffoldMessenger] (provided by `MaterialApp`; `ScaffoldMessenger.of`
/// throws when there is none).
///
/// ```dart
/// SymphonySnackbar.success(context, 'Profile saved');
/// SymphonySnackbar.showFailure(
///   context,
///   failure,
///   actionLabel: 'Retry',
///   onAction: reload,
/// );
/// ```
///
/// The snack bar currently displayed (if any) is hidden first and the snack
/// bars still waiting in the queue are discarded
/// (`ScaffoldMessengerState.clearSnackBars`), so feedback is never queued
/// behind stale messages. Colours come from [SymphonyColors] and the theme
/// [ColorScheme]. Each method returns the snack bar controller, whose
/// `closed` future completes when it disappears (the `closed` future of a
/// snack bar discarded before it was displayed never completes, as with
/// `clearSnackBars`).
///
/// Note: on recent Flutter versions a snack bar with an action stays visible
/// until it is dismissed (framework default), which is why a close icon is
/// shown by default in that case.
abstract final class SymphonySnackbar {
  static const Duration _defaultDuration = Duration(seconds: 4);
  static const Duration _errorDuration = Duration(seconds: 6);

  /// Shows [message] styled according to [type].
  ///
  /// [actionLabel] adds an action button calling [onAction]. [duration]
  /// defaults to 4 seconds (6 seconds for errors). [showCloseIcon] defaults to
  /// `true` when an action is provided.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    String message, {
    SymphonySnackbarType type = SymphonySnackbarType.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
    bool showIcon = true,
    bool? showCloseIcon,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    final palette = _paletteFor(type, theme);
    final radius = SymphonyRadius.of(context);
    final textStyle =
        (theme.snackBarTheme.contentTextStyle ?? theme.textTheme.bodyMedium)
            ?.copyWith(color: palette.foreground);

    // Hides the current snack bar and drops the queued ones: with
    // hideCurrentSnackBar alone, a message shown while the previous one is
    // still hiding would wait behind every intermediate (stale) message.
    messenger.clearSnackBars();
    return messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: <Widget>[
            if (showIcon) ...<Widget>[
              Icon(iconFor(type), color: palette.foreground, size: 20),
              const SizedBox(width: SymphonySpacing.md),
            ],
            Expanded(child: Text(message, style: textStyle)),
          ],
        ),
        backgroundColor: palette.background,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius.smallBorderRadius),
        duration: duration ??
            (type == SymphonySnackbarType.error
                ? _errorDuration
                : _defaultDuration),
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: palette.foreground,
                onPressed: onAction ?? _noop,
              ),
        showCloseIcon: showCloseIcon ?? actionLabel != null,
        closeIconColor: palette.foreground,
      ),
    );
  }

  /// Shows a [SymphonySnackbarType.success] snack bar.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) =>
      show(
        context,
        message,
        type: SymphonySnackbarType.success,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  /// Shows a [SymphonySnackbarType.error] snack bar.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) =>
      show(
        context,
        message,
        type: SymphonySnackbarType.error,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  /// Shows a [SymphonySnackbarType.warning] snack bar.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> warning(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) =>
      show(
        context,
        message,
        type: SymphonySnackbarType.warning,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  /// Shows a [SymphonySnackbarType.info] snack bar.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> info(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) =>
      show(
        context,
        message,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  /// Shows the user facing message of [failure] as an error snack bar.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showFailure(
    BuildContext context,
    Failure failure, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) =>
      error(
        context,
        failure.message,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  /// The icon displayed for [type].
  static IconData iconFor(SymphonySnackbarType type) => switch (type) {
        SymphonySnackbarType.info => Icons.info_outline,
        SymphonySnackbarType.success => Icons.check_circle_outline,
        SymphonySnackbarType.warning => Icons.warning_amber_rounded,
        SymphonySnackbarType.error => Icons.error_outline,
      };

  static ({Color background, Color foreground}) _paletteFor(
    SymphonySnackbarType type,
    ThemeData theme,
  ) {
    final colors = theme.extension<SymphonyColors>() ??
        SymphonyColors.fallback(theme.brightness);
    final scheme = theme.colorScheme;
    return switch (type) {
      SymphonySnackbarType.info => (
          background: colors.info,
          foreground: colors.onInfo,
        ),
      SymphonySnackbarType.success => (
          background: colors.success,
          foreground: colors.onSuccess,
        ),
      SymphonySnackbarType.warning => (
          background: colors.warning,
          foreground: colors.onWarning,
        ),
      SymphonySnackbarType.error => (
          background: scheme.error,
          foreground: scheme.onError,
        ),
    };
  }

  static void _noop() {}
}
