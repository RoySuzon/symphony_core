import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/src/core/core.dart';
import 'package:symphony_core/src/features/auth/auth.dart';
import 'package:symphony_core/src/features/routing/routing.dart';

/// Signed-out access snapshot.
const AccessContext signedOut = AccessContext.unauthenticated;

/// Signed-in access snapshot with the given grants.
AccessContext signedIn({
  Set<String> roles = const <String>{},
  Set<String> permissions = const <String>{},
}) =>
    AccessContext(
      status: AuthStatus.authenticated,
      roles: roles,
      permissions: permissions,
    );

/// Mutable access snapshot overriding `accessContextProvider` in tests.
class TestAccessNotifier extends Notifier<AccessContext> {
  /// Creates the notifier starting at [initial].
  TestAccessNotifier([this.initial = AccessContext.unknown]);

  /// First value of the snapshot.
  final AccessContext initial;

  @override
  AccessContext build() => initial;

  /// Replaces the snapshot.
  void set(AccessContext value) => state = value;
}

/// Provider of the mutable test access snapshot.
final testAccessProvider = NotifierProvider<TestAccessNotifier, AccessContext>(
  TestAccessNotifier.new,
);

/// [AuthController] fake recording `restoreSession` calls.
class RecordingAuthController extends AuthController {
  /// Number of `restoreSession` calls.
  int restoreCalls = 0;

  @override
  AuthState build() => const AuthState.unknown();

  @override
  Future<void> restoreSession({bool force = false}) async {
    restoreCalls++;
  }
}

/// A `ProviderScope` whose `accessContextProvider` follows
/// [testAccessProvider] (starting at [initialAccess]) and whose auth
/// controller is a [RecordingAuthController].
///
/// The override list is built inline so that the `Override` type (exported
/// from different libraries by Riverpod 2 and 3) is never named.
Widget routingTestScope({
  required Widget child,
  AccessContext initialAccess = AccessContext.unknown,
}) =>
    ProviderScope(
      overrides: [
        testAccessProvider.overrideWith(
          () => TestAccessNotifier(initialAccess),
        ),
        accessContextProvider.overrideWith(
          (ref) => ref.watch(testAccessProvider),
        ),
        authControllerProvider.overrideWith(RecordingAuthController.new),
      ],
      child: child,
    );

/// A `ProviderContainer` with the same overrides as [routingTestScope].
ProviderContainer routingTestContainer({
  AccessContext initialAccess = AccessContext.unknown,
}) =>
    ProviderContainer(
      overrides: [
        testAccessProvider.overrideWith(
          () => TestAccessNotifier(initialAccess),
        ),
        accessContextProvider.overrideWith(
          (ref) => ref.watch(testAccessProvider),
        ),
        authControllerProvider.overrideWith(RecordingAuthController.new),
      ],
    );

/// Builder of a test page displaying `page:<name>`.
GoRouterWidgetBuilder testPage(String name) =>
    (BuildContext context, GoRouterState state) =>
        Scaffold(body: Center(child: Text('page:$name')));

/// Finder of the test page named [name].
Finder findPage(String name) => find.text('page:$name');

/// Current location of [router].
String locationOf(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

/// A pumped `MaterialApp.router` driven by `SymphonyRouter.create`.
class RouterHarness {
  /// Creates the harness.
  RouterHarness(this.tester, this.container, this.router);

  /// The widget tester.
  final WidgetTester tester;

  /// The container of the app's `ProviderScope`.
  final ProviderContainer container;

  /// The router under test.
  final GoRouter router;

  /// Current location of [router].
  String get location => locationOf(router);

  /// The fake auth controller.
  RecordingAuthController get auth =>
      container.read(authControllerProvider.notifier)
          as RecordingAuthController;

  /// Replaces the access snapshot and settles the navigation.
  Future<void> setAccess(AccessContext access) async {
    container.read(testAccessProvider.notifier).set(access);
    await tester.pumpAndSettle();
  }

  /// Navigates to [location] and settles the navigation.
  Future<void> go(String location) async {
    router.go(location);
    await tester.pumpAndSettle();
  }
}

/// Pumps an app whose router is `SymphonyRouter.create(ref, ...)` with the
/// given options, below the `ProviderScope` of [routingTestScope].
Future<RouterHarness> pumpSymphonyRouter(
  WidgetTester tester, {
  required List<RouteBase> routes,
  AccessContext initialAccess = AccessContext.unknown,
  String? initialLocation,
  SymphonyRoutePaths paths = const SymphonyRoutePaths(),
  Set<String> publicPaths = const <String>{},
  GoRouterRedirect? redirect,
  Listenable? refreshListenable,
  bool restoreSessionOnStart = true,
  AccessRequirement? defaultAccess,
}) async {
  final routerProvider = Provider<GoRouter>(
    (ref) => SymphonyRouter.create(
      ref,
      routes: routes,
      initialLocation: initialLocation,
      paths: paths,
      publicPaths: publicPaths,
      redirect: redirect,
      refreshListenable: refreshListenable,
      restoreSessionOnStart: restoreSessionOnStart,
      defaultAccess: defaultAccess,
    ),
  );
  await tester.pumpWidget(
    routingTestScope(
      initialAccess: initialAccess,
      child: Consumer(
        builder: (context, ref, child) =>
            MaterialApp.router(routerConfig: ref.watch(routerProvider)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
    listen: false,
  );
  return RouterHarness(tester, container, container.read(routerProvider));
}
