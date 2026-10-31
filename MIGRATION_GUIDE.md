# Migration guide

- [Part 1 – Adopting symphony_core in an existing app](#part-1--adopting-symphony_core-in-an-existing-app)
- [Part 2 – Notes for specific stacks](#part-2--notes-for-specific-stacks)
- [Part 3 – Upgrading symphony_core](#part-3--upgrading-symphony_core)

## Part 1 – Adopting symphony_core in an existing app

The package can be adopted one module at a time. Each step below leaves the
app shippable; stop at any step.

Before you start:

- Flutter `>=3.10`, Dart `>=3.0`, and, if the app already uses them,
  flutter_riverpod `>=2.4 <4`, go_router `>=10 <19`, dio `>=5.4 <6`,
  flutter_secure_storage `>=9 <12` (see [COMPATIBILITY.md](COMPATIBILITY.md)).
- The package uses Riverpod internally. Apps on Provider, Bloc or another
  state management solution can still adopt it: see
  [Provider, Bloc and other state management](#provider-bloc-and-other-state-management).

### Step 1 – Add the dependency

Add `symphony_core` (path or git, see [README – Installation](README.md#installation))
and, if not present yet, `flutter_riverpod` and `go_router`. Run
`flutter pub get` and fix any version conflict by moving your own
constraints into the supported ranges.

### Step 2 – Initialize the core

**Option A – let SymphonyCore own the root container (recommended).**
Replace the root `ProviderScope` with `SymphonyScope` and move your existing
overrides into `SymphonyCore.initialize(overrides: [...])`, so they live in
the same root container as the package's providers.

Before:

```dart
void main() {
  runApp(
    ProviderScope(
      overrides: [
        featureFlagsProvider.overrideWithValue(const FeatureFlags(newCheckout: true)),
      ],
      child: const LegacyApp(),
    ),
  );
}
```

After:

```dart
Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    overrides: [
      featureFlagsProvider.overrideWithValue(const FeatureFlags(newCheckout: true)),
    ],
  );
  runApp(const SymphonyScope(child: LegacyApp()));
}
```

You also get `SymphonyCore.instance` (services outside the widget tree) and
the global error handlers (`handleGlobalErrors`, on by default; turn it off if
your crash reporter already installs `FlutterError.onError` and you do not
want both).

**Option B – keep your root `ProviderScope`.** Add the package's overrides to
it with `symphonyOverrides`. It must be the root scope: the package's
providers declare no Riverpod `dependencies`, so a nested scope cannot
override them.

```dart
void main() {
  runApp(
    ProviderScope(
      overrides: symphonyOverrides(
        config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
        overrides: [
          featureFlagsProvider.overrideWithValue(const FeatureFlags(newCheckout: true)),
        ],
      ),
      child: const LegacyApp(),
    ),
  );
}
```

In this mode there is no `SymphonyCore.instance` and no global error handler
(call `GlobalErrorHandler.install(reporter: ...)` yourself if you want one).

Nested `ProviderScope`s of your app below `SymphonyScope` (or below the root
scope) keep working as before.

### Step 3 – Move HTTP calls to `ApiClient`

Start with one repository; the old client and `ApiClient` can coexist.

Before (raw Dio):

```dart
import 'package:dio/dio.dart';

class LegacyOrderApi {
  LegacyOrderApi()
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://api.example.com',
            connectTimeout: const Duration(seconds: 10),
          ),
        );

  final Dio _dio;

  Future<List<dynamic>> fetchOrders() async {
    try {
      final response = await _dio.get<List<dynamic>>('/orders');
      return response.data ?? const [];
    } on DioException catch (error) {
      throw Exception('Could not load orders: ${error.message}');
    }
  }
}
```

After:

```dart
class OrderApi {
  const OrderApi(this._client);

  final ApiClient _client;

  /// Throws a `Failure` (NetworkFailure, UnauthorizedFailure...) on error.
  Future<List<dynamic>> fetchOrders() async {
    final response = await _client.get<List<dynamic>>('/orders');
    return response.data;
  }
}

final orderApiProvider = Provider<OrderApi>(
  (ref) => OrderApi(ref.watch(apiClientProvider)),
);
```

Where things move:

| Before | With symphony_core |
|---|---|
| `BaseOptions(baseUrl, timeouts, headers)` | `SymphonyConfig(baseUrl, connectTimeout, receiveTimeout, sendTimeout, defaultHeaders)` |
| Several `Dio` instances | One `ApiClient` (`apiClientProvider`); per-request `ApiRequestOptions` for differences |
| Custom interceptors | `apiInterceptorsProvider` (they run after the inspector and logging, before headers, token and retry) |
| Token / refresh interceptor | `AuthTokenInterceptor`, fed by the auth module or your own `AuthTokenDelegate` |
| Retry package or interceptor | `SymphonyConfig.maxRetries`, `retryDelay`, `retryStatusCodes` |
| Logging interceptor | `SymphonyConfig.enableLogging` (redacted) |
| Network inspector package | `SymphonyConfig.enableInspector` + `SymphonyInspectorOverlay` |
| `DioException` handling | `Failure` subclasses, `guardResult`, `ApiErrorMapper` |
| `Response<T>` | `ApiResponse<T>` with a typed `decoder` |
| Changing `dio.options.baseUrl` | `apiClient.updateBaseUrl(...)` |

To keep an existing, heavily customised `Dio` for a while, pass it to the
`ApiClient` by overriding `apiClientProvider`. Its interceptors run before
the package's interceptors; its options are kept except the base URL,
timeouts and default headers, which come from `SymphonyConfig`. Closing the
client closes that `Dio` too.

```dart
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:symphony_core/symphony_core.dart';

Dio createLegacyDio() => Dio()..interceptors.add(LogInterceptor());

Future<void> main() async {
  final legacyDio = createLegacyDio();
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    overrides: [
      apiClientProvider.overrideWith((ref) {
        final config = ref.watch(symphonyConfigProvider);
        final container = ref.container;
        final client = ApiClient(
          config: config,
          dio: legacyDio,
          logger: ref.watch(symphonyLoggerProvider).withTag('HTTP'),
          inspector: config.enableInspector ? ref.watch(apiInspectorProvider) : null,
          // Resolved lazily on each request (avoids a provider cycle).
          tokenDelegate: () => container.read(authTokenDelegateProvider),
          errorMapper: ref.watch(apiErrorMapperProvider),
        );
        ref.onDispose(client.close);
        return client;
      }),
    ],
  );
  runApp(const SymphonyScope(child: LegacyApp()));
}
```

### Step 4 – Write an `AuthAdapter` for the existing endpoints

If the backend is a typical REST/JSON API, configure `RestAuthAdapter`
(endpoints, `AuthResponseMapping`, body hooks; see
[README – Authentication](README.md#authentication)). Otherwise wrap the
existing calls in a custom adapter:

```dart
class LegacyAuthAdapter extends AuthAdapter {
  LegacyAuthAdapter(this._client);

  final ApiClient _client;

  @override
  Future<AuthSession> login(AuthCredentials credentials) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/v1/session',
      data: {'login': credentials['email'], 'secret': credentials['password']},
      options: ApiRequestOptions.unauthenticated,
    );
    final body = response.data;
    return AuthSession(
      tokens: AuthTokens(
        accessToken: body['jwt'] as String,
        refreshToken: body['refresh'] as String?,
        expiresAt: DateTime.now().add(Duration(seconds: body['ttl'] as int)),
      ),
      user: AuthUser(
        id: '${body['user_id']}',
        displayName: body['name'] as String?,
        roles: JsonReader.asStringSet(body['groups']) ?? const <String>{},
      ),
    );
  }

  @override
  Future<AuthTokens> refresh(AuthTokens current) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/v1/session/refresh',
      data: {'refresh': current.refreshToken},
      options: ApiRequestOptions.unauthenticated,
    );
    return current.copyWith(accessToken: response.data['jwt'] as String);
  }

  @override
  Future<void> logout(AuthSession session) async {
    await _client.delete<void>(
      '/v1/session',
      // Never refresh during sign-out; send the token explicitly.
      options: ApiRequestOptions(
        refreshOnUnauthorized: false,
        headers: {'Authorization': 'Bearer ${session.tokens.accessToken}'},
      ),
    );
  }
}
```

Rules for adapters: throw `Failure`s; use `ApiRequestOptions.unauthenticated`
for sign-in, refresh, registration and recovery; never let sign-out trigger
a refresh. Register the adapter with
`authAdapterBuilder: (ref) => LegacyAuthAdapter(ref.watch(apiClientProvider))`.

Keep users signed in across the update by moving the tokens stored by the old
implementation into the package's session storage once, before the session
is restored. `secureStorageProvider` prefixes its keys with `symphony.`, so
read the old, unprefixed keys through a `SecureKeyValueStorage` without
prefix:

```dart
Future<void> migrateLegacySession(SymphonyCore core) async {
  final legacy = SecureKeyValueStorage(
    storage: core.read(flutterSecureStorageProvider),
  );
  final accessToken = await legacy.read('auth_token');
  if (accessToken == null) return;
  await core.read(sessionStorageProvider).writeTokens(
        AuthTokens(
          accessToken: accessToken,
          refreshToken: await legacy.read('refresh_token'),
        ),
      );
  await legacy.delete('auth_token');
  await legacy.delete('refresh_token');
}

Future<void> main() async {
  final core = await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    authAdapterBuilder: (ref) => LegacyAuthAdapter(ref.watch(apiClientProvider)),
  );
  await migrateLegacySession(core);
  runApp(SymphonyScope(core: core, child: const LegacyApp()));
}
```

The user profile is then loaded by `fetchCurrentUser` during restoration (the
default returns the stored user, which is empty here: override
`fetchCurrentUser` in the adapter, or configure `currentUser` with
`RestAuthAdapter`). Replace your own session state (auth notifier, "is
logged in" flags) with `authControllerProvider`, `currentUserProvider` and
`isAuthenticatedProvider`.

### Step 5 – Adopt the router guards

Create the router with `SymphonyRouter.create` and replace hand-written
redirect logic with `GuardedRoute` / `GuestRoute`. Your remaining global
rules go to `redirect:` and run after the built-in rules. Apps with many
plain `GoRoute`s that all require sign-in can keep them unchanged and pass
`defaultAccess: AccessRequirement.authenticated` (see
[README – Secure by default](README.md#secure-by-default)).

```dart
final routerProvider = Provider<GoRouter>((ref) {
  return SymphonyRouter.create(
    ref,
    // Keep your existing locations.
    paths: const SymphonyRoutePaths(login: '/sign-in', home: '/home', unauthorized: null),
    initialLocation: '/home', // the app has no '/' route
    redirect: (context, state) => null, // your previous app rules, if any
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GuestRoute(path: '/sign-in', builder: (context, state) => const LoginPage()),
      GuardedRoute(
        path: '/home',
        builder: (context, state) => const HomePage(),
        routes: [
          GuardedRoute(
            path: 'admin',
            access: const AccessRequirement(roles: {'admin'}),
            builder: (context, state) => const AdminPage(),
          ),
        ],
      ),
    ],
  );
});
```

If you must keep building the `GoRouter` yourself (for example to use
go_router options that `SymphonyRouter` does not forward), plug in the
redirect and the refresh trigger. The session is then not restored
automatically: use `SymphonySplashScreen` or
`SymphonyCore.initialize(restoreSession: true)`.

```dart
final customRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    refreshListenable: SymphonyRouter.accessRefreshListenable(ref),
    redirect: SymphonyRouter.buildRedirect(
      readAccess: () => ref.read(accessContextProvider),
    ),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GuestRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GuardedRoute(path: '/', builder: (context, state) => const HomePage()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
```

### Step 6 – Adopt the UI components

The widgets work with your existing `ThemeData`; `SymphonyColors` and
`SymphonyRadius` fall back to defaults when the theme does not define them.
Adopt them per screen, then switch the theme when convenient, either
`SymphonyTheme.light(SymphonyThemeConfig(lightColorScheme: ...))` or your
theme plus the extensions:

```dart
final legacyTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
  extensions: const [SymphonyColors.light, SymphonyRadius.standard],
);
```

Good first candidates: `SymphonyErrorView` / `SymphonySnackbar.showFailure`
(they understand `Failure`s), `SymphonyButton(isLoading: ...)`,
`SymphonyDialogs.confirm`, `SymphonyValidators`.

### Step 7 – Remove duplicated infrastructure

Once the steps above are done, delete what the package now provides:

- extra `Dio` / `http` clients, base URL switching code, retry helpers;
- token storage helpers, refresh interceptors and "refresh in progress"
  locks;
- logging interceptors and network inspector packages;
- custom exception classes that mirror `Failure`s, ad-hoc error parsing;
- splash/session bootstrap code, auth state notifiers, route redirect
  functions;
- secure storage wrappers (use `secureStorageProvider` or a
  `PrefixedKeyValueStorage` on top of it);
- duplicated widgets (loading/error/empty states, confirm dialogs).

Then search the codebase for `Dio(` and `FlutterSecureStorage(`: outside
`apiClientProvider` / `flutterSecureStorageProvider` overrides, they usually
indicate leftovers.

## Part 2 – Notes for specific stacks

### Apps on raw Dio or package:http

- Follow step 3. Dio types are re-exported by symphony_core, so existing
  interceptors compile unchanged.
- `package:http` users: symphony_core re-exports Dio's `Response`. Import
  with `hide Response` in files that also import `package:http`.
- `DioException` no longer reaches your code from `ApiClient`: catch
  `Failure` (or a subclass) instead.

### Provider, Bloc and other state management

`SymphonyScope` must still wrap the app, because the package's widgets use
Riverpod internally. Your own code does not have to: everything is reachable
through `SymphonyCore`.

```dart
/// Mirrors the authentication state into a plain [ValueNotifier], usable
/// with Provider, Bloc, or `ListenableBuilder`.
class AuthStateBridge extends ValueNotifier<AuthState> {
  AuthStateBridge(SymphonyCore core) : super(core.read(authControllerProvider)) {
    _subscription = core.container.listen<AuthState>(
      authControllerProvider,
      (previous, next) => value = next,
    );
  }

  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

/// A view model without Riverpod: actions go through the core's controller.
class SignInViewModel extends ChangeNotifier {
  SignInViewModel(this._core);

  final SymphonyCore _core;
  Failure? error;

  Future<void> signIn(String email, String password) async {
    final result = await _core.auth.login(
      AuthCredentials.emailPassword(email: email, password: password),
    );
    error = result.failureOrNull;
    notifyListeners();
  }
}

GoRouter buildRouter(AuthStateBridge auth) {
  return SymphonyRouter.custom(
    readAccess: () => auth.value.accessContext,
    refreshListenable: auth,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GuestRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GuardedRoute(path: '/', builder: (context, state) => const HomePage()),
    ],
  );
}
```

- Inject `SymphonyCore.instance.apiClient` into your repositories, blocs or
  `ChangeNotifier`s (for example through `Provider.value` or your service
  locator).
- `SymphonyRouter.custom` does not restore the session: call
  `SymphonyCore.initialize(restoreSession: true)` or use
  `SymphonySplashScreen`. The caller disposes the router.
- Read any other service with `SymphonyCore.instance.read(provider)` and
  observe changes with `core.container.listen(...)`.

### Upgrading your app from Riverpod 2 to Riverpod 3

symphony_core supports both majors with the same API, so you can upgrade
Riverpod independently. Riverpod 3 changes that commonly affect apps (see
the Riverpod 3.0 migration guide on [riverpod.dev](https://riverpod.dev)):

| Change in Riverpod 3 | What to do |
|---|---|
| `StateProvider`, `StateNotifierProvider` and `ChangeNotifierProvider` moved to `package:flutter_riverpod/legacy.dart`. | Import `legacy.dart` or migrate to `Notifier`. |
| `Override`, `ProviderListenable` and other types are exported by `package:flutter_riverpod/misc.dart`, not by `flutter_riverpod.dart`. | Let types be inferred, or import `misc.dart`. |
| `Ref` is no longer generic; typed refs such as `ProviderRef<T>` are gone. | Type parameters as `Ref`. Functions taking a raw `Ref` (like `SymphonyRouter.create`) work on both. |
| Errors thrown by providers are rethrown wrapped in `ProviderException`. | Match errors by message in tests; catch `Failure`s inside your providers if you need typed handling. |
| Failing providers are retried automatically (exceptions, not errors). | Expect retries for providers that throw `Failure`s; configure with the provider's `retry:` parameter. |
| `AsyncValue.valueOrNull` was removed; `value` returns `null` when there is no data. | Replace `valueOrNull` with `value`. |
| Auto-dispose and family notifiers use a new class hierarchy. | Port such notifiers following the Riverpod guide. |

Typing an override list explicitly on Riverpod 3:

```dart
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:symphony_core/symphony_core.dart';

List<Override> testOverrides() => [
      secureStorageProvider.overrideWithValue(InMemoryKeyValueStorage()),
    ];
```

symphony_core-specific differences between the two majors (duplicate
overrides, error wrapping, retries) are listed in
[COMPATIBILITY.md](COMPATIBILITY.md#version-specific-behaviour).

### go_router major upgrades

`GuardedRoute` and `GuestRoute` are plain `GoRoute` subclasses and the
package only uses APIs that exist in every go_router major from 10 to 18, so
upgrading go_router needs no symphony_core change. Check your own code
against go_router's breaking changes:

| go_router | Breaking change (from go_router's changelog) | Notes for symphony_core apps |
|---|---|---|
| 10.0 | `GoRouterState.location` / `queryParameters` replaced by `uri` ([guide](https://flutter.dev/go/go-router-v10-breaking-changes)). | The package uses `state.uri`. |
| 11.0 | `GoRouteInformationProvider.restore` signature, `NavigationType.restore`. | |
| 12.0 | `RouteConfiguration` constructor, `RouteMatch.match`. | |
| 13.0 | `RouteMatchList` refactor and matching logic. | |
| 14.0 | `GoRouteData.onExit` takes `(context, state)`. | |
| 15.0 | URLs are case-sensitive by default ([guide](https://flutter.dev/go/go-router-v15-breaking-changes)). | The package's own path checks stay case-insensitive; make links match the route case. |
| 16.0 | `GoRouteData` changes (type-safe routes, go_router_builder 3). | |
| 17.0 | `ShellRoute` navigation notifies the router's observers by default. | Some 17.0.x releases evaluate the top-level redirect once per navigation (see COMPATIBILITY.md). |
| 18.0 | Requires Flutter 3.44 / Dart 3.12. | Older SDKs keep resolving an older major. |

Options of newer go_router versions that `SymphonyRouter.create` does not
forward (for example `onEnter` or `caseSensitive`) can be used by building
the `GoRouter` yourself with `SymphonyRouter.buildRedirect` (step 5).

## Part 3 – Upgrading symphony_core

### Procedure

1. Read the [CHANGELOG](CHANGELOG.md) entries between your version and the
   target, and the matching section below.
2. Change the version constraint or the git `ref` and run `flutter pub get`.
3. Fix analyzer errors and deprecation warnings (deprecated APIs name their
   replacement).
4. Run your tests, then check the behaviour changes listed for the release
   (redirects, failure mapping, persisted data).

### Before and after 1.0

- **0.x**: the minor number is the breaking digit (`0.1.x` → `0.2.0` may
  break); patch releases (`0.1.x`) only add features and fixes. Constraints
  such as `^0.1.0` never pick up a breaking release.
- **1.0** will be released once the public API has been used by several
  apps without breaking changes for a while. From then on, breaking changes
  require a major version, deprecated APIs keep working until the next major,
  and minimum versions follow the
  [policy for version ranges](COMPATIBILITY.md#policy-for-version-ranges).
- What counts as breaking is defined in
  [README – Versioning policy](README.md#versioning-policy).

No migration is needed yet: 0.1.0 is the first release.

### Template for future migrations

Each breaking release adds a section using this template:

```markdown
## Migrating from <old version> to <new version>

**Summary:** what changed and why, in two or three sentences.
**Effort:** low / medium / high.
**Requires:** Flutter / Dart / dependency minimums, if they changed.

### Breaking changes

| Before | After | Why |
|---|---|---|
| `OldApi(...)` | `NewApi(...)` | ... |

### Behaviour changes

- Redirect rules, failure mapping, defaults, persisted formats...
  (with how to keep the old behaviour, if possible).

### Deprecations

- `deprecatedMember` → `replacement` (removed in <version>).

### Compatibility

- Ranges added or removed (see COMPATIBILITY.md).

### Steps

1. ...

### Verification checklist

- [ ] `flutter analyze` reports no issue or deprecation.
- [ ] Tests pass with `flutter pub downgrade` and `flutter pub upgrade`.
- [ ] Sign-in, session restoration and sign-out work on a device.
- [ ] Guarded routes and the dashboard show the expected entries per role.
```
