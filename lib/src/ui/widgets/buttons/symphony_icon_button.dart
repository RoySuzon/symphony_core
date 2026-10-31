import 'package:flutter/material.dart';

/// Visual style of a [SymphonyIconButton].
enum SymphonyIconButtonVariant {
  /// Icon only, no container (`IconButton`).
  standard,

  /// Filled container, high emphasis (`IconButton.filled`).
  filled,

  /// Tonal container, medium emphasis (`IconButton.filledTonal`).
  tonal,

  /// Outlined container, medium emphasis (`IconButton.outlined`).
  outlined,
}

/// Themed icon button with a mandatory [tooltip] (used as its accessibility
/// label) and a loading state.
///
/// ```dart
/// SymphonyIconButton(
///   icon: Icons.refresh,
///   tooltip: 'Refresh',
///   isLoading: isRefreshing,
///   onPressed: refresh,
/// );
/// ```
class SymphonyIconButton extends StatelessWidget {
  /// Creates an icon button.
  const SymphonyIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.variant = SymphonyIconButtonVariant.standard,
    this.isLoading = false,
    this.iconSize,
    this.color,
    this.loadingSemanticsLabel = 'Loading',
    this.focusNode,
    this.autofocus = false,
  });

  /// Icon displayed in the button.
  final IconData icon;

  /// Tooltip and accessibility label describing the action.
  final String tooltip;

  /// Called when tapped. `null` disables the button.
  final VoidCallback? onPressed;

  /// Visual style.
  final SymphonyIconButtonVariant variant;

  /// Replaces the icon with a progress indicator and ignores taps.
  final bool isLoading;

  /// Size of the icon. Defaults to the Material default (24).
  final double? iconSize;

  /// Colour of the icon. Defaults to the variant colour.
  final Color? color;

  /// Announced by screen readers (after [tooltip]) while [isLoading] is true.
  final String loadingSemanticsLabel;

  /// Focus node of the button.
  final FocusNode? focusNode;

  /// Whether the button requests focus when first built.
  final bool autofocus;

  static const double _defaultIconSize = 24;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? effectiveOnPressed =
        onPressed != null && isLoading ? _ignoreActivation : onPressed;
    final Widget iconWidget = isLoading
        ? _IconButtonSpinner(size: iconSize ?? _defaultIconSize, color: color)
        : Icon(icon);

    final Widget button = switch (variant) {
      SymphonyIconButtonVariant.standard => IconButton(
          icon: iconWidget,
          tooltip: tooltip,
          onPressed: effectiveOnPressed,
          iconSize: iconSize,
          color: color,
          focusNode: focusNode,
          autofocus: autofocus,
        ),
      SymphonyIconButtonVariant.filled => IconButton.filled(
          icon: iconWidget,
          tooltip: tooltip,
          onPressed: effectiveOnPressed,
          iconSize: iconSize,
          color: color,
          focusNode: focusNode,
          autofocus: autofocus,
        ),
      SymphonyIconButtonVariant.tonal => IconButton.filledTonal(
          icon: iconWidget,
          tooltip: tooltip,
          onPressed: effectiveOnPressed,
          iconSize: iconSize,
          color: color,
          focusNode: focusNode,
          autofocus: autofocus,
        ),
      SymphonyIconButtonVariant.outlined => IconButton.outlined(
          icon: iconWidget,
          tooltip: tooltip,
          onPressed: effectiveOnPressed,
          iconSize: iconSize,
          color: color,
          focusNode: focusNode,
          autofocus: autofocus,
        ),
    };

    return Semantics(
      container: isLoading,
      button: isLoading ? true : null,
      enabled: isLoading ? false : null,
      label: isLoading ? tooltip : null,
      value: isLoading ? loadingSemanticsLabel : null,
      excludeSemantics: isLoading,
      child: IgnorePointer(ignoring: isLoading, child: button),
    );
  }

  static void _ignoreActivation() {}
}

class _IconButtonSpinner extends StatelessWidget {
  const _IconButtonSpinner({required this.size, required this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? IconTheme.of(context).color;
    // Slightly smaller than the icon so the ring visually matches its weight.
    return SizedBox.square(
      dimension: size,
      child: Padding(
        padding: EdgeInsets.all(size / 8),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: foreground == null
              ? null
              : AlwaysStoppedAnimation<Color>(foreground),
        ),
      ),
    );
  }
}
