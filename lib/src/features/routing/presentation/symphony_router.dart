import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/access_context.dart';
import '../../../core/access/access_requirement.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/redirect_logic.dart';
import '../domain/symphony_route_paths.dart';
import 'guarded_route.dart';
import 'symphony_route_scope.dart';
import 'widgets/symphony_route_error_screen.dart';

/// Builds [GoRouter]s wired to the authentication state: session-restoration
/// splash, sign-in redirects with return to the requested page, guest-only
/// pages, and the access source of `GuardedRoute`/`GuestRoute`.
///
/// Applications keep defining and owning their routes; `SymphonyRouter` only
/// adds the redirect policy described in [SymphonyRedirectResolver].
///
/// Recommended usage with Riverpod:
///
/// ```dart
/// final routerProvider = Provider<GoRouter>((ref) {
///   return SymphonyRouter.create(
///     ref,
///     routes: [
///       GoRoute(
///         path: '/splash',
///         builder: (context, state) => const SplashPage(),
///       ),
///       GuestRoute(
///         path: '/login',
///         builder: (context, state) => const LoginPage(),
///       ),
///       GoRoute(
///         path: '/unauthorized',
///         builder: (context, state) => const SymphonyUnauthorizedScreen(),
///       ),
///       GuardedRoute(
///         path: '/',
///         builder: (context, state) => const HomePage(),
///         routes: [
///           GuardedRoute(
///             path: 'admin',
///             access: const AccessRequirement(roles: {'admin'}),
///             builder: (context, state) => const AdminPage(),
///           ),
///         ],
///       ),
///     ],
///   );
/// });
///
/// class App extends ConsumerWidget {
///   const App({super.key});
///
///   @override
///   Widget build(BuildContext context, WidgetRef ref) =>
///       MaterialApp.router(routerConfig: ref.watch(routerProvider));
/// }
/// ```
///
/// Only `ref.listen`/`ref.read` are used internally: the router is created
/// once and refreshed — never rebuilt — when the access changes. Do not
/// `ref.watch` other providers in the router provider either, or the
/// navigation stack would be reset when they change.
///
/// Secure by default: pass `defaultAccess: AccessRequirement.authenticated`
/// (or a role/permission requirement) to require it on every location except
/// the splash route, the guest-only routes and the `publicPaths`, so plain
/// `GoRoute`s are protected as well.
///
/// When the access changes, the pages opened with `GoRouter.push` are checked
/// again too (go_router 13 and later only re-evaluate the redirects of the
/// location below them): a pushed page the user may no longer see is closed
/// and the user is sent where its guard says (sign-in, unauthorized...).
abstract final class SymphonyRouter {
  /// Creates a [GoRouter] driven by `accessContextProvider`.
  ///
  /// * [ref] is the `Ref` of the provider exposing the router. The router and
  ///   its refresh notifier are disposed with that provider.
  /// * [routes] are the application routes. They must contain routes for the
  ///   locations of [paths] (splash, login, home and, unless `null`,
  ///   unauthorized).
  /// * [paths] configures those locations and the redirect parameter.
  /// * [publicPaths] are shown without waiting for the session restoration
  ///   (route guards still apply). Entries cover their descendants.
  /// * [redirect] is the application's global redirect, evaluated after the
  ///   built-in rules when they do not redirect. go_router evaluates the
  ///   global redirect again on each location a redirect produces, except
  ///   some go_router 17.x releases (such as 17.0.x) which evaluate it once
  ///   per navigation.
  /// * [errorBuilder] builds the page of unknown locations and redirect
  ///   errors; defaults to [SymphonyRouteErrorScreen].
  /// * [refreshListenable] adds application triggers re-evaluating the
  ///   redirects, on top of access changes.
  /// * [restoreSessionOnStart] calls `AuthController.restoreSession()` once,
  ///   in a microtask after the router is created, so that the unknown
  ///   status (splash) resolves without extra wiring. The restoration is
  ///   idempotent, so a splash page restoring the session as well is
  ///   harmless. Errors are reported through [FlutterError.reportError].
  /// * [defaultAccess] makes the router secure by default. When set, every
  ///   location except the splash route, the guest-only routes (the login
  ///   route included) and the [publicPaths] requires it, so plain
  ///   `GoRoute`s are protected without wrapping each of them in a
  ///   `GuardedRoute`: signed-out users go to `login?from=<location>`,
  ///   signed-in users who do not satisfy it go to
  ///   [SymphonyRoutePaths.unauthorized] (else home), which stays reachable
  ///   for them. Route guards add their own requirements on top of it; list
  ///   the pages open to everybody in [publicPaths], and the guest pages
  ///   other than the login route (registration, password recovery...) in
  ///   [SymphonyRoutePaths.guestOnlyPaths] — a `GuestRoute` alone does not
  ///   exempt its page, the global redirect only knows locations. With a
  ///   role or permission requirement keep [SymphonyRoutePaths.unauthorized]
  ///   set: without it denied users have no page left and go_router reports
  ///   a redirect loop. `null` (the default) only protects guarded routes.
  ///   See [SymphonyRedirectResolver.defaultAccess].
  /// * [initialLocation], [navigatorKey], [observers],
  ///   [debugLogDiagnostics], [redirectLimit] and [restorationScopeId] are
  ///   forwarded to [GoRouter].
  static GoRouter create(
    Ref ref, {
    required List<RouteBase> routes,
    SymphonyRoutePaths paths = const SymphonyRoutePaths(),
    String? initialLocation,
    Set<String> publicPaths = const <String>{},
    GoRouterRedirect? redirect,
    GoRouterWidgetBuilder? errorBuilder,
    GlobalKey<NavigatorState>? navigatorKey,
    List<NavigatorObserver>? observers,
    bool debugLogDiagnostics = false,
    int redirectLimit = 5,
    bool restoreSessionOnStart = true,
    Listenable? refreshListenable,
    String? restorationScopeId,
    AccessRequirement? defaultAccess,
  }) {
    final accessChanges = _listenAccess(ref);
    final router = custom(
      readAccess: () => ref.read(accessContextProvider),
      refreshListenable: refreshListenable == null
          ? accessChanges
          : Listenable.merge(<Listenable>[accessChanges, refreshListenable]),
      routes: routes,
      paths: paths,
      initialLocation: initialLocation,
      publicPaths: publicPaths,
      redirect: redirect,
      errorBuilder: errorBuilder,
      navigatorKey: navigatorKey,
      observers: observers,
      debugLogDiagnostics: debugLogDiagnostics,
      redirectLimit: redirectLimit,
      restorationScopeId: restorationScopeId,
      defaultAccess: defaultAccess,
    );
    var disposed = false;
    ref.onDispose(() {
      disposed = true;
      router.dispose();
      accessChanges.dispose();
    });
    if (restoreSessionOnStart) {
      scheduleMicrotask(() {
        if (!disposed) _restoreSession(ref);
      });
    }
    return router;
  }

  /// Creates a [GoRouter] without Riverpod: the access snapshot comes from
  /// [readAccess] and [refreshListenable] must notify whenever it changes
  /// (for example a `ValueNotifier<AccessContext>` owned by the app's own
  /// state management).
  ///
  /// ```dart
  /// final access = ValueNotifier<AccessContext>(AccessContext.unknown);
  /// final router = SymphonyRouter.custom(
  ///   readAccess: () => access.value,
  ///   refreshListenable: access,
  ///   routes: routes,
  /// );
  /// ```
  ///
  /// `GuardedRoute` and `GuestRoute` of this router read the same access
  /// source and [paths]: the router's top-level redirect binds them to the
  /// router context that go_router passes to every redirect, so no
  /// `ProviderScope` is needed.
  ///
  /// The caller owns the returned router and must `dispose` it. Other
  /// parameters (including the secure-by-default [defaultAccess]) behave
  /// like in [create].
  static GoRouter custom({
    required AccessContext Function() readAccess,
    required Listenable refreshListenable,
    required List<RouteBase> routes,
    SymphonyRoutePaths paths = const SymphonyRoutePaths(),
    String? initialLocation,
    Set<String> publicPaths = const <String>{},
    GoRouterRedirect? redirect,
    GoRouterWidgetBuilder? errorBuilder,
    GlobalKey<NavigatorState>? navigatorKey,
    List<NavigatorObserver>? observers,
    bool debugLogDiagnostics = false,
    int redirectLimit = 5,
    String? restorationScopeId,
    AccessRequirement? defaultAccess,
  }) {
    return GoRouter(
      routes: routes,
      initialLocation: initialLocation,
      redirect: buildRedirect(
        readAccess: readAccess,
        paths: paths,
        publicPaths: publicPaths,
        redirect: redirect,
        defaultAccess: defaultAccess,
      ),
      refreshListenable: refreshListenable,
      errorBuilder:
          errorBuilder ?? defaultErrorBuilder(homeLocation: paths.home),
      navigatorKey: navigatorKey,
      observers: observers,
      debugLogDiagnostics: debugLogDiagnostics,
      redirectLimit: redirectLimit,
      restorationScopeId: restorationScopeId,
    );
  }

  /// Builds the global redirect used by [create] and [custom], for
  /// applications constructing their [GoRouter] themselves:
  ///
  /// ```dart
  /// GoRouter(
  ///   routes: routes,
  ///   redirect: SymphonyRouter.buildRedirect(
  ///     readAccess: () => ref.read(accessContextProvider),
  ///   ),
  ///   refreshListenable: SymphonyRouter.accessRefreshListenable(ref),
  /// );
  /// ```
  ///
  /// The returned redirect applies the rules of
  /// [SymphonyRedirectResolver.resolveGlobal] (including the optional
  /// secure-by-default [defaultAccess], see [create]), re-checks the pages
  /// pushed on top of the displayed location when the router refreshes, then
  /// applies the application [redirect]. With a [defaultAccess], the
  /// location returned by [redirect] must satisfy it as well. It also
  /// provides [readAccess] and [paths] to the `GuardedRoute`/`GuestRoute`
  /// redirects of the same router.
  static GoRouterRedirect buildRedirect({
    required AccessContext Function() readAccess,
    SymphonyRoutePaths paths = const SymphonyRoutePaths(),
    Set<String> publicPaths = const <String>{},
    GoRouterRedirect? redirect,
    AccessRequirement? defaultAccess,
  }) {
    assert(_debugCheckConfiguration(paths, publicPaths));
    final resolver = SymphonyRedirectResolver(
      paths: paths,
      publicPaths: publicPaths,
      defaultAccess: defaultAccess,
    );
    final scope =
        SymphonyRouteScope(readAccess: readAccess, resolver: resolver);
    final pushedPages = _PushedPagesGuard(resolver);
    return (BuildContext context, GoRouterState state) {
      SymphonyRouteScope.bind(context, scope);
      final access = readAccess();
      final target = resolver.resolveGlobal(access, state.uri) ??
          pushedPages.check(context, state.uri, access);
      if (target != null) return target;
      final appTarget = redirect?.call(context, state);
      if (defaultAccess == null) return appTarget;
      return _finalAppTarget(appTarget, resolver, readAccess);
    };
  }

  /// Applies the global rules to the location returned by the application
  /// redirect, so that it satisfies the default requirement even on the
  /// go_router releases that do not evaluate the global redirect again on
  /// the location it returns.
  static FutureOr<String?> _finalAppTarget(
    FutureOr<String?> appTarget,
    SymphonyRedirectResolver resolver,
    AccessContext Function() readAccess,
  ) {
    String? finalTarget(String? location) {
      if (location == null) return null;
      final uri = Uri.tryParse(location);
      if (uri == null) return location;
      return resolver.resolveGlobal(readAccess(), uri) ?? location;
    }

    if (appTarget is Future<String?>) return appTarget.then(finalTarget);
    return finalTarget(appTarget);
  }

  /// A [Listenable] notifying whenever `accessContextProvider` changes, to
  /// use as `GoRouter.refreshListenable`. It is disposed with [ref].
  static Listenable accessRefreshListenable(Ref ref) {
    final notifier = _listenAccess(ref);
    ref.onDispose(notifier.dispose);
    return notifier;
  }

  /// The error page builder used when no `errorBuilder` is given: a
  /// [SymphonyRouteErrorScreen] whose button opens [homeLocation].
  static GoRouterWidgetBuilder defaultErrorBuilder({
    String homeLocation = '/',
  }) {
    return (BuildContext context, GoRouterState state) {
      return SymphonyRouteErrorScreen(
        error: state.error,
        location: SymphonyRedirectResolver.locationOf(state.uri),
        homeLocation: homeLocation,
      );
    };
  }

  static _AccessChangeNotifier _listenAccess(Ref ref) {
    final notifier = _AccessChangeNotifier();
    ref.listen<AccessContext>(
      accessContextProvider,
      (AccessContext? previous, AccessContext next) {
        if (previous != next) notifier.notifyAccessChanged();
      },
      // Re-run the redirects so the failure surfaces through the router.
      onError: (Object error, StackTrace stackTrace) =>
          notifier.notifyAccessChanged(),
    );
    return notifier;
  }

  static void _restoreSession(Ref ref) {
    unawaited(
      Future<void>.sync(
        () => ref.read(authControllerProvider.notifier).restoreSession(),
      ).catchError(_reportRestoreError),
    );
  }

  static void _reportRestoreError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'symphony_core',
        context:
            ErrorDescription('while restoring the session on router start'),
      ),
    );
  }

  static bool _debugCheckConfiguration(
    SymphonyRoutePaths paths,
    Set<String> publicPaths,
  ) {
    final named = <String, String?>{
      'splash': paths.splash,
      'login': paths.login,
      'home': paths.home,
      'unauthorized': paths.unauthorized,
    };
    named.forEach((String name, String? value) {
      assert(
        value == null || value.startsWith('/'),
        'SymphonyRoutePaths.$name must start with "/" (got "$value").',
      );
    });
    for (final entry in <String>[...paths.guestOnlyPaths, ...publicPaths]) {
      assert(
        entry.startsWith('/'),
        'Guest-only and public paths must start with "/" (got "$entry").',
      );
    }
    assert(
      paths.redirectParameter.isNotEmpty,
      'SymphonyRoutePaths.redirectParameter must not be empty.',
    );
    return true;
  }
}

/// Notifies the router that the access snapshot changed.
class _AccessChangeNotifier extends ChangeNotifier {
  void notifyAccessChanged() => notifyListeners();
}

/// Re-checks the pages pushed on top of the displayed location when the
/// router refreshes (for example after a sign-out or a role change).
///
/// On a refresh go_router 13 and later only evaluate the redirects of the
/// base location: pages opened with `GoRouter.push` would stay displayed
/// after the user lost access to them. go_router 10 evaluates their route
/// redirects, but against the base location. This guard runs in the global
/// redirect and applies the global rules and the `GuardedRoute`/`GuestRoute`
/// guards to every pushed location, top first. The first one that redirects
/// replaces the whole stack.
///
/// It only uses the go_router API common to 10.0 and 18.x: the redirect
/// context is the `Router` element, whose delegate exposes the displayed
/// match list.
class _PushedPagesGuard {
  _PushedPagesGuard(this.resolver);

  final SymphonyRedirectResolver resolver;

  /// Whether a navigation replacing the stack is already scheduled.
  bool _replacing = false;

  /// Where to send the user because a pushed page of the displayed stack is
  /// no longer allowed, or `null`. Only acts when [location] is the
  /// displayed base location, which is the case on refreshes.
  String? check(
    BuildContext routerContext,
    Uri location,
    AccessContext access,
  ) {
    final Widget widget = routerContext.widget;
    if (widget is! Router<Object?>) return null;
    final RouterDelegate<Object?> delegate = widget.routerDelegate;
    if (delegate is! GoRouterDelegate) return null;
    final RouteMatchList configuration = delegate.currentConfiguration;
    final displayed = _canonical(location);
    if (_canonical(configuration.uri) != displayed) return null;
    for (final pushed in _pushedMatchLists(configuration)) {
      final target =
          resolver.resolveGlobal(access, pushed.uri) ?? _guard(pushed, access);
      if (target == null) continue;
      final targetUri = Uri.tryParse(target);
      if (targetUri == null || _canonical(targetUri) != displayed) {
        return target;
      }
      // The destination is the displayed location itself: a refresh
      // resolving to the current location keeps the stack (and the pushed
      // pages), so navigate to it explicitly to replace the stack.
      _replaceStack(routerContext, widget, target);
      return null;
    }
    return null;
  }

  /// The redirect of the first `GuardedRoute`/`GuestRoute` of [pushed] that
  /// does not let [access] through, parent routes first.
  String? _guard(RouteMatchList pushed, AccessContext access) {
    for (final RouteBase route in pushed.routes) {
      final String? target;
      if (route is GuardedRoute) {
        target = resolver.resolveGuard(
          access,
          pushed.uri,
          requirement: route.access,
          deniedRedirect: route.deniedRedirect,
        );
      } else if (route is GuestRoute) {
        target = resolver.resolveGuest(
          access,
          pushed.uri,
          authenticatedRedirect: route.authenticatedRedirect,
        );
      } else {
        continue;
      }
      if (target != null) return target;
    }
    return null;
  }

  void _replaceStack(
    BuildContext routerContext,
    Router<Object?> router,
    String location,
  ) {
    final provider = router.routeInformationProvider;
    if (_replacing || provider is! GoRouteInformationProvider) return;
    _replacing = true;
    scheduleMicrotask(() {
      _replacing = false;
      if (!routerContext.mounted) return;
      final Widget current = routerContext.widget;
      if (current is Router<Object?> &&
          identical(current.routeInformationProvider, provider)) {
        provider.go(location);
      }
    });
  }

  /// The match lists of the pages pushed on top of the base location of
  /// [configuration], top first. Pushed pages are the last matches, possibly
  /// nested in a shell route match (go_router 13 and later), so they are
  /// peeled off the top with `last`/`remove`, like pops do.
  static List<RouteMatchList> _pushedMatchLists(RouteMatchList configuration) {
    final pushed = <RouteMatchList>[];
    var remaining = configuration;
    try {
      while (remaining.isNotEmpty) {
        final RouteMatch top = remaining.last;
        if (top is! ImperativeRouteMatch) break;
        pushed.add(top.matches);
        final next = remaining.remove(top);
        if (identical(next, remaining)) break;
        remaining = next;
      }
    } on StateError {
      // A shell match without sub-routes: nothing more is pushed on it.
    }
    return pushed;
  }

  /// [uri] as go_router compares locations: leading slash, no trailing
  /// slash.
  static String _canonical(Uri uri) {
    final path = SymphonyRoutePaths.normalizePath(uri.path);
    return (path == uri.path ? uri : uri.replace(path: path)).toString();
  }
}
