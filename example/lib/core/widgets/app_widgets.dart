import 'package:flutter/material.dart';
import 'package:symphony_core/symphony_core.dart';

import '../utils/formatters.dart';

/// Standard page of the example: an [AppBar] and a width-constrained body.
///
/// With [scrollable] the body scrolls as a whole; otherwise it fills the
/// available height (lists, loading and error states).
class AppPage extends StatelessWidget {
  /// Creates a page.
  const AppPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    this.floatingActionButton,
    this.scrollable = false,
    this.maxWidth = 960,
    this.padding = const EdgeInsets.all(16),
  });

  /// App bar title.
  final String title;

  /// Page content.
  final Widget body;

  /// App bar actions.
  final List<Widget> actions;

  /// Optional floating action button.
  final Widget? floatingActionButton;

  /// Whether the whole body scrolls.
  final bool scrollable;

  /// Maximum width of the content.
  final double maxWidth;

  /// Padding around the content.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = SymphonyContentConstraint(
      maxWidth: maxWidth,
      padding: scrollable ? null : padding,
      child: body,
    );
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: scrollable
            ? SingleChildScrollView(padding: padding, child: content)
            : content,
      ),
    );
  }
}

/// A titled card grouping related content.
class SectionCard extends StatelessWidget {
  /// Creates a section.
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  /// Section title.
  final String title;

  /// Optional description below the title.
  final String? subtitle;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional widget at the end of the header.
  final Widget? trailing;

  /// Section content.
  final Widget child;

  /// Inner padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    final icon = this.icon;
    final trailing = this.trailing;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: SymphonySpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleMedium),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: SymphonySpacing.lg),
            child,
          ],
        ),
      ),
    );
  }
}

/// A label / value line.
class InfoRow extends StatelessWidget {
  /// Creates a row.
  const InfoRow({super.key, required this.label, required this.value});

  /// Label (left).
  final String label;

  /// Value (right).
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SymphonySpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: SymphonySpacing.md),
          Expanded(
            flex: 3,
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// The example's logo.
class AppLogo extends StatelessWidget {
  /// Creates the logo.
  const AppLogo({super.key, this.size = 72});

  /// Diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[scheme.primary, scheme.tertiary],
        ),
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        color: scheme.onPrimary,
        size: size * 0.55,
      ),
    );
  }
}

/// A circular avatar with the user's initials.
class UserAvatar extends StatelessWidget {
  /// Creates an avatar.
  const UserAvatar({super.key, required this.name, this.radius = 20});

  /// Name used for the initials.
  final String? name;

  /// Radius.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(
        Formatters.initials(name),
        style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Small rounded label (roles, permissions, statuses).
class TagChip extends StatelessWidget {
  /// Creates a tag.
  const TagChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
  });

  /// Text.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Accent color (defaults to the secondary container color).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color;
    final background = accent?.withAlpha(36) ?? scheme.secondaryContainer;
    final foreground = accent ?? scheme.onSecondaryContainer;
    final icon = this.icon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(SymphonyRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: SymphonySpacing.xs),
          ],
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
