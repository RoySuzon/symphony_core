import 'package:flutter/material.dart';

import '../../theme/symphony_spacing.dart';
import '../buttons/symphony_button.dart';

/// Placeholder shown when a list or screen has no content.
///
/// ```dart
/// SymphonyEmptyState(
///   icon: Icons.receipt_long_outlined,
///   title: 'No invoices yet',
///   message: 'Invoices you create will appear here.',
///   actionLabel: 'Create invoice',
///   onAction: openEditor,
/// );
/// ```
///
/// The action button is shown when both [actionLabel] and [onAction] are
/// provided; pass [action] to display a custom widget instead.
class SymphonyEmptyState extends StatelessWidget {
  /// Creates an empty state.
  const SymphonyEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.actionIcon,
    this.action,
  });

  /// Headline.
  final String title;

  /// Optional description.
  final String? message;

  /// Illustration icon.
  final IconData icon;

  /// Label of the optional action button.
  final String? actionLabel;

  /// Called when the action button is pressed.
  final VoidCallback? onAction;

  /// Uses a smaller layout.
  final bool compact;

  /// Optional leading icon of the action button.
  final IconData? actionIcon;

  /// Custom action widget displayed instead of the default button.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final description = message;
    final label = actionLabel;
    final callback = onAction;
    final Widget? effectiveAction =
        action ??
        (label != null && callback != null
            ? SymphonyButton(
              label: label,
              icon: actionIcon,
              onPressed: callback,
              variant:
                  compact
                      ? SymphonyButtonVariant.text
                      : SymphonyButtonVariant.primary,
              size:
                  compact
                      ? SymphonyButtonSize.small
                      : SymphonyButtonSize.medium,
            )
            : null);

    final Widget illustration =
        compact
            ? Icon(icon, size: 32, color: scheme.onSurfaceVariant)
            : DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: SymphonySpacing.allLg,
                child: Icon(icon, size: 40, color: scheme.onSecondaryContainer),
              ),
            );

    return Center(
      child: SingleChildScrollView(
        padding: compact ? SymphonySpacing.allLg : SymphonySpacing.allXl,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ExcludeSemantics(child: illustration),
              SizedBox(
                height: compact ? SymphonySpacing.sm : SymphonySpacing.lg,
              ),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style:
                      compact
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleLarge,
                ),
              ),
              if (description != null && description.isNotEmpty) ...<Widget>[
                SizedBox(
                  height: compact ? SymphonySpacing.xs : SymphonySpacing.sm,
                ),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: (compact
                          ? theme.textTheme.bodySmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (effectiveAction != null) ...<Widget>[
                SizedBox(
                  height: compact ? SymphonySpacing.sm : SymphonySpacing.xl,
                ),
                effectiveAction,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
