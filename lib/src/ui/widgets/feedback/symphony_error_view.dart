import 'package:flutter/material.dart';

import '../../../core/error/failure.dart';
import '../../theme/symphony_radius.dart';
import '../../theme/symphony_spacing.dart';
import '../buttons/symphony_button.dart';

/// Error display with an icon and title matching the [Failure] type, the
/// failure message and an optional retry action.
///
/// | failure                 | icon                 | default title             |
/// |-------------------------|----------------------|---------------------------|
/// | [NetworkFailure]        | `Icons.wifi_off`     | No internet connection    |
/// | [TimeoutFailure]        | `Icons.timer_off`    | Request timed out         |
/// | [UnauthorizedFailure]   | `Icons.lock_outline` | Session expired           |
/// | [ForbiddenFailure]      | `Icons.block`        | Access denied             |
/// | [NotFoundFailure]       | `Icons.search_off`   | Not found                 |
/// | [ValidationFailure]     | `Icons.rule`         | Invalid input             |
/// | anything else / `null`  | `Icons.error_outline`| Something went wrong      |
///
/// ```dart
/// SymphonyErrorView(
///   failure: failure,
///   onRetry: () => ref.invalidate(ordersProvider),
/// );
/// ```
///
/// Pass [title], [message] and [icon] to override the defaults (for example
/// with localized strings). [compact] renders an inline banner suited to
/// lists and cards.
class SymphonyErrorView extends StatelessWidget {
  /// Creates an error view. Provide a [failure] or a [message].
  const SymphonyErrorView({
    super.key,
    this.failure,
    this.title,
    this.message,
    this.icon,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.compact = false,
    this.retryIcon = Icons.refresh,
  });

  /// Failure to describe. Its message is used when [message] is null.
  final Failure? failure;

  /// Headline. Defaults to [titleFor] the [failure].
  final String? title;

  /// Description. Defaults to the failure message.
  final String? message;

  /// Icon. Defaults to [iconFor] the [failure].
  final IconData? icon;

  /// Called when the retry button is pressed. Hides the button when null.
  final VoidCallback? onRetry;

  /// Label of the retry button.
  final String retryLabel;

  /// Uses a smaller, inline layout.
  final bool compact;

  /// Icon of the retry button. `null` removes it.
  final IconData? retryIcon;

  /// The default icon representing [failure].
  static IconData iconFor(Failure? failure) => switch (failure) {
    NetworkFailure() => Icons.wifi_off,
    TimeoutFailure() => Icons.timer_off,
    UnauthorizedFailure() => Icons.lock_outline,
    ForbiddenFailure() => Icons.block,
    NotFoundFailure() => Icons.search_off,
    ValidationFailure() => Icons.rule,
    _ => Icons.error_outline,
  };

  /// The default (English) title describing [failure].
  static String titleFor(Failure? failure) => switch (failure) {
    NetworkFailure() => 'No internet connection',
    TimeoutFailure() => 'Request timed out',
    UnauthorizedFailure() => 'Session expired',
    ForbiddenFailure() => 'Access denied',
    NotFoundFailure() => 'Not found',
    ValidationFailure() => 'Invalid input',
    _ => 'Something went wrong',
  };

  @override
  Widget build(BuildContext context) {
    final effectiveTitle = title ?? titleFor(failure);
    final effectiveMessage = message ?? failure?.message;
    final effectiveIcon = icon ?? iconFor(failure);
    return Semantics(
      container: true,
      liveRegion: true,
      child:
          compact
              ? _buildCompact(
                context,
                effectiveTitle,
                effectiveMessage,
                effectiveIcon,
              )
              : _buildFull(
                context,
                effectiveTitle,
                effectiveMessage,
                effectiveIcon,
              ),
    );
  }

  Widget _buildFull(
    BuildContext context,
    String title,
    String? message,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final retry = onRetry;
    return Center(
      child: SingleChildScrollView(
        padding: SymphonySpacing.allXl,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: SymphonySpacing.allLg,
                  child: Icon(icon, size: 40, color: scheme.onErrorContainer),
                ),
              ),
              const SizedBox(height: SymphonySpacing.lg),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (message != null && message.isNotEmpty) ...<Widget>[
                const SizedBox(height: SymphonySpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (retry != null) ...<Widget>[
                const SizedBox(height: SymphonySpacing.xl),
                SymphonyButton(
                  label: retryLabel,
                  icon: retryIcon,
                  variant: SymphonyButtonVariant.secondary,
                  onPressed: retry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompact(
    BuildContext context,
    String title,
    String? message,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = SymphonyRadius.of(context);
    final retry = onRetry;
    return Material(
      color: scheme.errorContainer,
      shape: RoundedRectangleBorder(borderRadius: radius.mediumBorderRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SymphonySpacing.md,
          SymphonySpacing.md,
          SymphonySpacing.sm,
          SymphonySpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 24, color: scheme.onErrorContainer),
            const SizedBox(width: SymphonySpacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                  if (message != null && message.isNotEmpty) ...<Widget>[
                    const SizedBox(height: SymphonySpacing.xxs),
                    Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (retry != null) ...<Widget>[
              const SizedBox(width: SymphonySpacing.sm),
              SymphonyButton(
                label: retryLabel,
                variant: SymphonyButtonVariant.text,
                size: SymphonyButtonSize.small,
                onPressed: retry,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
