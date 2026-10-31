import 'package:flutter/material.dart';

import '../../theme/symphony_radius.dart';
import '../../theme/symphony_spacing.dart';
import 'symphony_loading_indicator.dart';

/// Covers [child] with a translucent barrier and a progress indicator while
/// [isLoading] is true.
///
/// While loading, the child cannot be tapped, focused or reached by screen
/// readers; its state is preserved when [isLoading] toggles.
///
/// ```dart
/// SymphonyLoadingOverlay(
///   isLoading: state.isSaving,
///   message: 'Saving…',
///   child: const ProfileForm(),
/// );
/// ```
class SymphonyLoadingOverlay extends StatelessWidget {
  /// Creates a loading overlay.
  const SymphonyLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
    this.barrierColor,
    this.animationDuration = const Duration(milliseconds: 200),
    this.semanticsLabel,
  });

  /// Whether the overlay is displayed and interaction is blocked.
  final bool isLoading;

  /// The content covered by the overlay.
  final Widget child;

  /// Optional text displayed below the indicator.
  final String? message;

  /// Colour of the barrier. Defaults to the theme scrim at 32% opacity.
  final Color? barrierColor;

  /// Duration of the fade in / out animation.
  final Duration animationDuration;

  /// Accessibility label of the indicator. Defaults to [message], or to
  /// `'Loading'` when there is no message.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = SymphonyRadius.of(context);
    final effectiveBarrierColor =
        barrierColor ?? theme.colorScheme.scrim.withAlpha(0x52);

    // An opaque listener stops pointer events from reaching the child without
    // hiding the indicator from screen readers (unlike AbsorbPointer on older
    // Flutter versions).
    final overlay = Listener(
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: effectiveBarrierColor,
        child: Center(
          child: Material(
            color: theme.colorScheme.surface,
            elevation: 6,
            shadowColor: theme.colorScheme.shadow,
            shape: RoundedRectangleBorder(
              borderRadius: radius.largeBorderRadius,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Padding(
                padding: SymphonySpacing.allXl,
                child: IntrinsicWidth(
                  child: SymphonyLoadingIndicator(
                    message: message,
                    semanticsLabel: semanticsLabel,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // The child always stays at the same position in the tree so that its
    // state survives loading phases, and receives the incoming constraints
    // unchanged so the overlay does not alter its layout.
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        ExcludeSemantics(
          excluding: isLoading,
          child: ExcludeFocus(
            excluding: isLoading,
            child: AbsorbPointer(absorbing: isLoading, child: child),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !isLoading,
            child: AnimatedSwitcher(
              duration: animationDuration,
              child: isLoading ? overlay : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}
