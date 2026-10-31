import 'package:flutter/material.dart';

/// Responsive page layout for authentication screens: a [Scaffold] with a
/// centered, width-constrained and scrollable column holding an optional
/// logo, title, subtitle, header, the [child] (usually a form) and a footer.
///
/// Used by `SymphonyLoginScreen`; use it directly to build registration or
/// password recovery screens with the same look:
///
/// ```dart
/// SymphonyAuthLayout(
///   title: 'Create your account',
///   child: SymphonyRegisterForm(onSignIn: () => context.go('/login')),
/// );
/// ```
class SymphonyAuthLayout extends StatelessWidget {
  /// Creates the layout.
  const SymphonyAuthLayout({
    super.key,
    required this.child,
    this.logo,
    this.title,
    this.subtitle,
    this.header,
    this.footer,
    this.appBar,
    this.backgroundColor,
    this.maxWidth = 440,
    this.padding = const EdgeInsets.all(24),
  });

  /// Main content, usually a form.
  final Widget child;

  /// Widget displayed at the top (an image, an icon...).
  final Widget? logo;

  /// Headline below the [logo].
  final String? title;

  /// Text below the [title].
  final String? subtitle;

  /// Widget displayed above the [child] (an announcement, a language
  /// picker...).
  final Widget? header;

  /// Widget displayed below the [child] (legal links, version...).
  final Widget? footer;

  /// Optional app bar (for example with a back button).
  final PreferredSizeWidget? appBar;

  /// Background color. Defaults to the theme's scaffold background.
  final Color? backgroundColor;

  /// Maximum width of the content column.
  final double maxWidth;

  /// Padding around the content column.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = this.logo;
    final title = this.title;
    final subtitle = this.subtitle;
    final header = this.header;
    final footer = this.footer;
    return Scaffold(
      appBar: appBar,
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (logo != null) ...<Widget>[
                    Center(child: logo),
                    const SizedBox(height: 24),
                  ],
                  if (title != null)
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (title != null || subtitle != null)
                    const SizedBox(height: 32),
                  if (header != null) ...<Widget>[
                    header,
                    const SizedBox(height: 16),
                  ],
                  child,
                  if (footer != null) ...<Widget>[
                    const SizedBox(height: 24),
                    footer,
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
