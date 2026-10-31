import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/access_context.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/redirect_logic.dart';
import '../domain/symphony_route_paths.dart';
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
  /// parameters behave like in [create].
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
  }) {
    return GoRouter(
      routes: routes,
      initialLocation: initialLocation,
      redirect: buildRedirect(
        readAccess: readAccess,
        paths: paths,
        publicPaths: publicPaths,
        redirect: redirect,
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
  /// [SymphonyRedirectResolver.resolveGlobal], then the application
  /// [redirect]. It also provides [readAccess] and [paths] to the
  /// `GuardedRoute`/`GuestRoute` redirects of the same router.
  static GoRouterRedirect buildRedirect({
    required AccessContext Function() readAccess,
    SymphonyRoutePaths paths = const SymphonyRoutePaths(),
    Set<String> publicPaths = const <String>{},
    GoRouterRedirect? redirect,
  }) {
    assert(_debugCheckConfiguration(paths, publicPaths));
    final resolver = SymphonyRedirectResolver(
      paths: paths,
      publicPaths: publicPaths,
    );
    final scope =
        SymphonyRouteScope(readAccess: readAccess, resolver: resolver);
    return (BuildContext context, GoRouterState state) {
      SymphonyRouteScope.bind(context, scope);
      final target = resolver.resolveGlobal(readAccess(), state.uri);
      if (target != null) return target;
      return redirect?.call(context, state);
    };
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
