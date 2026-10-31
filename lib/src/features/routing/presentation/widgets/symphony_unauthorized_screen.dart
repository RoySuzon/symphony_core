import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../ui/widgets/buttons/symphony_button.dart';
import 'routing_message_layout.dart';

/// Page shown to signed-in users who lack the roles or permissions of a
/// guarded route.
///
/// Register it at `SymphonyRoutePaths.unauthorized` (`/unauthorized` by
/// default):
///
/// ```dart
/// GoRoute(
///   path: '/unauthorized',
///   builder: (context, state) => SymphonyUnauthorizedScreen(
///     actions: [
///       Consumer(
///         builder: (context, ref, _) => SymphonyButton(
///           label: 'Sign out',
///           variant: SymphonyButtonVariant.outlined,
///           onPressed: () =>
///               ref.read(authControllerProvider.notifier).logout(),
///         ),
///       ),
///     ],
///   ),
/// )
/// ```
///
/// Every text can be overridden to localize the screen.
class SymphonyUnauthorizedScreen extends StatelessWidget {
  /// Creates the unauthorized screen.
  const SymphonyUnauthorizedScreen({
    super.key,
    this.title = 'Access denied',
    this.message = "You don't have permission to view this page.",
    this.homeLabel = 'Go to home',
    this.homeLocation = '/',
    this.icon = Icons.lock_outline,
    this.onGoHome,
    this.actions = const <Widget>[],
  });

  /// Headline.
  final String title;

  /// Description shown below the headline.
  final String message;

  /// Label of the home button.
  final String homeLabel;

  /// Location opened by the home button when [onGoHome] is `null`.
  final String homeLocation;

  /// Illustration icon.
  final IconData icon;

  /// Called by the home button. Defaults to `GoRouter.go(homeLocation)`; the
  /// button is hidden when neither is available.
  final VoidCallback? onGoHome;

  /// Extra actions shown after the home button (for example a sign-out
  /// button to switch accounts).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final goHome = onGoHome ?? _routerGoHome(context);
    return RoutingMessageLayout(
      icon: icon,
      iconColor: Theme.of(context).colorScheme.error,
      title: title,
      message: message,
      actions: <Widget>[
        if (goHome != null)
          SymphonyButton(
            label: homeLabel,
            icon: Icons.home_outlined,
            onPressed: goHome,
          ),
        ...actions,
      ],
    );
  }

  VoidCallback? _routerGoHome(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return null;
    return () => router.go(homeLocation);
  }
}
