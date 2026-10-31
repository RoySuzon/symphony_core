// Internal to the routing module: not exported from the barrel.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/access_context.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/redirect_logic.dart';

/// Access source and redirect rules used by the route guards of one router.
///
/// go_router invokes the top-level redirect and the route-level redirects of
/// a navigation with the same [BuildContext] (the one of the `Router`
/// widget), always top-level first. The top-level redirect built by
/// `SymphonyRouter` therefore [bind]s its scope to that context, and the
/// `GuardedRoute`/`GuestRoute` redirects evaluated right after it find the
/// scope with [of]. This works with and without Riverpod and keeps several
/// routers (or successive routers on the same app) independent.
///
/// The association is weak: it does not keep the context alive.
@immutable
class SymphonyRouteScope {
  /// Creates a scope.
  const SymphonyRouteScope({required this.readAccess, required this.resolver});

  /// Returns the current access snapshot.
  final AccessContext Function() readAccess;

  /// Redirect rules configured for the router.
  final SymphonyRedirectResolver resolver;

  static final Expando<SymphonyRouteScope> _bindings =
      Expando<SymphonyRouteScope>('SymphonyRouteScope');

  /// Associates [scope] with [routerContext], the context go_router passes to
  /// redirect callbacks.
  static void bind(BuildContext routerContext, SymphonyRouteScope scope) {
    _bindings[routerContext] = scope;
  }

  /// The scope bound to [context] by a `SymphonyRouter` redirect.
  ///
  /// When the router was not built by `SymphonyRouter`, falls back to the
  /// `accessContextProvider` of the enclosing `ProviderScope` with the
  /// default `SymphonyRoutePaths`.
  ///
  /// Throws a [StateError] when neither is available.
  static SymphonyRouteScope of(BuildContext context) {
    final bound = _bindings[context];
    if (bound != null) return bound;
    final ProviderContainer container;
    try {
      container = ProviderScope.containerOf(context, listen: false);
    } on StateError {
      throw StateError(
        'GuardedRoute/GuestRoute could not find an access source. Create the '
        'GoRouter with SymphonyRouter.create(ref, ...) or '
        'SymphonyRouter.custom(readAccess: ...), pass '
        'SymphonyRouter.buildRedirect(...) as the GoRouter redirect, or place '
        'the app below a ProviderScope.',
      );
    }
    return SymphonyRouteScope(
      readAccess: () => container.read(accessContextProvider),
      resolver: const SymphonyRedirectResolver(),
    );
  }
}
