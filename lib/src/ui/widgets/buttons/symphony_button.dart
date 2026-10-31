import 'package:flutter/material.dart';

/// Visual style of a [SymphonyButton].
enum SymphonyButtonVariant {
  /// Filled, high emphasis (`FilledButton`).
  primary,

  /// Tonal, medium emphasis (`FilledButton.tonal`).
  secondary,

  /// Outlined, medium emphasis (`OutlinedButton`).
  outlined,

  /// Text only, low emphasis (`TextButton`).
  text,

  /// Destructive action: a filled button using the theme error colours.
  danger,
}

/// Size of a [SymphonyButton].
enum SymphonyButtonSize {
  /// Compact button, 36 logical pixels high.
  small(36),

  /// Default button, 44 logical pixels high.
  medium(44),

  /// Large touch target, 52 logical pixels high.
  large(52);

  const SymphonyButtonSize(this.minHeight);

  /// Minimum height of the visible button. On touch platforms the tap
  /// target is still padded to 48 logical pixels by Material.
  final double minHeight;
}

/// Themed button with variants, sizes, optional icons, a loading state and
/// a full-width mode.
///
/// The button follows the ambient button themes (shape, colours), so it
/// adapts to `SymphonyTheme` as well as to any custom application theme.
///
/// ```dart
/// SymphonyButton(
///   label: 'Sign in',
///   icon: Icons.login,
///   isLoading: controller.isSubmitting,
///   expanded: true,
///   onPressed: controller.submit,
/// );
/// ```
///
/// While [isLoading] is `true` the label is replaced by a progress indicator
/// drawn in the foreground colour, the button keeps its size and colours, and
/// taps are ignored. Screen readers announce the [label] together with
/// [loadingSemanticsLabel].
class SymphonyButton extends StatelessWidget {
  /// Creates a button.
  const SymphonyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SymphonyButtonVariant.primary,
    this.size = SymphonyButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.expanded = false,
    this.trailingIcon,
    this.tooltip,
    this.loadingSemanticsLabel = 'Loading',
    this.style,
    this.focusNode,
    this.autofocus = false,
  });

  /// Text of the button.
  final String label;

  /// Called when tapped. `null` disables the button.
  final VoidCallback? onPressed;

  /// Visual style.
  final SymphonyButtonVariant variant;

  /// Size.
  final SymphonyButtonSize size;

  /// Optional leading icon.
  final IconData? icon;

  /// Shows a progress indicator and ignores taps.
  final bool isLoading;

  /// Expands to the available width.
  final bool expanded;

  /// Optional icon displayed after the label.
  final IconData? trailingIcon;

  /// Optional tooltip displayed on long press / hover.
  final String? tooltip;

  /// Announced by screen readers (after [label]) while [isLoading] is true.
  final String loadingSemanticsLabel;

  /// Style overrides merged on top of the variant and size styles.
  final ButtonStyle? style;

  /// Focus node of the button.
  final FocusNode? focusNode;

  /// Whether the button requests focus when first built.
  final bool autofocus;

  bool get _enabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = _ButtonMetrics.of(size);
    final baseStyle = _baseStyle(theme, metrics);
    final effectiveStyle = style?.merge(baseStyle) ?? baseStyle;
    // While loading, keep the button enabled (same colours, focus kept) but
    // swallow activations; pointer events are blocked by the IgnorePointer.
    final VoidCallback? effectiveOnPressed =
        _enabled && isLoading ? _ignoreActivation : onPressed;
    final content = _ButtonContent(
      label: label,
      icon: icon,
      trailingIcon: trailingIcon,
      isLoading: isLoading,
      metrics: metrics,
    );

    Widget button = switch (variant) {
      SymphonyButtonVariant.primary ||
      SymphonyButtonVariant.danger => FilledButton(
        onPressed: effectiveOnPressed,
        style: effectiveStyle,
        focusNode: focusNode,
        autofocus: autofocus,
        child: content,
      ),
      SymphonyButtonVariant.secondary => FilledButton.tonal(
        onPressed: effectiveOnPressed,
        style: effectiveStyle,
        focusNode: focusNode,
        autofocus: autofocus,
        child: content,
      ),
      SymphonyButtonVariant.outlined => OutlinedButton(
        onPressed: effectiveOnPressed,
        style: effectiveStyle,
        focusNode: focusNode,
        autofocus: autofocus,
        child: content,
      ),
      SymphonyButtonVariant.text => TextButton(
        onPressed: effectiveOnPressed,
        style: effectiveStyle,
        focusNode: focusNode,
        autofocus: autofocus,
        child: content,
      ),
    };

    // The wrappers are always present so that toggling [isLoading] keeps the
    // button element (and its focus / hover state) alive.
    button = Semantics(
      container: isLoading,
      button: isLoading ? true : null,
      enabled: isLoading ? false : null,
      label: isLoading ? label : null,
      value: isLoading ? loadingSemanticsLabel : null,
      excludeSemantics: isLoading,
      child: IgnorePointer(ignoring: isLoading, child: button),
    );

    final tooltipMessage = tooltip;
    if (tooltipMessage != null) {
      button = Tooltip(message: tooltipMessage, child: button);
    }
    if (expanded) {
      button = SizedBox(width: double.infinity, child: button);
    }
    return button;
  }

  ButtonStyle _baseStyle(ThemeData theme, _ButtonMetrics metrics) {
    final textTheme = theme.textTheme;
    final textStyle = switch (size) {
      SymphonyButtonSize.small => textTheme.labelMedium,
      SymphonyButtonSize.medium => textTheme.labelLarge,
      SymphonyButtonSize.large => textTheme.titleMedium,
    };
    final minimumSize = Size(metrics.minWidth, size.minHeight);
    final padding = EdgeInsets.symmetric(
      horizontal:
          variant == SymphonyButtonVariant.text
              ? metrics.textHorizontalPadding
              : metrics.horizontalPadding,
      vertical: metrics.verticalPadding,
    );

    return switch (variant) {
      SymphonyButtonVariant.primary ||
      SymphonyButtonVariant.secondary => FilledButton.styleFrom(
        minimumSize: minimumSize,
        padding: padding,
        textStyle: textStyle,
      ),
      SymphonyButtonVariant.danger => FilledButton.styleFrom(
        backgroundColor: theme.colorScheme.error,
        foregroundColor: theme.colorScheme.onError,
        minimumSize: minimumSize,
        padding: padding,
        textStyle: textStyle,
      ),
      SymphonyButtonVariant.outlined => OutlinedButton.styleFrom(
        minimumSize: minimumSize,
        padding: padding,
        textStyle: textStyle,
      ),
      SymphonyButtonVariant.text => TextButton.styleFrom(
        minimumSize: minimumSize,
        padding: padding,
        textStyle: textStyle,
      ),
    };
  }

  static void _ignoreActivation() {}
}

/// Label, icons and loading indicator of a [SymphonyButton].
class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.trailingIcon,
    required this.isLoading,
    required this.metrics,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final _ButtonMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final leading = icon;
    final trailing = trailingIcon;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
    final Widget content =
        leading == null && trailing == null
            ? text
            : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  Icon(leading, size: metrics.iconSize),
                  SizedBox(width: metrics.gap),
                ],
                Flexible(child: text),
                if (trailing != null) ...<Widget>[
                  SizedBox(width: metrics.gap),
                  Icon(trailing, size: metrics.iconSize),
                ],
              ],
            );
    if (!isLoading) return content;

    // The invisible content keeps the button width stable while loading.
    final foreground =
        IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Opacity(opacity: 0, child: content),
        SizedBox.square(
          dimension: metrics.iconSize,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor:
                foreground == null
                    ? null
                    : AlwaysStoppedAnimation<Color>(foreground),
          ),
        ),
      ],
    );
  }
}

/// Dimensions of a [SymphonyButtonSize].
class _ButtonMetrics {
  const _ButtonMetrics({
    required this.minWidth,
    required this.horizontalPadding,
    required this.textHorizontalPadding,
    required this.verticalPadding,
    required this.iconSize,
    required this.gap,
  });

  static _ButtonMetrics of(SymphonyButtonSize size) => switch (size) {
    SymphonyButtonSize.small => const _ButtonMetrics(
      minWidth: 48,
      horizontalPadding: 12,
      textHorizontalPadding: 8,
      verticalPadding: 6,
      iconSize: 16,
      gap: 6,
    ),
    SymphonyButtonSize.medium => const _ButtonMetrics(
      minWidth: 64,
      horizontalPadding: 20,
      textHorizontalPadding: 12,
      verticalPadding: 10,
      iconSize: 18,
      gap: 8,
    ),
    SymphonyButtonSize.large => const _ButtonMetrics(
      minWidth: 72,
      horizontalPadding: 28,
      textHorizontalPadding: 16,
      verticalPadding: 14,
      iconSize: 20,
      gap: 8,
    ),
  };

  final double minWidth;
  final double horizontalPadding;
  final double textHorizontalPadding;
  final double verticalPadding;
  final double iconSize;
  final double gap;
}
