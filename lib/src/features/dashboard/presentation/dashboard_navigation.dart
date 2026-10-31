import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../domain/dashboard_item.dart';

/// Navigates to the destination of [item] the way the dashboard does, and
/// returns whether a navigation was started.
///
/// * With a `GoRouter` above [context]: [DashboardItem.routeName] is opened
///   with `goNamed` / `pushNamed` (with the item's path and query parameters),
///   otherwise [DashboardItem.route] with `go` / `push`, according to
///   [DashboardItem.navigation]. [DashboardItem.extra] is forwarded.
/// * Without GoRouter (fallback): [DashboardItem.routeLocation] is pushed as
///   a named route of the nearest `Navigator`
///   (`Navigator.pushNamed(context, location, arguments: extra)`), which
///   suits apps using `MaterialApp(routes: ...)` or `onGenerateRoute`.
///   [DashboardItem.routeName] alone cannot be resolved without GoRouter.
///
/// Returns `false` without doing anything when the item has no destination.
/// When it has one that cannot be opened (no GoRouter and no usable
/// `Navigator` route), the problem is reported with
/// [FlutterError.reportError] — the app keeps running — and `false` is
/// returned. Apps with another routing solution handle navigation
/// themselves through the dashboard's `onItemSelected` callback.
///
/// Errors raised by the router itself (for example an unknown route name)
/// propagate unchanged, exactly like a direct router call.
bool navigateToDashboardItem(BuildContext context, DashboardItem item) {
  if (!item.hasDestination) return false;
  final routeName = item.routeName;
  final router = GoRouter.maybeOf(context);

  if (router != null && routeName != null && routeName.isNotEmpty) {
    switch (item.navigation) {
      case DashboardNavigation.go:
        router.goNamed(
          routeName,
          pathParameters: item.pathParameters,
          queryParameters: item.routeQueryParameters,
          extra: item.extra,
        );
      case DashboardNavigation.push:
        unawaited(
          router.pushNamed<Object?>(
            routeName,
            pathParameters: item.pathParameters,
            queryParameters: item.routeQueryParameters,
            extra: item.extra,
          ),
        );
    }
    return true;
  }

  // Only computed when needed: a routeName navigation never parses [route].
  final location = item.routeLocation;
  if (router != null && location != null) {
    switch (item.navigation) {
      case DashboardNavigation.go:
        router.go(location, extra: item.extra);
      case DashboardNavigation.push:
        unawaited(router.push<Object?>(location, extra: item.extra));
    }
    return true;
  }

  final navigator = Navigator.maybeOf(context);
  if (navigator != null && location != null) {
    unawaited(navigator.pushNamed<Object?>(location, arguments: item.extra));
    return true;
  }

  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary(
          'Cannot open the destination of the dashboard item "${item.id}".',
        ),
        ErrorDescription(
          navigator == null
              ? 'No GoRouter and no Navigator were found above the dashboard.'
              : 'No GoRouter was found above the dashboard and the item has '
                  'no route location (a routeName requires GoRouter).',
        ),
        ErrorHint(
          'Use MaterialApp.router with a GoRouter, give the item a route '
          'registered as a Navigator named route, or handle the navigation '
          'with the onItemSelected callback of the dashboard.',
        ),
      ]),
      library: 'symphony_core',
      context: ErrorDescription('while opening a dashboard item'),
    ),
  );
  return false;
}
