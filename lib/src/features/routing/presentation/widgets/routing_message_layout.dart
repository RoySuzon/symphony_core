// Internal to the routing module: not exported from the barrel.
import 'package:flutter/material.dart';

/// Full-page layout shared by the routing screens: an icon, a title, a
/// message, optional detail widgets and a row of actions, centered and
/// width-constrained so it reads well on phones, tablets and desktops.
class RoutingMessageLayout extends StatelessWidget {
  /// Creates the layout.
  const RoutingMessageLayout({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor,
    this.details = const <Widget>[],
    this.actions = const <Widget>[],
  });

  /// Illustration icon.
  final IconData icon;

  /// Color of [icon]. Defaults to the color scheme's primary color.
  final Color? iconColor;

  /// Headline.
  final String title;

  /// Description shown below the headline.
  final String message;

  /// Extra widgets shown below the message.
  final List<Widget> details;

  /// Buttons shown at the bottom.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 64, color: iconColor ?? scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  ...details,
                  if (actions.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: actions,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
