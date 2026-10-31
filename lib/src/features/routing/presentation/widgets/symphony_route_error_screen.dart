import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../ui/widgets/buttons/symphony_button.dart';
import 'routing_message_layout.dart';

/// Page shown when a location cannot be resolved: unknown routes, redirect
/// loops or too many redirects.
///
/// `SymphonyRouter` uses it as the default `errorBuilder`. To customize the
/// texts (for example to localize them) pass your own builder:
///
/// ```dart
/// SymphonyRouter.create(
///   ref,
///   routes: routes,
///   errorBuilder: (context, state) => SymphonyRouteErrorScreen(
///     error: state.error,
///     location: state.uri.toString(),
///     title: 'Page introuvable',
///     message: "Cette page n'existe pas.",
///     homeLabel: "Retour à l'accueil",
///   ),
/// );
/// ```
class SymphonyRouteErrorScreen extends StatelessWidget {
  /// Creates the error screen.
  const SymphonyRouteErrorScreen({
    super.key,
    this.error,
    this.location,
    this.homeLocation = '/',
    this.title = 'Page not found',
    this.message =
        'The page you are looking for does not exist or has been moved.',
    this.locationLabel = 'Requested location',
    this.homeLabel = 'Go to home',
    this.icon = Icons.explore_off_outlined,
    this.showErrorDetails = kDebugMode,
    this.onGoHome,
  });

  /// The routing error (`GoRouterState.error`), shown when
  /// [showErrorDetails] is true.
  final Object? error;

  /// The location that failed (`GoRouterState.uri`). Hidden when `null`.
  final String? location;

  /// Location opened by the home button when [onGoHome] is `null`.
  final String homeLocation;

  /// Headline.
  final String title;

  /// Description shown below the headline.
  final String message;

  /// Label displayed above [location].
  final String locationLabel;

  /// Label of the home button.
  final String homeLabel;

  /// Illustration icon.
  final IconData icon;

  /// Whether the technical [error] description is displayed. Defaults to
  /// debug builds only.
  final bool showErrorDetails;

  /// Called by the home button. Defaults to `GoRouter.go(homeLocation)`; the
  /// button is hidden when neither is available.
  final VoidCallback? onGoHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failedLocation = location;
    final details = error;
    final goHome = onGoHome ?? _routerGoHome(context);
    return RoutingMessageLayout(
      icon: icon,
      iconColor: scheme.error,
      title: title,
      message: message,
      details: <Widget>[
        if (failedLocation != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            locationLabel,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            failedLocation,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ],
        if (showErrorDetails && details != null) ...<Widget>[
          const SizedBox(height: 16),
          SelectableText(
            details.toString(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
      actions: <Widget>[
        if (goHome != null)
          SymphonyButton(
            label: homeLabel,
            icon: Icons.home_outlined,
            onPressed: goHome,
          ),
      ],
    );
  }

  VoidCallback? _routerGoHome(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return null;
    return () => router.go(homeLocation);
  }
}
