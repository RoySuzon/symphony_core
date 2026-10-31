import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/access_requirement.dart';
import 'symphony_route_scope.dart';

/// A [GoRoute] that can only be opened by users satisfying [access].
///
/// The guard runs as the route's redirect, so it also protects every nested
/// route in [routes]: go_router evaluates the redirects of all matched routes
/// from the outermost to the innermost one and the first redirect wins.
/// Nested routes may declare stricter requirements of their own.
///
/// ```dart
/// GuardedRoute(
///   path: '/admin',
///   access: const AccessRequirement(roles: {'admin'}),
///   builder: (context, state) => const AdminPage(),
///   routes: [
///     // Inherits the admin guard and additionally needs a permission.
///     GuardedRoute(
///       path: 'audit',
///       access: const AccessRequirement(
///         roles: {'admin'},
///         permissions: {'audit.read'},
///       ),
///       deniedRedirect: '/admin',
///       builder: (context, state) => const AuditPage(),
///     ),
///   ],
/// )
/// ```
///
/// When the requirement is not met:
/// * while the session is being restored the user waits on the splash route
///   (`splash?from=<location>`);
/// * signed-out users go to `login?from=<location>` and come back after
///   signing in;
/// * signed-in users lacking roles or permissions go to [deniedRedirect],
///   else to `SymphonyRoutePaths.unauthorized`, else to home.
///
/// When access is granted, the optional application [appRedirect] runs.
///
/// Guards read the access snapshot and the configured route paths from the
/// router built by `SymphonyRouter` (`create`, `custom` or a GoRouter using
/// `SymphonyRouter.buildRedirect`). Inside any other GoRouter they fall back
/// to `accessContextProvider` of the enclosing `ProviderScope` and the
/// default `SymphonyRoutePaths`; give such a router
/// `refreshListenable: SymphonyRouter.accessRefreshListenable(ref)` so the
/// guards also re-run when the access changes.
///
/// When the access changes, go_router 13 and later only re-run the redirects
/// of the location below the pages opened with `GoRouter.push`. The global
/// redirect of `SymphonyRouter` therefore re-checks the guards of the pushed
/// pages as well and closes those the user may no longer see; inside any
/// other GoRouter such pages stay displayed until they are popped.
///
/// go_router only evaluates redirects of `GoRoute`s on its oldest supported
/// versions, so guard the routes inside a `ShellRoute` (or wrap the shell
/// with `AccessGate`) rather than the shell itself.
class GuardedRoute extends GoRoute {
  /// Creates a guarded route.
  ///
  /// [redirect] is the application redirect composed after the guard: it is
  /// only evaluated once the guard granted access. One of [builder],
  /// [pageBuilder] or [redirect] must be provided.
  GuardedRoute({
    required super.path,
    super.name,
    super.builder,
    super.pageBuilder,
    super.parentNavigatorKey,
    super.routes,
    this.access = AccessRequirement.authenticated,
    this.deniedRedirect,
    GoRouterRedirect? redirect,
  })  : assert(
          builder != null || pageBuilder != null || redirect != null,
          'GuardedRoute needs a builder, a pageBuilder or a redirect.',
        ),
        appRedirect = redirect,
        super(redirect: _guard(access, deniedRedirect, redirect));

  /// Who may open this route and every route nested in it. Defaults to any
  /// signed-in user.
  final AccessRequirement access;

  /// Where signed-in users lacking [access] are sent. Defaults to
  /// `SymphonyRoutePaths.unauthorized`, or home when that is `null`.
  final String? deniedRedirect;

  /// The application redirect evaluated after the guard granted access.
  final GoRouterRedirect? appRedirect;

  static GoRouterRedirect _guard(
    AccessRequirement access,
    String? deniedRedirect,
    GoRouterRedirect? appRedirect,
  ) {
    return (BuildContext context, GoRouterState state) {
      final scope = SymphonyRouteScope.of(context);
      final target = scope.resolver.resolveGuard(
        scope.readAccess(),
        state.uri,
        requirement: access,
        deniedRedirect: deniedRedirect,
      );
      if (target != null) return target;
      return appRedirect?.call(context, state);
    };
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<AccessRequirement>('access', access))
      ..add(
        StringProperty('deniedRedirect', deniedRedirect, defaultValue: null),
      );
  }
}

/// A [GoRoute] reserved to signed-out users, such as sign-in, registration
/// or password recovery pages.
///
/// Signed-in users opening it are sent to [authenticatedRedirect] when given,
/// otherwise to the location remembered in the redirect parameter
/// (`/login?from=/orders` → `/orders`), otherwise to home. The guard also
/// applies to the nested [routes].
///
/// ```dart
/// GuestRoute(
///   path: '/login',
///   builder: (context, state) => const LoginPage(),
/// )
/// ```
///
/// The login route is always guest-only for the global redirect of
/// `SymphonyRouter`; [GuestRoute] makes any other route guest-only without
/// listing it in `SymphonyRoutePaths.guestOnlyPaths`.
class GuestRoute extends GoRoute {
  /// Creates a guest-only route.
  ///
  /// [redirect] is the application redirect composed after the guard: it is
  /// only evaluated for users allowed on the route. One of [builder],
  /// [pageBuilder] or [redirect] must be provided.
  GuestRoute({
    required super.path,
    super.name,
    super.builder,
    super.pageBuilder,
    super.parentNavigatorKey,
    super.routes,
    this.authenticatedRedirect,
    GoRouterRedirect? redirect,
  })  : assert(
          builder != null || pageBuilder != null || redirect != null,
          'GuestRoute needs a builder, a pageBuilder or a redirect.',
        ),
        appRedirect = redirect,
        super(redirect: _guard(authenticatedRedirect, redirect));

  /// Where signed-in users are sent instead of the remembered location or
  /// home.
  final String? authenticatedRedirect;

  /// The application redirect evaluated for users allowed on the route.
  final GoRouterRedirect? appRedirect;

  static GoRouterRedirect _guard(
    String? authenticatedRedirect,
    GoRouterRedirect? appRedirect,
  ) {
    return (BuildContext context, GoRouterState state) {
      final scope = SymphonyRouteScope.of(context);
      final target = scope.resolver.resolveGuest(
        scope.readAccess(),
        state.uri,
        authenticatedRedirect: authenticatedRedirect,
      );
      if (target != null) return target;
      return appRedirect?.call(context, state);
    };
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      StringProperty(
        'authenticatedRedirect',
        authenticatedRedirect,
        defaultValue: null,
      ),
    );
  }
}
