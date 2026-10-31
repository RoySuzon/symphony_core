import 'package:flutter/material.dart';

import 'symphony_auth_layout.dart';
import 'symphony_login_form.dart';

/// Ready-made sign-in screen: a [SymphonyAuthLayout] around a
/// [SymphonyLoginForm].
///
/// Pass a configured [form] to customize the fields, texts and callbacks:
///
/// ```dart
/// SymphonyLoginScreen(
///   logo: const FlutterLogo(size: 72),
///   title: 'Welcome to Acme',
///   form: SymphonyLoginForm(
///     onForgotPassword: () => context.push('/forgot-password'),
///     onRegister: () => context.push('/register'),
///   ),
/// );
/// ```
///
/// The screen never navigates by itself: route redirects (or
/// [SymphonyLoginForm.onSuccess]) take the user further once signed in.
class SymphonyLoginScreen extends StatelessWidget {
  /// Creates a sign-in screen.
  const SymphonyLoginScreen({
    super.key,
    this.form,
    this.logo,
    this.title = 'Welcome back',
    this.subtitle = 'Sign in to continue',
    this.header,
    this.footer,
    this.appBar,
    this.backgroundColor,
    this.maxWidth = 440,
    this.padding = const EdgeInsets.all(24),
  });

  /// The form. Defaults to a `SymphonyLoginForm()` with default settings.
  final Widget? form;

  /// Widget displayed at the top (an image, an icon...).
  final Widget? logo;

  /// Headline. `null` hides it.
  final String? title;

  /// Text below the [title]. `null` hides it.
  final String? subtitle;

  /// Widget displayed above the form.
  final Widget? header;

  /// Widget displayed below the form.
  final Widget? footer;

  /// Optional app bar.
  final PreferredSizeWidget? appBar;

  /// Background color. Defaults to the theme's scaffold background.
  final Color? backgroundColor;

  /// Maximum width of the content column.
  final double maxWidth;

  /// Padding around the content column.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SymphonyAuthLayout(
      logo: logo,
      title: title,
      subtitle: subtitle,
      header: header,
      footer: footer,
      appBar: appBar,
      backgroundColor: backgroundColor,
      maxWidth: maxWidth,
      padding: padding,
      child: form ?? const SymphonyLoginForm(),
    );
  }
}
