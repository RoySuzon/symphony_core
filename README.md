# symphony_core

A reusable application core for Flutter apps. It provides the infrastructure
that most business apps rebuild from scratch: configuration and dependency
injection, one central HTTP client with an in-app API inspector, pluggable
authentication with persisted sessions, route guards, secure storage, a
permission-aware dashboard and a set of common UI components.

Applications plug in their own **configuration** (`SymphonyConfig`) and
**adapters** (for example an `AuthAdapter` for their backend). They never edit
the package source. Every endpoint, response format, text and visual choice
can be configured or replaced.

The package builds on [Riverpod](https://pub.dev/packages/flutter_riverpod)
(dependency injection and state), [Dio](https://pub.dev/packages/dio) (HTTP),
[go_router](https://pub.dev/packages/go_router) (navigation) and
[flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage).
A single codebase targets Flutter 3.10 and later, Riverpod 2 and 3, and
go_router 10 to 18; both ends of these ranges are verified (see
[Compatibility](#compatibility)).

## Contents

- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Integration walkthrough](#integration-walkthrough) and the
  [example app](#example-app)
- [Configuration reference](#configuration-reference)
- Module guides:
  [Core](#core-entry-point-di-errors-logging),
  [Networking](#networking),
  [API inspector](#api-inspector),
  [Authentication](#authentication),
  [Routing](#routing),
  [Storage](#storage),
  [Dashboard](#dashboard),
  [UI components](#ui-components)
- [Overriding dependencies](#overriding-dependencies)
- [Testing](#testing)
- [Security notes](#security-notes)
- [Architecture](#architecture)
- [Compatibility](#compatibility)
- [Troubleshooting](#troubleshooting)
- [Versioning policy](#versioning-policy)
- [License](#license)

Related documents: [COMPATIBILITY.md](COMPATIBILITY.md),
[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md), [CHANGELOG.md](CHANGELOG.md),
[doc/architecture.md](doc/architecture.md). A runnable demo lives in
[`example/`](example/) (entry point `example/lib/main.dart`, see
[Example app](#example-app)).

## Features

| Module | What it provides |
|---|---|
| **core** | `SymphonyCore` entry point and `SymphonyScope`; `SymphonyConfig`; Riverpod providers and `symphonyOverrides`; `Failure` hierarchy and `Result<T>`; `ErrorReporter` and `GlobalErrorHandler`; `SymphonyLogger` with `LogRedactor`; `AccessContext` / `AccessRequirement`; utilities (`SymphonyValidators`, `JsonReader`, `Debouncer`, `Throttler`, string and `BuildContext` extensions). |
| **networking** | `ApiClient`, a wrapper around a single Dio instance: typed `get`/`post`/`put`/`patch`/`delete`/`request`, multipart `upload`, `download`/`downloadBytes`, per-request `ApiRequestOptions`, base URL / headers / timeouts changeable at runtime, access token injection with single-flight refresh, retries with backoff and `Retry-After`, redacted logging, and mapping of every error to a `Failure`. |
| **inspector** | In-app HTTP inspector: records calls with secrets masked, shows a draggable floating button (`SymphonyInspectorOverlay`), a searchable and filterable call list, request/response detail tabs, and cURL export. |
| **auth** | `AuthAdapter` contract; configurable `RestAuthAdapter` (endpoints, response mapping, body and parser hooks); `InMemoryAuthAdapter` for demos and tests; session persistence, restoration and token refresh (`AuthRepositoryImpl`); `AuthController` (Riverpod `Notifier`); splash, login, registration and password recovery widgets. |
| **routing** | `SymphonyRouter`: a `GoRouter` with authentication-aware redirects (splash while the session is restored, sign-in with return to the requested page, guest-only pages, optional secure-by-default `defaultAccess`). `GuardedRoute` (roles, permissions, custom predicate, nested guards), `GuestRoute`, `AccessGate`, open-redirect protection. |
| **storage** | `KeyValueStorage` (secure, in-memory and prefixed implementations) with JSON helpers; `SessionStorage`; an engine-agnostic `LocalDatabase` / `LocalStore` / `StorageCodec` abstraction with in-memory and key-value implementations. |
| **dashboard** | `DashboardItem` trees (nested groups, badges, per-item access rules), permission filtering, `SymphonyDashboard` grid with inline or page submenus and GoRouter navigation. |
| **ui** | Material 3 theme (`SymphonyTheme`, `SymphonyColors`, `SymphonyRadius`, `SymphonySpacing`), buttons, text and password fields with a strength meter, loading/error/empty views, snack bars, dialogs and responsive helpers. Every default text can be overridden. |

All modules are exported by a single library:

```dart
import 'package:symphony_core/symphony_core.dart';
```

## Installation

The package is not published on pub.dev yet. Add it as a path or git
dependency. Your app also imports Riverpod and go_router directly, so declare
them too (use ranges inside the ones supported by the package):

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ">=2.4.0 <4.0.0"
  go_router: ">=10.0.0 <19.0.0"
  symphony_core:
    path: ../symphony_core
```

Dio types used in public signatures (`Interceptor`, `RequestOptions`,
`CancelToken`, `FormData`, `MultipartFile`, `HttpClientAdapter`, `Response`...)
are re-exported, so `package:dio` is only needed when you import it yourself.
Add `flutter_secure_storage` only if you name its types (for example to pass
platform options).

### Git dependency

```yaml
dependencies:
  symphony_core:
    git:
      url: https://github.com/<your-org>/symphony_core.git
      ref: v0.1.0 # a tag (recommended), a branch or a commit SHA
      # path: packages/symphony_core # only if the package is in a monorepo folder
```

### Versioned tags

Releases are tagged `vMAJOR.MINOR.PATCH`; each tag matches the `version:` in
`pubspec.yaml` and a [CHANGELOG.md](CHANGELOG.md) entry. Pin a tag in apps.
`pubspec.lock` records the resolved commit, so a branch `ref` only moves when
you run `flutter pub upgrade symphony_core`. To upgrade, change `ref` to the
new tag, read the CHANGELOG and [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md), then
run `flutter pub get`.

### pub.dev (planned)

Once published, the dependency becomes `symphony_core: ^0.1.0` (or
`flutter pub add symphony_core`). CI already runs `dart pub publish --dry-run`.
The `homepage`/`repository` fields of `pubspec.yaml` must be filled in before
the first release.

### Platform setup

Secure storage needs per-platform setup (Android backup rules, macOS keychain
entitlement, Linux `libsecret`, HTTPS on the web). See
[COMPATIBILITY.md – Platform notes](COMPATIBILITY.md#platform-notes).

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

Future<void> main() async {
  await SymphonyCore.initialize(
    config: SymphonyConfig(
      baseUrl: 'https://api.example.com',
      enableInspector: true,
      enableLogging: true,
      connectTimeout: Duration(seconds: 30),
    ),
  );
  runApp(const SymphonyScope(child: MyApp()));
}

final greetingProvider = FutureProvider<String>((ref) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.get<Map<String, dynamic>>('/greeting');
  return response.data['message'] as String;
});

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: SymphonyTheme.light(),
      darkTheme: SymphonyTheme.dark(),
      // Floating API inspector button (visible because enableInspector is true).
      builder: (context, child) => SymphonyInspectorOverlay(child: child!),
      home: const GreetingPage(),
    );
  }
}

class GreetingPage extends ConsumerWidget {
  const GreetingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final greeting = ref.watch(greetingProvider);
    return Scaffold(
      body: greeting.when(
        data: (message) => Center(child: Text(message)),
        loading: () => const SymphonyLoadingIndicator(),
        error: (error, stackTrace) => SymphonyErrorView(
          failure: error is Failure ? error : null,
          onRetry: () => ref.invalidate(greetingProvider),
        ),
      ),
    );
  }
}
```

What happens:

1. `SymphonyCore.initialize` initializes the Flutter bindings, builds a
   Riverpod container holding every service, installs the global error
   handlers (`handleGlobalErrors` is `true` by default) and registers the
   instance as `SymphonyCore.instance`. Registration is synchronous, so the
   call also works without `await`; awaiting it before `runApp` is
   recommended.
2. `SymphonyScope` exposes that container to the widget tree
   (`SymphonyCore.instance.wrap(const MyApp())` is equivalent).
3. Widgets and providers use the regular Riverpod APIs:
   `ref.watch(apiClientProvider)`. The `ApiClient` is created on first use.

`const SymphonyConfig(...)` works too. Lint sets that enable
`prefer_const_constructors` (for example flutter_lints 3.x and 4.x) suggest
adding `const` to the configuration above.

## Integration walkthrough

This walkthrough builds a complete app shell: configuration, a REST
authentication adapter, a router with guards, splash and sign-in pages, a
permission-aware dashboard and the inspector overlay. Each block is one file
of the app.

### 1. Initialize the core

```dart
// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:symphony_core/symphony_core.dart';

import 'app.dart';
import 'modules.dart';

Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(
      baseUrl: 'https://api.example.com',
      appName: 'Acme',
      enableInspector: kDebugMode,
      enableLogging: kDebugMode,
    ),
    // The adapter needs the ApiClient, so it is built from the container.
    authAdapterBuilder: (ref) => RestAuthAdapter(
      apiClient: ref.watch(apiClientProvider),
      endpoints: const RestAuthEndpoints(
        login: '/auth/login',
        refresh: '/auth/refresh',
        logout: '/auth/logout',
        currentUser: '/auth/me',
        register: '/auth/register',
        requestPasswordReset: '/auth/password/forgot',
        confirmPasswordReset: '/auth/password/reset',
      ),
    ),
    overrides: [
      dashboardItemsProvider.overrideWithValue(appModules),
    ],
  );
  runApp(const SymphonyScope(child: AcmeApp()));
}
```

Passing an adapter (`authAdapter:` or `authAdapterBuilder:`) also connects the
`ApiClient` to the session: requests get the access token, and a `401`
triggers one refresh and a replay. No backend yet? Use
`authAdapter: InMemoryAuthAdapter(accounts: [...])`
(see [Authentication](#in-memory-adapter-demos-and-tests)).

### 2. App widget, theme and inspector overlay

```dart
// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import 'router.dart';

class AcmeApp extends ConsumerWidget {
  const AcmeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Acme',
      theme: SymphonyTheme.light(),
      darkTheme: SymphonyTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      // Draggable inspector button; hidden when enableInspector is false.
      builder: (context, child) => SymphonyInspectorOverlay(child: child!),
    );
  }
}
```

### 3. Router with guards

```dart
// lib/router.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/symphony_core.dart';

import 'pages.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return SymphonyRouter.create(
    ref,
    paths: const SymphonyRoutePaths(
      guestOnlyPaths: {'/register', '/forgot-password'},
    ),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SymphonySplashScreen(),
      ),
      GuestRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GuestRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GuestRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/unauthorized',
        builder: (context, state) => const SymphonyUnauthorizedScreen(),
      ),
      GuardedRoute(
        path: '/',
        builder: (context, state) => const HomePage(),
        routes: [
          GuardedRoute(
            path: 'orders',
            access: const AccessRequirement(permissions: {'orders.read'}),
            builder: (context, state) => const OrdersPage(),
          ),
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

The routes for `/splash`, `/login`, `/` and `/unauthorized` match the
defaults of `SymphonyRoutePaths`. The router is created once; it listens to
`accessContextProvider` and re-evaluates its redirects when the user signs in
or out, or when roles change.

### 4. Splash, sign-in and account pages

```dart
// lib/pages.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/symphony_core.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SymphonyLoginScreen(
      form: SymphonyLoginForm(
        // The links are shown only when the adapter supports the feature.
        onForgotPassword: () => context.push('/forgot-password'),
        onRegister: () => context.push('/register'),
      ),
    );
  }
}

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SymphonyAuthLayout(
      appBar: AppBar(),
      title: 'Create your account',
      child: SymphonyRegisterForm(onSignIn: () => context.go('/login')),
    );
  }
}

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SymphonyAuthLayout(
      appBar: AppBar(),
      title: 'Reset your password',
      child: SymphonyForgotPasswordForm(
        enableConfirmStep: true,
        onCompleted: () => context.go('/login'),
        onBackToSignIn: () => context.go('/login'),
      ),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Hello, ${user?.displayName ?? 'there'}'),
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'API inspector',
              icon: const Icon(Icons.network_check),
              onPressed: () => showApiInspector(context),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: const SymphonyDashboard(),
    );
  }
}

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Orders')));
  }
}

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Administration')));
  }
}
```

No page navigates after sign-in or sign-out: the router reacts to the
authentication state.

### 5. Dashboard modules

```dart
// lib/modules.dart
import 'package:flutter/material.dart';
import 'package:symphony_core/symphony_core.dart';

const appModules = <DashboardItem>[
  DashboardItem(
    id: 'orders',
    label: 'Orders',
    description: 'Track and fulfil orders',
    icon: Icons.receipt_long_outlined,
    route: '/orders',
    access: AccessRequirement(permissions: {'orders.read'}),
  ),
  DashboardItem(
    id: 'admin',
    label: 'Administration',
    icon: Icons.admin_panel_settings_outlined,
    access: AccessRequirement(roles: {'admin'}),
    children: [
      DashboardItem(
        id: 'admin.users',
        label: 'Users',
        icon: Icons.group_outlined,
        route: '/admin',
      ),
      DashboardItem(
        id: 'admin.audit',
        label: 'Audit log',
        icon: Icons.history,
        route: '/admin',
        queryParameters: {'tab': 'audit'},
      ),
    ],
  ),
];
```

### 6. What happens at runtime

1. The app starts on `/`. The status is `unknown`, so the router redirects to
   `/splash`.
2. `SymphonyRouter.create` (`restoreSessionOnStart: true`) and the splash
   screen both call `AuthController.restoreSession()`; the call is idempotent.
   A stored session is loaded from secure storage, refreshed if its access
   token expired, then validated through the adapter.
3. Signed in: the router leaves the splash for the remembered location (or
   `/`). Signed out: `/` is guarded, so the user lands on `/login`.
4. After a successful sign-in on `/login` (a guest-only route), the router
   sends the user to the page they originally asked for, or `/`.
5. The dashboard shows only the modules the user may access; the guards
   enforce the same rules on the routes (`/admin` without the `admin` role
   redirects to `/unauthorized`).
6. When the server rejects the session (refresh failed), the session is
   cleared, the state becomes unauthenticated and the router returns to
   `/login`.
7. In debug builds, the floating button and the app bar action open the API
   inspector.

The splash screen does not hold the router: as soon as the status is known,
the router leaves it. If the splash must finish start-up work first
(`SymphonySplashScreen(onInitialize: ...)`), pass
`restoreSessionOnStart: false` to `SymphonyRouter.create`; the splash then
restores the session after `onInitialize` completes.

### Example app

[`example/`](example/) is a runnable app built on every module, talking to an
in-process demo backend (no server needed). Run it with
`cd example && flutter run`.

- `example/lib/main.dart`: `SymphonyCore.initialize` with a `RestAuthAdapter`
  (`authAdapterBuilder`), a secure storage with an in-memory fallback, and
  `httpClientAdapterProvider` overridden by the demo backend. Remove that
  override to call a real API.
- `example/lib/app/`: app widget, theme and router.
- `example/lib/features/`: feature modules written on top of the package.
- `example/test/`: flow tests driving the app against the demo backend.

## Configuration reference

`SymphonyConfig` is immutable; only `baseUrl` is required. Use `copyWith` to
derive variants.

| Field | Type | Default | Description |
|---|---|---|---|
| `baseUrl` | `String` | required | Base URL of the `ApiClient`. Must be absolute (relative URLs are accepted on the web only). Can be changed at runtime with `ApiClient.updateBaseUrl`. |
| `appName` | `String` | `'Symphony App'` | Display name. Default title of `SymphonySplashScreen`; included in the start-up log line. |
| `environment` | `AppEnvironment` | `AppEnvironment.development` | `development`, `staging`, `production` (`isProduction: true`) or a custom `AppEnvironment('qa')`. |
| `enableInspector` | `bool` | `false` | Records HTTP traffic in the API inspector. When `false`, the inspector interceptor is not installed and `SymphonyInspectorOverlay` hides its button. |
| `enableLogging` | `bool` | `false` | Enables the shared logger and the redacted HTTP logging interceptor. |
| `logLevel` | `LogLevel` | `LogLevel.debug` | Minimum level written when logging is enabled (`verbose`, `debug`, `info`, `warning`, `error`, `none`). |
| `logRequestBodies` | `bool` | `true` | Includes request bodies in logs and in the inspector. |
| `logResponseBodies` | `bool` | `true` | Includes response bodies in logs and in the inspector. |
| `connectTimeout` | `Duration` | 30 s | Maximum time to establish a connection. |
| `receiveTimeout` | `Duration` | 30 s | Maximum time between two received data packets. |
| `sendTimeout` | `Duration` | 30 s | Maximum time to send the request body. |
| `defaultHeaders` | `Map<String, String>` | `{}` | Headers sent with every request (for example `Accept-Language`). |
| `authHeaderName` | `String` | `'Authorization'` | Header carrying the access token. Always masked in logs and in the inspector. |
| `authTokenPrefix` | `String` | `'Bearer'` | Produces `<prefix> <token>`. An empty string sends the raw token. |
| `refreshTokenStatusCodes` | `Set<int>` | `{401}` | Statuses that trigger a token refresh followed by one replay of the request. |
| `maxRetries` | `int` | `0` | Automatic retries of idempotent requests (GET, HEAD, OPTIONS, PUT, DELETE) after connectivity errors, timeouts or a status in `retryStatusCodes`. `0` disables retries. Must be `>= 0`. |
| `retryDelay` | `Duration` | 500 ms | Base delay between retries, multiplied by the attempt number. A longer `Retry-After` (in seconds, up to 30 s) is honoured. |
| `retryStatusCodes` | `Set<int>` | `{408, 429, 502, 503, 504}` | Statuses considered transient. |
| `inspectorMaxEntries` | `int` | `200` | Calls kept by the inspector; the oldest are dropped. Must be `> 0`. |
| `maxLoggedBodyLength` | `int` | `4000` | Bodies longer than this many characters are truncated in logs and in the inspector. Must be `> 0`. |
| `sensitiveKeys` | `Set<String>` | `LogRedactor.defaultSensitiveKeys` | Header, JSON field and URL parameter (query and fragment) names whose values are masked in logs and in the inspector. A key matches when its lower-case form without `-`, `_`, `.` and spaces contains an entry. Defaults: `authorization`, `password`, `passwd`, `token`, `secret`, `cookie`, `apikey`, `credential`, `session`. |
| `handleGlobalErrors` | `bool` | `true` | `SymphonyCore.initialize` installs `GlobalErrorHandler` (`FlutterError.onError` and `PlatformDispatcher.onError`), reporting to `errorReporterProvider`. Ignored by `SymphonyCore.create`. |
| `extras` | `Map<String, Object?>` | `{}` | Project-specific values. Read them with `config.extra<T>('key')`, which returns `null` when the value is missing or not a `T`. |

Other members: `copyWith(...)` (every field) and `redactor` (a `LogRedactor`
built from `sensitiveKeys`). `SymphonyConfig` has no value equality.

Per-environment configuration with `--dart-define`:

```dart
SymphonyConfig configFor(String environment) {
  const base = SymphonyConfig(
    baseUrl: 'https://dev.api.example.com',
    appName: 'Acme',
  );
  return switch (environment) {
    'production' => base.copyWith(
        baseUrl: 'https://api.example.com',
        environment: AppEnvironment.production,
      ),
    'staging' => base.copyWith(
        baseUrl: 'https://staging.api.example.com',
        environment: AppEnvironment.staging,
        enableInspector: true,
      ),
    _ => base.copyWith(enableInspector: true, enableLogging: true),
  };
}

Future<void> main() async {
  const environment = String.fromEnvironment('APP_ENV');
  await SymphonyCore.initialize(config: configFor(environment));
  runApp(const SymphonyScope(child: MyApp()));
}
```

Run it with `flutter run --dart-define=APP_ENV=staging`.

## Core: entry point, DI, errors, logging

### SymphonyCore

| Member | Description |
|---|---|
| `SymphonyCore.initialize({required config, authAdapter, authAdapterBuilder, secureStorage, errorReporter, overrides, restoreSession = false, parent, localDatabase})` | Creates the app-wide instance and registers it as `SymphonyCore.instance`. Calling it again disposes the previous instance (a failing re-initialization keeps it). With `restoreSession: true` and an adapter, it awaits the session restoration; a failure is reported and logged, never thrown. |
| `SymphonyCore.create({...same..., installErrorHandlers = false})` | Independent instance, not registered globally (tests, several instances). Does not initialize the bindings, restore the session or read `handleGlobalErrors`. The caller disposes it. |
| `SymphonyCore.instance`, `SymphonyCore.isInitialized` | The registered instance (`StateError` before `initialize`). |
| `SymphonyCore.reset()` | `@visibleForTesting`: disposes and unregisters the global instance. |
| `core.container`, `core.config`, `core.hasAuth`, `core.isDisposed` | The Riverpod container, the resolved configuration, whether an adapter is configured. |
| `core.read(provider)`, `core.apiClient`, `core.logger`, `core.auth` | Access from outside the widget tree. `auth` (the `AuthController`) throws a `StateError` without an adapter. |
| `core.wrap(app)` | `SymphonyScope(core: core, child: app)`. |
| `core.dispose()` | Uninstalls the error handlers and disposes every service. Idempotent; members throw afterwards. |

Parameters of `initialize` / `create`:

- `authAdapter` **or** `authAdapterBuilder` (`AuthAdapter Function(Ref ref)`,
  for adapters that need other providers such as the `ApiClient`). Passing
  both throws an `ArgumentError`.
- `secureStorage`: replaces `secureStorageProvider` (for example an
  `InMemoryKeyValueStorage` in tests).
- `localDatabase`: replaces `localDatabaseProvider` with a database your app
  owns (it opens and closes it; disposing the core does not close it).
- `errorReporter`: replaces `errorReporterProvider`.
- `overrides`: your own provider overrides, applied last (they win over the
  built-in ones).
- `parent` (advanced): creates the container as a child of an existing one
  whose root was created with `symphonyOverrides(...)`. `config` must then be
  the same instance the parent provides, and `authAdapter`,
  `authAdapterBuilder`, `secureStorage`, `localDatabase` and `errorReporter`
  must be `null`.
  Most apps nest `ProviderScope`s below `SymphonyScope` instead.

### Without SymphonyCore: `symphonyOverrides`

Apps that manage their own root `ProviderScope` can apply the same
configuration with `symphonyOverrides`:

```dart
void main() {
  runApp(
    ProviderScope(
      overrides: symphonyOverrides(
        config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
        authAdapter: InMemoryAuthAdapter(),
        overrides: [
          dashboardItemsProvider.overrideWithValue(const <DashboardItem>[]),
        ],
      ),
      child: const MyApp(),
    ),
  );
}
```

It returns, in order: the configuration, the adapter and the session token
delegate (when an adapter is given), `secureStorage`, `localDatabase`,
`errorReporter`, then your `overrides`. Put it in the **root**
`ProviderScope`: the package's providers declare no Riverpod
`dependencies`, so overriding them in a nested scope does not reach them. In
this mode `SymphonyCore.instance` does not exist and no global error handler
is installed (see [`GlobalErrorHandler`](#errors-and-results)).

> On Riverpod 3 the `Override` type is not exported by
> `package:flutter_riverpod/flutter_riverpod.dart`. Pass list literals
> directly (`overrides: [a.overrideWithValue(x)]`) and let Dart infer the
> type, or import `package:flutter_riverpod/misc.dart` (Riverpod 3 only) to
> write `List<Override>`.

### Errors and results

Every expected error is a `Failure` (it implements `Exception`). The data
layer converts Dio, platform and parsing errors into failures; the UI never
sees infrastructure exceptions.

| Failure | Typical cause |
|---|---|
| `NetworkFailure` | Offline, DNS, refused connection, TLS. |
| `TimeoutFailure` | Connect, send or receive timeout. |
| `UnauthorizedFailure` | HTTP 401 or expired session. |
| `ForbiddenFailure` | HTTP 403. |
| `NotFoundFailure` | HTTP 404. |
| `ValidationFailure` | HTTP 400/422 or local validation; `fieldErrors` and `errorFor(field)`. |
| `ServerFailure` | Other HTTP statuses; `statusCode` and decoded `data`. |
| `AuthFailure` | Wrong credentials, rejected session. |
| `CancelledFailure` | Request cancelled with a `CancelToken`. |
| `ParsingFailure` | Response could not be decoded into the expected type. |
| `StorageFailure` | Local storage error (`code` from `StorageFailureCodes`). |
| `UnsupportedFailure` | Feature not supported by the adapter or the platform. |
| `UnexpectedFailure` | Anything else (`UnexpectedFailure.fromError`). |

Each failure has `message` (safe to show), `code`, `statusCode`, `cause` and
`stackTrace`. Extend `Failure` for app-specific cases.

`Result<T>` (a sealed class: `ResultSuccess` / `ResultFailure`) is returned at
repository boundaries. `guardResult` turns a throwing body into a result:

```dart
Future<Result<int>> countOrders(ApiClient client) {
  return guardResult(() async {
    final response = await client.get<Map<String, dynamic>>('/orders/count');
    return response.data['count'] as int;
  });
}

Future<String> describeOrders(ApiClient client) async {
  final result = await countOrders(client);
  return switch (result) {
    ResultSuccess(:final value) => '$value orders',
    ResultFailure(:final failure) => failure.message,
  };
}
```

`Result` also offers `isSuccess`, `valueOrNull`, `failureOrNull`, `when`,
`map`, `mapFailure`, `flatMap`, `getOrElse` and `getOrThrow`.

Unexpected errors go to an `ErrorReporter`. Plug in your crash reporting SDK
by implementing it (reporters must never throw):

```dart
class CrashReporter extends ErrorReporter {
  const CrashReporter();

  @override
  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    // Forward to Sentry, Crashlytics...
  }
}

Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    errorReporter: const CrashReporter(),
  );
  runApp(const SymphonyScope(child: MyApp()));
}
```

Built-in reporters: `LoggerErrorReporter` (default, writes to the logger),
`NoopErrorReporter` and `CompositeErrorReporter([...])`.

With `handleGlobalErrors: true`, framework errors (`FlutterError.onError`) are
reported as non-fatal and uncaught root-isolate errors
(`PlatformDispatcher.onError`) as fatal; previously installed handlers keep
being called. For full control, set `handleGlobalErrors: false` and call
`GlobalErrorHandler.install(reporter: ..., presentFlutterErrorsInDebug: false)`
yourself (useful when another SDK already prints errors, which would
otherwise appear twice in debug builds). `GlobalErrorHandler.runGuarded`
additionally runs `main` in a guarded zone.

### Logging

`symphonyLoggerProvider` is a `SymphonyLogger` enabled by
`config.enableLogging` at `config.logLevel`. HTTP logs are written by the
`SecureLoggingInterceptor` with headers, query parameters and JSON fields
masked by `LogRedactor`. Route logs elsewhere with a custom `LogSink`:

```dart
class RemoteLogSink extends LogSink {
  const RemoteLogSink();

  @override
  void write(LogEntry entry) {
    // entry.level, entry.tag, entry.message, entry.error, entry.time
  }
}

Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(
      baseUrl: 'https://api.example.com',
      enableLogging: true,
      logLevel: LogLevel.info,
    ),
    overrides: [
      symphonyLoggerProvider.overrideWith((ref) {
        final config = ref.watch(symphonyConfigProvider);
        return SymphonyLogger(
          enabled: config.enableLogging,
          minLevel: config.logLevel,
          tag: 'Symphony',
          sinks: const [DebugPrintLogSink(), RemoteLogSink()],
        );
      }),
    ],
  );
  runApp(const SymphonyScope(child: MyApp()));
}
```

The logger never redacts free-form messages itself: redact secrets with
`LogRedactor` before logging them.

### Access control primitives

`AccessContext` (status, roles, permissions, attributes) describes the
current user; `AccessRequirement` describes what a route, dashboard item or
widget needs. Guards, menus and `AccessGate` all evaluate
`AccessRequirement.isSatisfiedBy(AccessContext)`:

```dart
bool isProPlan(AccessContext access) => access.attributes['plan'] == 'pro';

const anyone = AccessRequirement.public(); // also AccessRequirement.none
const signedIn = AccessRequirement(); // also AccessRequirement.authenticated
const adminOrOwner = AccessRequirement(roles: {'admin', 'owner'}); // any role
const ordersEditor = AccessRequirement(
  permissions: {'orders.read', 'orders.write'}, // all permissions
);
const reportsReader = AccessRequirement(
  permissions: {'reports.read', 'reports.admin'},
  permissionMatch: MatchMode.any,
);
const proPlan = AccessRequirement(predicate: isProPlan); // runs last
```

With the auth module, roles and permissions come from `AuthUser.roles` /
`AuthUser.permissions`, and `attributes` from `AuthUser.data`.

### Utilities

- `SymphonyValidators`: `required`, `email`, `phone`, `minLength`,
  `maxLength`, `pattern`, `numeric`, `match` and `compose`, each returning a
  `FormFieldValidator<String>` with an overridable `message`.
- `JsonReader`: never-throwing readers for loosely typed JSON (`readPath`
  with dotted paths, `asString`, `asInt`, `asDouble`, `asBool`,
  `asDateTime`, `asMap`, `asList`, `asListOf`, `asStringSet`).
- `Debouncer` and `Throttler` for UI events.
- Extensions: `String?.isBlank` / `isNotBlank` / `nullIfBlank`,
  `String.capitalize()` / `truncate(max)`, and `BuildContext.theme`,
  `colorScheme`, `textTheme`, `isDarkMode`, `unfocus()`.

```dart
final emailValidator = SymphonyValidators.compose([
  SymphonyValidators.required(message: 'Enter your e-mail.'),
  SymphonyValidators.email(),
]);

int? retryAfterSeconds(Map<String, dynamic> body) =>
    JsonReader.asInt(JsonReader.readPath(body, 'error.details.retryAfter'));
```

## Networking

### Getting the client

There is one `ApiClient` per `SymphonyCore` instance:
`ref.watch(apiClientProvider)` in providers and widgets,
`SymphonyCore.instance.apiClient` elsewhere. Repositories receive it and
never touch Dio:

```dart
class OrderRepository {
  const OrderRepository(this._client);

  final ApiClient _client;

  Future<Result<List<Order>>> fetchOrders({int page = 1}) {
    return guardResult(() async {
      final response = await _client.get<List<Order>>(
        '/orders',
        queryParameters: {'page': page},
        decoder: (data) => [
          for (final item in data! as List<dynamic>)
            Order.fromJson(item as Map<String, dynamic>),
        ],
      );
      return response.data;
    });
  }

  Future<Order> create(Order order) async {
    final response = await _client.post<Order>(
      '/orders',
      data: order.toJson(),
      decoder: (data) => Order.fromJson(data! as Map<String, dynamic>),
    );
    return response.data;
  }

  Future<void> delete(String id) => _client.delete<void>('/orders/$id');
}

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(ref.watch(apiClientProvider)),
);

final ordersProvider = FutureProvider<List<Order>>((ref) async {
  final result = await ref.watch(orderRepositoryProvider).fetchOrders();
  return result.getOrThrow();
});
```

### Request methods

| Method | Notes |
|---|---|
| `get<T>(path, {queryParameters, options, decoder, cancelToken, onReceiveProgress})` | |
| `post<T>` / `put<T>` / `patch<T>(path, {data, queryParameters, options, decoder, cancelToken, onSendProgress, onReceiveProgress})` | `data`: a JSON-encodable object, `FormData`, a `String`... |
| `delete<T>(path, {data, queryParameters, options, decoder, cancelToken})` | |
| `request<T>(path, {method = 'GET', data, queryParameters, options, decoder, cancelToken, onSendProgress, onReceiveProgress, responseType})` | Any HTTP method; `responseType` for plain text, bytes or streams. |
| `upload<T>(path, {required files, fields, method = 'POST', ...})` | `multipart/form-data` from `UploadFile`s and form fields. |
| `download(path, savePath, {..., deleteOnError = true})` | Writes to a file. Not supported on the web (`UnsupportedFailure`). |
| `downloadBytes(path, {...})` | Returns `ApiResponse<Uint8List>`; also available on the web. |

Every method returns an `ApiResponse<T>` (`data`, `statusCode`,
`statusMessage`, lower-cased `headers`, `header(name)`, `requestUri`,
`isSuccessful`, `map`) and throws a `Failure` on error. Without a `decoder`
the body is cast to `T` (`Map<String, dynamic>`, `List<dynamic>`, `String`,
`void`...). A decoder error or a failed cast throws a `ParsingFailure`; a
`Failure` thrown by a decoder propagates unchanged.

### Per-request options

`ApiRequestOptions` controls one request:

| Field | Default | Effect |
|---|---|---|
| `headers` | `{}` | Extra headers; they take precedence over every other header source. |
| `requiresAuth` | `true` | Attach the access token. |
| `refreshOnUnauthorized` | `true` | Refresh the token and replay once on a status in `refreshTokenStatusCodes`. |
| `retry` | `true` | Allow automatic retries (idempotent methods only). |
| `maxRetries` | `null` | Overrides `SymphonyConfig.maxRetries`. |
| `connectTimeout`, `receiveTimeout`, `sendTimeout` | `null` | Per-request timeouts. |
| `contentType` | `null` | Body content type, e.g. `Headers.formUrlEncodedContentType`. |
| `inspect` | `true` | Record the call in the inspector. |
| `log` | `true` | Write the call to the logs. |
| `extra` | `{}` | Copied into Dio's `RequestOptions.extra` (for your interceptors). |

`ApiRequestOptions.unauthenticated` (no token, no refresh) is meant for
public endpoints such as sign-in, refresh, registration and password
recovery.

```dart
Future<void> requestExamples(ApiClient client) async {
  // Public endpoint: no token, a 401 never triggers a refresh.
  await client.post<void>(
    '/newsletter',
    data: {'email': 'ada@example.com'},
    options: ApiRequestOptions.unauthenticated,
  );

  // Slow export: longer receive timeout, up to 3 retries, not inspected.
  await client.get<Map<String, dynamic>>(
    '/reports/yearly',
    options: const ApiRequestOptions(
      receiveTimeout: Duration(minutes: 2),
      maxRetries: 3,
      inspect: false,
    ),
  );

  // Form-encoded body with an extra header.
  await client.post<Map<String, dynamic>>(
    '/oauth/token',
    data: {'grant_type': 'client_credentials'},
    options: const ApiRequestOptions(
      requiresAuth: false,
      contentType: Headers.formUrlEncodedContentType,
      headers: {'X-Client': 'mobile'},
    ),
  );

  // Cancellation surfaces as a CancelledFailure.
  final cancelToken = CancelToken();
  final search = client.get<List<dynamic>>(
    '/search',
    queryParameters: {'q': 'flutter'},
    cancelToken: cancelToken,
  );
  cancelToken.cancel();
  try {
    await search;
  } on CancelledFailure {
    // Superseded by a newer search.
  }
}
```

### Runtime base URL, headers and timeouts

```dart
void useStaging(ApiClient client) {
  client.updateBaseUrl('https://staging.api.example.com'); // ArgumentError if invalid
  client.setHeader('X-Tenant', 'acme'); // null removes the header
  client.updateTimeouts(receiveTimeout: const Duration(seconds: 60));
}

class BaseUrlLabel extends ConsumerWidget {
  const BaseUrlLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return ValueListenableBuilder<String>(
      valueListenable: client.baseUrlListenable,
      builder: (context, baseUrl, child) => Text(baseUrl),
    );
  }
}
```

`resetBaseUrl()` restores `config.baseUrl`; `headers` returns a read-only
snapshot of the default headers. Repositories keep using relative paths, so
switching environments needs no code change.

### Uploads and downloads

```dart
Future<String> uploadAvatar(ApiClient client, List<int> bytes) async {
  final response = await client.upload<Map<String, dynamic>>(
    '/me/avatar',
    files: [
      UploadFile.fromBytes(
        bytes,
        filename: 'avatar.png',
        field: 'avatar',
        contentType: 'image/png',
      ),
    ],
    fields: {'visibility': 'public'},
    onSendProgress: (sent, total) => debugPrint('$sent / $total bytes'),
  );
  return response.data['url'] as String;
}

Future<void> saveReport(ApiClient client, String savePath) async {
  if (kIsWeb) {
    final response = await client.downloadBytes('/reports/2026.pdf');
    debugPrint('Received ${response.data.length} bytes');
    return;
  }
  await client.download('/reports/2026.pdf', savePath);
}
```

`UploadFile.fromPath(path)` reads a device file (not on the web: use
`fromBytes`). Form `fields`: `null` values are skipped, lists become repeated
entries, maps are JSON-encoded and `DateTime`s ISO-8601 strings. Always pass
`contentType`: dio 5.4 sends files without one as
`application/octet-stream`.

### Error mapping

`DefaultApiErrorMapper` converts every error into a `Failure`:

| Error | Failure |
|---|---|
| Cancelled request | `CancelledFailure` |
| Connect / send / receive timeout | `TimeoutFailure` |
| Connection error, bad certificate | `NetworkFailure` |
| HTTP 400 / 422 | `ValidationFailure` (with `fieldErrors`) |
| HTTP 401 | `UnauthorizedFailure` |
| HTTP 403 | `ForbiddenFailure` |
| HTTP 404 | `NotFoundFailure` |
| Other HTTP status | `ServerFailure` (`statusCode`, decoded `data`) |
| Socket or TLS error reported as "unknown" | `NetworkFailure` |
| Malformed JSON | `ParsingFailure` |
| Anything else | `UnexpectedFailure` |

The message is read from the response body (keys `message`,
`error_description`, `error`, `detail`, `title`, `msg`, also inside nested
objects), the code from `code`, `error_code` or `errorCode`, and field errors
from `errors`, shaped either as `{"errors": {"email": ["is invalid"]}}` or as
`{"errors": [{"field": "email", "message": "is invalid"}]}`. Every fallback
message is a constructor parameter, so you can localize them or extend the
mapper:

```dart
class AcmeErrorMapper extends DefaultApiErrorMapper {
  const AcmeErrorMapper()
      : super(
          fieldErrorsKey: 'violations',
          networkMessage: 'You are offline.',
          serverErrorMessage: 'Our servers are having trouble.',
        );

  @override
  Failure mapResponseError(DioException error, StackTrace stackTrace) {
    if (error.response?.statusCode == 409) {
      return ValidationFailure(
        'This record was changed by someone else.',
        statusCode: 409,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return super.mapResponseError(error, stackTrace);
  }
}

Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    overrides: [
      apiErrorMapperProvider.overrideWithValue(const AcmeErrorMapper()),
    ],
  );
  runApp(const SymphonyScope(child: MyApp()));
}
```

Handling failures in the UI:

```dart
class SubmitOrderButton extends ConsumerStatefulWidget {
  const SubmitOrderButton({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<SubmitOrderButton> createState() => _SubmitOrderButtonState();
}

class _SubmitOrderButtonState extends ConsumerState<SubmitOrderButton> {
  Future<void> _submit() async {
    final client = ref.read(apiClientProvider);
    try {
      await client.post<void>('/orders', data: widget.order.toJson());
      if (!mounted) return;
      SymphonySnackbar.success(context, 'Order created');
    } on ValidationFailure catch (failure) {
      if (!mounted) return;
      SymphonySnackbar.error(context, failure.errorFor('quantity') ?? failure.message);
    } on Failure catch (failure) {
      if (!mounted) return;
      SymphonySnackbar.showFailure(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SymphonyButton(label: 'Submit', onPressed: _submit);
  }
}
```

`apiClient.mapError(error, stackTrace)` exposes the mapper, for example
`guardResult(body, mapError: client.mapError)`.

### Interceptors and header providers

Interceptor order (requests, responses and errors):

1. API inspector (when `enableInspector` is true)
2. Secure logging (when `enableLogging` is true)
3. Your interceptors (`apiInterceptorsProvider`, then `ApiClient.addInterceptor`)
4. `HeadersInterceptor` (header providers)
5. `AuthTokenInterceptor` (token injection and refresh)
6. `RetryInterceptor`

```dart
class CorrelationIdInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Correlation-Id'] =
        DateTime.now().microsecondsSinceEpoch.toString();
    handler.next(options);
  }
}

String currentLanguage() => 'en';

Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    overrides: [
      apiInterceptorsProvider.overrideWithValue([CorrelationIdInterceptor()]),
      // Evaluated before every request; may be async.
      apiHeaderProvidersProvider.overrideWithValue([
        () => {'Accept-Language': currentLanguage()},
        () async => {'X-App-Version': '1.4.0'},
      ]),
    ],
  );
  runApp(const SymphonyScope(child: MyApp()));
}
```

Header precedence: per-request `headers` > header providers > default headers
and earlier interceptors. A header provider that throws is skipped and logged
by error type only. At runtime use `addInterceptor` / `removeInterceptor` and
`addHeaderProvider` / `removeHeaderProvider`. `apiClient.dio` exposes the Dio
instance for advanced cases; prefer the APIs above.

### Tokens without the auth module

The token logic talks to an `AuthTokenDelegate`. The auth module provides one
automatically; apps that manage tokens themselves implement it:

```dart
class StaticTokenDelegate extends AuthTokenDelegate {
  const StaticTokenDelegate(this.token);

  final String token;

  @override
  Future<String?> getAccessToken() async => token;

  @override
  Future<String?> refreshAccessToken() async => null; // cannot refresh

  @override
  Future<void> onSessionExpired() async {}
}

Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    overrides: [
      authTokenDelegateProvider.overrideWithValue(
        const StaticTokenDelegate('api-key-from-secure-config'),
      ),
    ],
  );
  runApp(const SymphonyScope(child: MyApp()));
}
```

Refresh behaviour: concurrent `401`s share one `refreshAccessToken()` call;
each request is replayed once with the new token; if refreshing fails or the
replay is rejected again, `onSessionExpired()` is called once. Requests with a
caller-set `Authorization` header, `requiresAuth: false` or a stream body are
never refreshed. Requests issued from inside `refreshAccessToken` /
`onSessionExpired` never wait for a refresh, so a refresh call cannot
deadlock or loop.

## API inspector

Enable recording with `SymphonyConfig(enableInspector: true)` (typically
`kDebugMode` or non-production environments), then add an entry point:

- **Floating button** for the whole app:
  `MaterialApp(.router)(builder: (context, child) => SymphonyInspectorOverlay(child: child!))`.
  It shows the call count and an error badge, can be dragged and snaps to
  the nearest edge; tapping opens the inspector above the app. `enabled`
  defaults to `config.enableInspector`.
- **Menu entry**: `showApiInspector(context)` pushes the inspector screen.
- **Route**: `ApiInspectorScreen()` is a regular widget.

```dart
final debugRoutes = [
  GoRoute(
    path: '/debug/network',
    builder: (context, state) => const ApiInspectorScreen(
      title: 'Network',
      strings: ApiInspectorStrings(
        searchHint: 'Filter by URL, method or status',
        emptyTitle: 'No requests yet',
      ),
    ),
  ),
];
```

The screen lists calls newest first with live updates, a search field (all
terms must match method, URL, status or error), status filters (success,
`4xx`, `5xx`, failed, pending) with counts, pause/resume of recording and
clear-all. The
detail screen has Overview, Request and Response tabs with copy buttons and
a cURL export.

What is recorded:

- Header values, URL parameters and JSON fields whose names match
  `sensitiveKeys` are masked (`***`), as are the `authHeaderName` header, URL
  credentials and bearer tokens in free text.
- Bodies are truncated to `maxLoggedBodyLength`; `logRequestBodies` /
  `logResponseBodies` control whether they are kept. Binary and stream
  bodies are replaced by placeholders.
- `ApiRequestOptions(inspect: false)` skips a request; the pause button sets
  `ApiInspector.enabled = false` at runtime.
- At most `inspectorMaxEntries` calls are kept.

Every label is in `ApiInspectorStrings`. Programmatic access:
`ref.read(apiInspectorProvider)` (`calls`, `errorCount`, `clear()`,
`enabled`). The cURL command contains the masked values: fill them in before
running it.

## Authentication

### Concepts

- **`AuthAdapter`**: your backend's sign-in API (login, refresh, logout,
  current user, registration, password recovery, session validation). It
  throws `Failure`s.
- **`AuthRepository`** (`AuthRepositoryImpl`): combines the adapter with
  `SessionStorage`; restores, refreshes, persists and clears sessions.
- **`AuthController`** (`authControllerProvider`): the app-facing
  `Notifier<AuthState>`. Its actions never throw; they return a `Result`.
- **`AuthState`**: `AuthUnknown` (at start) → `AuthAuthenticated(session)` or
  `AuthUnauthenticated(failure?)`.
- **Session**: `AuthSession(tokens: AuthTokens(...), user: AuthUser(...))`.
  `AuthUser` carries `roles`, `permissions` and the raw `data`, which feed
  `accessContextProvider`.

### REST adapter

`RestAuthAdapter` covers typical REST/JSON backends. Every call goes through
the `ApiClient`, so base URL, headers, logging, the inspector and error
mapping apply. There are no default paths: declare yours.

```dart
Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    authAdapterBuilder: (ref) => RestAuthAdapter(
      apiClient: ref.watch(apiClientProvider),
      endpoints: const RestAuthEndpoints(
        login: '/auth/login',
        refresh: '/auth/token/refresh',
        logout: '/auth/logout',
        currentUser: '/users/me',
        register: '/auth/register',
        requestPasswordReset: '/auth/password/forgot',
        confirmPasswordReset: '/auth/password/reset',
      ),
      // Where tokens and user fields live in the responses.
      mapping: const AuthResponseMapping(
        accessToken: ['data.jwt'],
        refreshToken: ['data.refresh'],
        user: ['data.account'],
        userRoles: ['groups', ...AuthResponseMapping.defaultUserRolesPaths],
      ),
      refreshTokenField: 'refresh', // body of the refresh call: {"refresh": "..."}
      loginBody: (credentials) => {...credentials.fields, 'device': 'mobile'},
      sessionValidator: (session) {
        if (!(session.user?.roles.contains('staff') ?? false)) {
          throw const AuthFailure('This app is reserved for staff members.');
        }
      },
    ),
  );
  runApp(const SymphonyScope(child: MyApp()));
}
```

- **Endpoints**: only `login` is required. A missing `refresh` means an
  expired session signs the user out; a missing `logout` only clears the
  local session; a missing `currentUser` keeps the user from the sign-in
  response; `register` and `requestPasswordReset` enable
  `supportsRegistration` / `supportsPasswordRecovery` (the forms hide their
  links otherwise). The `...Method` fields change HTTP methods.
- **Mapping**: each field of `AuthResponseMapping` is a list of candidate
  dotted paths (`data.user.id`, `items.0.token`, `''` for the root); the
  first that resolves wins. The defaults understand common shapes such as
  `{"access_token", "refresh_token", "expires_in"}`,
  `{"accessToken", "user": {...}}` and `{"data": {"token", "user"}}`. Expiry
  comes from `expires_in` (seconds), `expires_at` (ISO-8601 or epoch) or, as a
  fallback, the JWT `exp` claim (read without signature verification; only
  used as an expiry hint). Roles and permissions accept a string (comma
  separated), a list of strings or objects, or a map of boolean flags.
- **Hooks**: `loginBody`, `refreshBody`, `refreshHeaders`, `logoutBody`,
  `registerBody`, `requestPasswordResetBody`, `confirmPasswordResetBody`
  build request bodies; `parseSession`, `parseRefresh`, `parseUser`,
  `parseRegistration` replace the mapping; `sessionValidator` applies business
  rules after sign-in and restoration.
- **Request policies**: sign-in, refresh, registration and recovery use
  `ApiRequestOptions.unauthenticated`; sign-out sends the token explicitly and
  never triggers a refresh. A `401` on sign-in becomes an `AuthFailure` with
  `invalidCredentialsMessage` unless the server sent its own message.

### Custom adapter

Extend `AuthAdapter` for anything else (GraphQL, OAuth SDKs, Firebase...).
Only `login` is abstract:

```dart
class GraphQlAuthAdapter extends AuthAdapter {
  GraphQlAuthAdapter(this._client);

  final ApiClient _client;

  static const _signIn = r'''
mutation SignIn($email: String!, $password: String!) {
  signIn(email: $email, password: $password) {
    token refreshToken user { id name roles }
  }
}''';

  @override
  Future<AuthSession> login(AuthCredentials credentials) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/graphql',
      data: {
        'query': _signIn,
        'variables': {
          'email': credentials['email'],
          'password': credentials['password'],
        },
      },
      options: ApiRequestOptions.unauthenticated,
    );
    final payload = JsonReader.asMap(
      JsonReader.readPath(response.data, 'data.signIn'),
    );
    final token = JsonReader.asString(payload?['token']);
    if (payload == null || token == null) {
      throw const AuthFailure('Invalid e-mail or password.');
    }
    final user = JsonReader.asMap(payload['user']) ?? const <String, Object?>{};
    return AuthSession(
      tokens: AuthTokens(
        accessToken: token,
        refreshToken: JsonReader.asString(payload['refreshToken']),
      ),
      user: AuthUser(
        id: JsonReader.asString(user['id']) ?? '',
        displayName: JsonReader.asString(user['name']),
        roles: JsonReader.asStringSet(user['roles']) ?? const <String>{},
      ),
    );
  }

  // Optional overrides: refresh (default: throws UnauthorizedFailure),
  // logout (default: no-op), fetchCurrentUser (default: session.user),
  // validateSession (default: accepts), supportsRegistration + register,
  // supportsPasswordRecovery + requestPasswordReset / confirmPasswordReset.
  @override
  Future<void> validateSession(AuthSession session) async {
    if (session.user?.roles.isEmpty ?? true) {
      throw const AuthFailure('Your account has no access to this app.');
    }
  }
}
```

Register it with
`authAdapterBuilder: (ref) => GraphQlAuthAdapter(ref.watch(apiClientProvider))`.

### In-memory adapter (demos and tests)

`InMemoryAuthAdapter` is a complete fake backend: accounts, expiring access
tokens, rotating refresh tokens, sign-out, registration, password recovery
with generated codes, simulated latency and failure injection. **Not for
production**: passwords are stored in plain text and tokens are unsigned.

```dart
final demoAuthAdapter = InMemoryAuthAdapter(
  accounts: const [
    InMemoryAccount(
      identifier: 'admin@example.com',
      password: 'admin123',
      user: AuthUser(
        id: '1',
        displayName: 'Ada Admin',
        roles: {'admin'},
        permissions: {'orders.read', 'orders.write'},
      ),
    ),
    InMemoryAccount(
      identifier: 'user@example.com',
      password: 'user1234',
      user: AuthUser(id: '2', displayName: 'Uma User', permissions: {'orders.read'}),
    ),
  ],
  latency: const Duration(milliseconds: 400),
  onResetCodeIssued: (identifier, code) => debugPrint('Code for $identifier: $code'),
  // failureInjector: (operation) => operation == InMemoryAuthOperation.refresh
  //     ? const NetworkFailure()
  //     : null,
);
```

### Using the controller

```dart
class AccountMenu extends ConsumerWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tell the user when the server ended the session.
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (previous is AuthAuthenticated &&
          next is AuthUnauthenticated &&
          next.failure != null) {
        SymphonySnackbar.warning(context, next.failure!.message);
      }
    });

    final state = ref.watch(authControllerProvider);
    return switch (state) {
      AuthUnknown() => const SymphonyLoadingIndicator(size: 20),
      AuthAuthenticated(:final session) => TextButton(
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          child: Text('Sign out ${session.user?.displayName ?? ''}'),
        ),
      AuthUnauthenticated() => const Text('Signed out'),
    };
  }
}

class CustomSignInForm extends ConsumerStatefulWidget {
  const CustomSignInForm({super.key});

  @override
  ConsumerState<CustomSignInForm> createState() => _CustomSignInFormState();
}

class _CustomSignInFormState extends ConsumerState<CustomSignInForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final result = await ref.read(authControllerProvider.notifier).login(
          AuthCredentials.emailPassword(
            email: _email.text,
            password: _password.text,
          ),
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result case ResultFailure(:final failure)) {
      SymphonySnackbar.showFailure(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SymphonyTextField(controller: _email, label: 'E-mail'),
        SymphonyPasswordField(controller: _password),
        SymphonyButton(
          label: 'Sign in',
          isLoading: _submitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}
```

Controller API: `restoreSession({force = false})` (idempotent; `force`
retries or revalidates), `login(credentials)`, `logout()` (always ends
signed out), `register(data)`, `requestPasswordReset(data)`,
`confirmPasswordReset(data)`, `updateSession(session)` (for example after a
profile update; only while signed in), `handleSessionExpired([failure])`,
plus `session`, `supportsRegistration` and `supportsPasswordRecovery`.
Derived providers: `currentUserProvider`, `isAuthenticatedProvider`,
`accessContextProvider`.

Session lifecycle:

- Restoration (`restoreSession`): no stored tokens → signed out. Expired
  access token (30 s leeway) with a refresh token → refresh. A rejected
  refresh clears the session; a network error, timeout or 5xx keeps the
  stored session (offline start). Then `fetchCurrentUser` and
  `validateSession` run.
- At runtime, refresh is reactive: the `ApiClient` refreshes after a `401`.
- `logout()` calls the adapter best-effort and always clears local data.

### Ready-made widgets

| Widget | Purpose |
|---|---|
| `SymphonySplashScreen` | Start-up screen: runs `onInitialize(ref)`, restores the session, stays at least `minDisplayDuration` (600 ms) before `onCompleted`; shows an error view with retry when `onInitialize` throws. Never navigates by itself. |
| `SymphonyLoginScreen` | `SymphonyAuthLayout` + `SymphonyLoginForm` with title and subtitle. |
| `SymphonyLoginForm` | Identifier + password form calling `AuthController.login`. Shows field errors from `ValidationFailure` under the matching fields and other failures in a banner; forgot-password / register links when the callbacks are set and the adapter supports the feature. |
| `SymphonyRegisterForm` | Name, identifier, password (strength meter) and confirmation. |
| `SymphonyForgotPasswordForm` | Request step, plus an optional code + new password step (`enableConfirmStep: true`). |
| `SymphonyAuthLayout` | Centered, scrollable, width-constrained `Scaffold` for auth pages. |

Every text is a parameter (`identifierLabel`, `submitLabel`,
`requiredFieldMessage`...), so the widgets can be localized. A sign-in with a
username and an extra field:

```dart
class TenantLoginPage extends StatefulWidget {
  const TenantLoginPage({super.key});

  @override
  State<TenantLoginPage> createState() => _TenantLoginPageState();
}

class _TenantLoginPageState extends State<TenantLoginPage> {
  final _tenant = TextEditingController(text: 'acme');

  @override
  void dispose() {
    _tenant.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SymphonyLoginScreen(
      title: 'Sign in',
      subtitle: null,
      form: SymphonyLoginForm(
        identifierField: 'username',
        identifierLabel: 'Username',
        identifierIcon: Icons.person_outline,
        identifierKeyboardType: TextInputType.text,
        identifierAutofillHints: const [AutofillHints.username],
        identifierValidator: SymphonyValidators.required(),
        extraFields: [SymphonyTextField(controller: _tenant, label: 'Company')],
        extraCredentials: () => {'tenant': _tenant.text},
        failureMessageBuilder: (failure) => failure is NetworkFailure
            ? 'No connection. Try again later.'
            : failure.message,
      ),
    );
  }
}
```

Tests can find the fields with `SymphonyLoginForm.identifierInputKey`,
`passwordInputKey` and `submitButtonKey` (similar keys exist on the other
forms).

## Routing

### SymphonyRouter

`SymphonyRouter.create(ref, routes: ...)` returns a `GoRouter` that applies
these global rules before your own `redirect`:

- While the status is `unknown`, every location except the splash route and
  `publicPaths` goes to `splash?from=<location>`.
- When the status becomes known on the splash route, signed-in users go to
  the remembered location (or `home`); signed-out users go to the remembered
  location (or `login`), where route guards take over.
- Signed-in users on a guest-only route (the login route and
  `guestOnlyPaths`) go to the remembered location (or `home`).

Without `defaultAccess` (below), the global rules never require sign-in by
themselves: protect routes with `GuardedRoute`. Parameters: `paths`,
`publicPaths`, `defaultAccess`, `redirect` (your global redirect, run after
the built-in rules), `errorBuilder` (default `SymphonyRouteErrorScreen`),
`refreshListenable` (extra triggers), `restoreSessionOnStart` (default
`true`), plus `initialLocation`, `navigatorKey`, `observers`,
`debugLogDiagnostics`, `redirectLimit` (default 5) and `restorationScopeId`,
forwarded to `GoRouter`.

The router is created once and disposed with its provider. Do not
`ref.watch` other providers in the router provider: the router would be
rebuilt and the navigation stack reset. When the access changes, the pages
opened with `push` are checked again as well: a pushed page the user may no
longer see is closed and the user is sent where its guard says (go_router
13 and later only re-evaluate the redirects of the page below them, so the
package does this check itself).

### Secure by default

`defaultAccess` applies a requirement to every location except the splash
route, the guest-only routes (the login route included) and `publicPaths`,
so plain `GoRoute`s are protected without wrapping each of them:

```dart
final secureRouterProvider = Provider<GoRouter>((ref) {
  return SymphonyRouter.create(
    ref,
    defaultAccess: AccessRequirement.authenticated,
    publicPaths: const {'/terms'}, // open to everybody
    paths: const SymphonyRoutePaths(guestOnlyPaths: {'/register'}),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GuestRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GuestRoute(path: '/register', builder: (context, state) => const RegisterPage()),
      GoRoute(path: '/terms', builder: (context, state) => const TermsPage()),
      GoRoute(
        path: '/unauthorized',
        builder: (context, state) => const SymphonyUnauthorizedScreen(),
      ),
      // Protected by defaultAccess.
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      // Guards add their own requirements on top of it.
      GuardedRoute(
        path: '/admin',
        access: const AccessRequirement(roles: {'admin'}),
        builder: (context, state) => const AdminPage(),
      ),
    ],
  );
});
```

Signed-out users go to `login?from=<location>`; signed-in users who do not
satisfy the requirement go to `paths.unauthorized` (else home), which stays
reachable for them. A `GuestRoute` alone does not exempt its page: list the
guest pages other than login in `guestOnlyPaths`. Guards cannot relax the
default requirement, so pages open to everybody belong in `publicPaths`.
With a role or permission requirement, keep `paths.unauthorized` set;
otherwise denied users have no page left and go_router reports a redirect
loop.

### Route paths

`SymphonyRoutePaths` configures the app routes the rules redirect to (app
paths, not backend endpoints):

```dart
const paths = SymphonyRoutePaths(
  splash: '/splash',
  login: '/auth/login',
  home: '/dashboard',
  unauthorized: '/forbidden', // null: denied users go to home
  redirectParameter: 'from', // /auth/login?from=%2Forders
  guestOnlyPaths: {'/auth/register', '/auth/forgot-password'},
);
```

Comparisons are case-insensitive, ignore trailing slashes and cover
descendants (`/auth/register` also matches `/auth/register/step-2`); `/`
only matches the root.

### Guarded routes

```dart
bool hasActiveSubscription(AccessContext access) =>
    access.attributes['subscription'] == 'active';

final securedRoutes = <RouteBase>[
  GuardedRoute(
    // Default access: any signed-in user. Protects every nested route.
    path: '/settings',
    builder: (context, state) => const SettingsPage(),
    routes: [
      GuardedRoute(
        path: 'billing',
        access: const AccessRequirement(
          permissions: {'billing.read', 'billing.manage'},
          predicate: hasActiveSubscription,
        ),
        deniedRedirect: '/settings', // instead of paths.unauthorized
        builder: (context, state) => const BillingPage(),
      ),
    ],
  ),
  GuardedRoute(
    path: '/reports',
    access: const AccessRequirement(
      roles: {'manager', 'analyst'}, // any of them
      permissions: {'reports.read'},
    ),
    builder: (context, state) => const ReportsPage(),
  ),
  GuardedRoute(
    path: '/public-catalog',
    access: const AccessRequirement.public(), // reachable signed out
    builder: (context, state) => const CatalogPage(),
  ),
];
```

A guard that is not satisfied redirects:

- status unknown → `splash?from=<location>`;
- signed out → `login?from=<location>`;
- signed in without the required roles/permissions/predicate →
  `deniedRedirect`, else `paths.unauthorized`, else `home` (a target equal to
  the current page is skipped, so a denied page is never shown).

go_router evaluates the redirects of matched routes from parent to child, so
a parent `GuardedRoute` protects all its descendants and children can add
stricter requirements. `GuardedRoute` / `GuestRoute` accept your own
`redirect`, which runs only after the guard granted access. `GuestRoute`
(`authenticatedRedirect`) keeps signed-in users away from sign-in pages.

Shell routes: protect the `GoRoute`s inside a `ShellRoute` /
`StatefulShellRoute` (go_router 10 does not evaluate `ShellRoute` redirects):

```dart
final shellRoute = StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) => AppShell(shell: navigationShell),
  branches: [
    StatefulShellBranch(
      routes: [
        GuardedRoute(path: '/home', builder: (context, state) => const HomePage()),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GuardedRoute(
          path: '/admin',
          access: const AccessRequirement(roles: {'admin'}),
          builder: (context, state) => const AdminPage(),
        ),
      ],
    ),
  ],
);

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: shell.goBranch,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.shield_outlined), label: 'Admin'),
        ],
      ),
    );
  }
}
```

Hide the admin destination for other users with `AccessGate` or
`ref.watchCanAccess(...)`.

### AccessGate

```dart
class OrderActions extends ConsumerWidget {
  const OrderActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const canWrite = AccessRequirement(permissions: {'orders.write'});
    return Row(
      children: [
        const AccessGate(
          requirement: canWrite,
          fallback: Text('Read only'),
          child: Text('You can edit orders'),
        ),
        FilledButton(
          // watchCanAccess rebuilds on access changes; readCanAccess is for callbacks.
          onPressed: ref.watchCanAccess(canWrite) ? () {} : null,
          child: const Text('New order'),
        ),
      ],
    );
  }
}
```

### Other entry points

- `SymphonyRouter.custom(readAccess:, refreshListenable:, routes:, ...)`:
  same router without Riverpod (the caller disposes it). `readAccess`
  returns the current `AccessContext`; `refreshListenable` notifies when it
  changes.
- `SymphonyRouter.buildRedirect(readAccess:, paths:, publicPaths:, redirect:, defaultAccess:)`:
  the global redirect for a `GoRouter` you build yourself, with
  `SymphonyRouter.accessRefreshListenable(ref)` as `refreshListenable`.
- `SymphonyRedirectResolver`: the pure rules (no `BuildContext`):
  `resolveGlobal`, `resolveGuard`, `resolveGuest`, `resolveDefaultAccess`,
  `sanitizeTarget`; handy for unit tests.
- `SymphonyRouteErrorScreen` (unknown locations) and
  `SymphonyUnauthorizedScreen` (denied access), with every text configurable.

```dart
GoRouter routerWithoutRiverpod(ValueNotifier<AccessContext> access) {
  return SymphonyRouter.custom(
    readAccess: () => access.value,
    refreshListenable: access,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GuestRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GuardedRoute(path: '/', builder: (context, state) => const HomePage()),
    ],
  );
}
```

Redirect targets taken from `from` are sanitized: only in-app paths starting
with a single `/`, without scheme, host, backslashes or control characters
(also percent-encoded), and never the splash or login routes.

## Storage

### Key/value storage

`secureStorageProvider` is a `KeyValueStorage` backed by
`flutter_secure_storage` (`SecureKeyValueStorage`). Its keys are stored with
the prefix `symphonySecureStorageKeyPrefix` (`'symphony.'`): `tenant` is
written as `symphony.tenant`, and `readAll()` / `clear()` only see the
entries written through it, never those of other plugins or of your own
`FlutterSecureStorage` calls. Plugin errors become `StorageFailure`s.

```dart
Future<void> storageExamples(WidgetRef ref) async {
  final storage = ref.read(secureStorageProvider);
  await storage.write('tenant', 'acme');
  final tenant = await storage.read('tenant'); // 'acme'
  final known = await storage.containsKey('tenant'); // true

  // JSON helpers (JsonKeyValueStorageX): corrupted values read as null.
  await storage.writeJson('preferences', {'theme': 'dark', 'fontScale': 1.1});
  final preferences = await storage.readJson('preferences');

  // Scope keys so clear() only removes your own entries.
  final drafts = PrefixedKeyValueStorage(storage, 'drafts.');
  await drafts.write('order-42', '{"quantity": 3}'); // key "drafts.order-42"
  await drafts.clear(); // removes drafts.* only
}
```

`KeyValueStorage` has `read`, `write`, `delete`, `containsKey`, `readAll` and
`clear`. Implementations: `SecureKeyValueStorage({storage, keyPrefix,
failureMessage})`, `InMemoryKeyValueStorage([initialValues])` (tests),
`PrefixedKeyValueStorage(inner, prefix)`. Implement the interface to use
another backend (shared preferences, Hive...) and override
`secureStorageProvider` or pass `secureStorage:` to `SymphonyCore`.

> `secureStorageProvider.clear()` deletes every entry written through it,
> **including the session**. Give feature data its own
> `PrefixedKeyValueStorage` and clear that instead.

Platform options of the plugin (requires a direct dependency on
`flutter_secure_storage`):

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:symphony_core/symphony_core.dart';

Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    overrides: [
      flutterSecureStorageProvider.overrideWithValue(
        const FlutterSecureStorage(
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        ),
      ),
    ],
  );
  runApp(const SymphonyScope(child: MyApp()));
}
```

### Session storage

`sessionStorageProvider` (`SecureSessionStorage`) persists the auth session
as JSON in `secureStorageProvider`, under the keys `symphony.session.tokens`
and `symphony.session.user` (`SecureSessionStorage(storage, namespace: ...)`
changes the first segment). Corrupted payloads are deleted and treated as
"no session", so users are never locked out. Override it to store sessions
elsewhere.

### Local database

`localDatabaseProvider` exposes an engine-agnostic `LocalDatabase`: named
`LocalStore<T>`s with `get`, `getAll` (insertion order), `put`, `putAll`
(all or nothing), `delete`, `clear`, `count` and `watchAll` (current values,
then every change). Values are converted by a `StorageCodec<T>`.

```dart
class Todo {
  const Todo({required this.title, this.done = false});

  factory Todo.fromJson(Map<String, Object?> json) =>
      Todo(title: json['title']! as String, done: json['done'] == true);

  final String title;
  final bool done;

  Map<String, Object?> toJson() => {'title': title, 'done': done};
}

final todoCodec = StorageCodec<Todo>.json(
  fromJson: Todo.fromJson,
  toJson: (todo) => todo.toJson(),
);

final todoStoreProvider = Provider<LocalStore<Todo>>(
  (ref) => ref.watch(localDatabaseProvider).store('todos', todoCodec),
);

final todosProvider = StreamProvider<List<Todo>>(
  (ref) => ref.watch(todoStoreProvider).watchAll(),
);

Future<void> addTodo(WidgetRef ref, String id, String title) =>
    ref.read(todoStoreProvider).put(id, Todo(title: title));
```

The default `InMemoryLocalDatabase` loses its data on restart. For small
data sets, persist it in any `KeyValueStorage` with `KeyValueLocalDatabase`
(the whole collection is one JSON document per store):

```dart
Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    overrides: [
      localDatabaseProvider.overrideWith((ref) {
        final database = KeyValueLocalDatabase(ref.watch(secureStorageProvider));
        ref.onDispose(database.close);
        return database;
      }),
    ],
  );
  runApp(const SymphonyScope(child: MyApp()));
}
```

For larger data, implement `LocalDatabase` and `LocalStore` on top of your
engine (Hive, Drift, sqflite, Isar...); the API documentation of
`LocalDatabase` contains a complete Hive adapter. Pass an instance you open
and close yourself with `SymphonyCore.initialize(localDatabase: ...)`, or
let the container own it with `localDatabaseProvider.overrideWith` as above.
`store(name, codec)` returns the same instance for the same name and throws a
`StateError` when a name is reused with another value type.

## Dashboard

### Describing modules

A `DashboardItem` is a tile: `id` (unique in the whole tree), `label`,
`icon` or `iconBuilder`, `description`, a destination (`route` with
`queryParameters`, or `routeName` with `pathParameters`), `navigation`
(`DashboardNavigation.go`, the default, or `.push`), `children` (a group;
any depth), `access` (default: visible to everybody), `badge` (`''` shows a
dot), `color`, `enabled` (disabled items stay visible but ignore taps),
`onTap` (replaces navigation) and free `metadata`.

```dart
const modules = <DashboardItem>[
  DashboardItem(
    id: 'sales',
    label: 'Sales',
    icon: Icons.point_of_sale,
    children: [
      DashboardItem(
        id: 'sales.orders',
        label: 'Orders',
        icon: Icons.receipt_long,
        route: '/sales/orders',
        queryParameters: {'status': 'open'},
        badge: '3',
      ),
      DashboardItem(
        id: 'sales.reports',
        label: 'Reports',
        icon: Icons.bar_chart,
        routeName: 'report',
        pathParameters: {'kind': 'monthly'},
        access: AccessRequirement(permissions: {'reports.read'}),
      ),
    ],
  ),
  DashboardItem(
    id: 'settings',
    label: 'Settings',
    icon: Icons.settings_outlined,
    route: '/settings',
    navigation: DashboardNavigation.push, // keeps the dashboard below
  ),
  DashboardItem(
    id: 'beta',
    label: 'Forecasts',
    description: 'Coming soon',
    icon: Icons.science_outlined,
    enabled: false,
  ),
];
```

Provide the menu by overriding `dashboardItemsProvider` in the **root**
container (`SymphonyCore.initialize(overrides: [...])` or the root
`ProviderScope`). For dynamic menus (feature flags, badge counts), use
`overrideWith` and watch other providers:

```dart
final unreadOrdersProvider = Provider<int>((ref) => 0);

Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    overrides: [
      dashboardItemsProvider.overrideWith((ref) {
        final unread = ref.watch(unreadOrdersProvider);
        return [
          DashboardItem(
            id: 'orders',
            label: 'Orders',
            icon: Icons.receipt_long,
            route: '/orders',
            badge: unread == 0 ? null : '$unread',
          ),
        ];
      }),
    ],
  );
  runApp(const SymphonyScope(child: MyApp()));
}
```

### Filtering

`visibleDashboardItemsProvider` filters the menu with `accessContextProvider`
and updates on sign-in, sign-out and role changes. Items whose `access` is
not satisfied are hidden with their children; groups whose children are all
hidden disappear (unless they have their own destination or `onTap`, in
which case they remain as a plain tile). The same logic is
available as `DashboardMenu.filterVisibleItems(items, access)` and, inside
widgets, as `watchVisibleDashboardItems(ref)` (for a drawer or a search
showing the same entries). `DashboardMenu` also offers `findItemById`,
`pathTo`, `flatten` and `duplicateIds`.

Hiding a tile is not a security boundary: guard the routes too.

### Displaying the dashboard

```dart
class ModulesPage extends StatelessWidget {
  const ModulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modules')),
      body: SymphonyDashboard(
        title: const Text('Your workspace'),
        maxCrossAxisExtent: 200,
        // inline (default): the grid cross-fades into the group with a
        // breadcrumb; page: each group is pushed as a page.
        submenuPresentation: DashboardSubmenuPresentation.inline,
        emptyTitle: 'No modules available for your account',
        tileBuilder: (context, item, onTap) => Card(
          child: ListTile(
            leading: Icon(item.icon),
            title: Text(item.label),
            subtitle: item.description == null ? null : Text(item.description!),
            enabled: onTap != null,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
```

`SymphonyDashboard` reads `dashboardItemsProvider` and `accessContextProvider`
unless you pass `items` / `accessContext`. Tap order: disabled → nothing;
`onTap`; group → submenu; `onItemSelected` (replaces navigation of leaves);
otherwise `navigateToDashboardItem`, which uses GoRouter (`routeName` →
`goNamed`/`pushNamed`, `route` → `go`/`push`) and falls back to
`Navigator.pushNamed` without GoRouter. Lower-level widgets:
`SymphonyDashboardGrid`, `SymphonyDashboardTile` and
`SymphonyDashboardSubmenuPage` (usable as a deep-linked route).

`SymphonyDashboardController` drives inline submenus (`path`, `open`,
`goBack`, `goToRoot`, `canGoBack`). The package cannot intercept the system
back button on every supported Flutter version; on Flutter 3.24+ wire it
with `PopScope`:

```dart
// Requires Flutter 3.24+ (PopScope.onPopInvokedWithResult).
class DashboardWithBack extends StatefulWidget {
  const DashboardWithBack({super.key});

  @override
  State<DashboardWithBack> createState() => _DashboardWithBackState();
}

class _DashboardWithBackState extends State<DashboardWithBack> {
  final _controller = SymphonyDashboardController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) => PopScope(
        canPop: !_controller.canGoBack,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _controller.goBack();
        },
        child: child!,
      ),
      child: SymphonyDashboard(controller: _controller),
    );
  }
}
```

## UI components

### Theme

```dart
final lightTheme = SymphonyTheme.light(
  const SymphonyThemeConfig(
    seedColor: Color(0xFF00695C),
    cornerRadius: 10,
    successColor: Color(0xFF2E7D32),
  ),
);
final darkTheme = SymphonyTheme.dark(
  const SymphonyThemeConfig(seedColor: Color(0xFF00695C)),
);

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = SymphonyColors.of(context);
    return Container(
      padding: SymphonySpacing.horizontalSm,
      decoration: BoxDecoration(
        color: colors.success,
        borderRadius: SymphonyRadius.of(context).smallBorderRadius,
      ),
      child: Text(label, style: TextStyle(color: colors.onSuccess)),
    );
  }
}
```

`SymphonyTheme.light/dark([SymphonyThemeConfig])` build a Material 3
`ThemeData` from `seedColor` (or explicit `lightColorScheme` /
`darkColorScheme`), `fontFamily`, `cornerRadius`, `visualDensity`, status
colours and extra `extensions`. Theme extensions: `SymphonyColors`
(`success`, `warning`, `info` and their `on*` colours) and `SymphonyRadius`
(`small`/`medium`/`large`/`extraLarge`). `SymphonySpacing` holds spacing
constants (`xxs` 2 … `xxl` 32) and matching `EdgeInsets`. The widgets also
work with your own `ThemeData`; the extensions then fall back to defaults.

### Widgets

```dart
class OrderForm extends StatefulWidget {
  const OrderForm({super.key});

  @override
  State<OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends State<OrderForm> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _saving = false);
    SymphonySnackbar.success(context, 'Saved');
  }

  @override
  Widget build(BuildContext context) {
    return SymphonyLoadingOverlay(
      isLoading: _saving,
      message: 'Saving…',
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            SymphonyTextField(
              label: 'Quantity',
              keyboardType: TextInputType.number,
              prefixIcon: Icons.numbers,
              validator: SymphonyValidators.compose([
                SymphonyValidators.required(),
                SymphonyValidators.numeric(),
              ]),
            ),
            const SizedBox(height: SymphonySpacing.md),
            SymphonyPasswordField(
              controller: _password,
              showStrengthIndicator: true,
              validator: SymphonyValidators.minLength(8),
            ),
            const SizedBox(height: SymphonySpacing.lg),
            SymphonyButton(
              label: 'Save',
              icon: Icons.save_outlined,
              expanded: true,
              isLoading: _saving,
              onPressed: _save,
            ),
            SymphonyButton(
              label: 'Discard',
              variant: SymphonyButtonVariant.text,
              size: SymphonyButtonSize.small,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}
```

| Widget | Notes |
|---|---|
| `SymphonyButton` | Variants `primary`, `secondary` (tonal), `outlined`, `text`, `danger`; sizes `small`/`medium`/`large`; `icon`, `trailingIcon`, `expanded`, `isLoading` (spinner, same size, taps ignored), `tooltip`, `style`. |
| `SymphonyIconButton` | `standard`, `filled`, `tonal`, `outlined`; required `tooltip`; `isLoading`. |
| `SymphonyTextField` | Wraps `TextFormField` with an outlined style; `label`, `hint`, `prefixIcon` (`IconData`), `suffix`, `validator`, formatters, autofill... |
| `SymphonyPasswordField` | Visibility toggle; optional strength meter (`showStrengthIndicator`, `strengthEvaluator`, `strengthLabels`). |
| `SymphonyPasswordStrengthMeter`, `PasswordStrengthEvaluator` | Standalone meter and the heuristic behind it (subclass to change the rules). |
| `SymphonyLoadingIndicator` | Centered spinner with optional `message`. |
| `SymphonyLoadingOverlay` | Blocks input over a child while `isLoading`, keeping its state. |
| `SymphonyErrorView` | Icon and title chosen from the `Failure` type, message, retry button; `compact` banner variant. |
| `SymphonyEmptyState` | Icon, title, message and optional action. |

### Feedback: errors, snack bars and dialogs

```dart
class OrdersView extends ConsumerWidget {
  const OrdersView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(ordersProvider).when(
          loading: () => const SymphonyLoadingIndicator(message: 'Loading orders…'),
          error: (error, stackTrace) => SymphonyErrorView(
            failure: error is Failure ? error : null,
            onRetry: () => ref.invalidate(ordersProvider),
          ),
          data: (orders) => orders.isEmpty
              ? SymphonyEmptyState(
                  title: 'No orders yet',
                  message: 'Orders you create appear here.',
                  actionLabel: 'Create order',
                  onAction: () => context.push('/orders/new'),
                )
              : ListView(
                  children: [
                    for (final order in orders) ListTile(title: Text(order.id)),
                  ],
                ),
        );
  }
}

class DeleteOrderButton extends ConsumerStatefulWidget {
  const DeleteOrderButton({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<DeleteOrderButton> createState() => _DeleteOrderButtonState();
}

class _DeleteOrderButtonState extends ConsumerState<DeleteOrderButton> {
  Future<void> _delete() async {
    final confirmed = await SymphonyDialogs.confirm(
      context,
      title: 'Delete order ${widget.order.id}?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!mounted) return;
    if (!confirmed) return;
    try {
      await SymphonyDialogs.runWithLoading(
        context,
        () => ref.read(orderRepositoryProvider).delete(widget.order.id),
        message: 'Deleting…',
      );
      if (!mounted) return;
      SymphonySnackbar.success(context, 'Order deleted');
    } on Failure catch (failure) {
      if (!mounted) return;
      SymphonySnackbar.showFailure(
        context,
        failure,
        actionLabel: 'Retry',
        onAction: _delete,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SymphonyIconButton(
      icon: Icons.delete_outline,
      tooltip: 'Delete',
      onPressed: _delete,
    );
  }
}
```

- `SymphonySnackbar.show(context, message, type: ...)`, `success`, `error`,
  `warning`, `info` and `showFailure(context, failure)`: floating snack bars
  coloured from `SymphonyColors`; a close icon is shown when an action is set.
- `SymphonyDialogs.confirm` (`Future<bool>`), `alert`, `prompt`
  (`Future<String?>`, validated input), `showLoading` (returns a handle with
  an idempotent `close()`) and `runWithLoading` (always closes, rethrows
  errors).

### Responsive helpers

```dart
class CatalogLayout extends StatelessWidget {
  const CatalogLayout({super.key});

  @override
  Widget build(BuildContext context) {
    const padding = ResponsiveValue<double>(compact: 12, medium: 24, expanded: 32);
    return Padding(
      padding: EdgeInsets.all(padding.resolve(context)),
      child: ResponsiveLayout(
        compact: const CatalogList(),
        expanded: Row(
          children: [
            const SizedBox(width: 280, child: CatalogFilters()),
            Expanded(
              child: ResponsiveBuilder(
                builder: (context, sizeClass, constraints) => GridView.count(
                  crossAxisCount: responsiveColumns(constraints.maxWidth, minTileWidth: 240),
                  children: const [CatalogTile(), CatalogTile(), CatalogTile()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- Size classes (`ScreenSizeClass.compact` < 600 ≤ `medium` < 840 ≤
  `expanded` < 1200 ≤ `large`) from `SymphonyBreakpoints`; change them
  app-wide with `SymphonyBreakpointsScope`.
- `ResponsiveLayout` / `ResponsiveBuilder` classify the width available to
  them (`LayoutBuilder`); `context.screenSizeClass`, `context.isCompact`,
  `context.isMediumOrLarger`, `context.isExpandedOrLarger` and
  `ResponsiveValue.resolve` use the screen width.
- `SymphonyContentConstraint(maxWidth: 600)` centers readable content;
  `responsiveColumns(width, minTileWidth: 280)` computes grid columns.

## Overriding dependencies

Every service is a Riverpod provider. Override providers in the **root**
container: `SymphonyCore.initialize(overrides: [...])`,
`SymphonyCore.create(overrides: [...])` or the root
`ProviderScope(overrides: symphonyOverrides(..., overrides: [...]))`. Prefer
the named parameters (`config`, `authAdapter`/`authAdapterBuilder`,
`secureStorage`, `localDatabase`, `errorReporter`) for the providers they
cover: they also wire the token delegate and avoid duplicate overrides. An
adapter supplied only through `overrides` does not wire the token delegate:
override `authTokenDelegateProvider` too (with
`(ref) => ref.watch(sessionTokenDelegateProvider)`).

| Provider | Type | Default | Override when |
|---|---|---|---|
| `symphonyConfigProvider` | `Provider<SymphonyConfig>` | none (throws until configured) | Always set, through `config:`. |
| `symphonyLoggerProvider` | `Provider<SymphonyLogger>` | Logger from `enableLogging` / `logLevel`, tag `Symphony` | Custom log sinks. |
| `logRedactorProvider` | `Provider<LogRedactor>` | `config.redactor` | A custom mask. Prefer `sensitiveKeys` for keys. |
| `errorReporterProvider` | `Provider<ErrorReporter>` | `LoggerErrorReporter(logger)` | Crash reporting (prefer `errorReporter:`). |
| `apiClientProvider` | `Provider<ApiClient>` | `ApiClient` built from the providers below | Rarely: reuse an existing `Dio` (`ApiClient(dio: ...)`). |
| `apiErrorMapperProvider` | `Provider<ApiErrorMapper>` | `const DefaultApiErrorMapper()` | Backend-specific error payloads, localized messages. |
| `apiInterceptorsProvider` | `Provider<List<Interceptor>>` | `[]` | Custom Dio interceptors. |
| `apiHeaderProvidersProvider` | `Provider<List<HeaderProvider>>` | `[]` | Dynamic headers (locale, app version, tenant). |
| `httpClientAdapterProvider` | `Provider<HttpClientAdapter?>` | `null` (platform default) | Tests, mock servers, certificate pinning. Never closed by the client. |
| `authTokenDelegateProvider` | `Provider<AuthTokenDelegate?>` | `null`; `sessionTokenDelegateProvider` when an adapter is configured | Tokens managed outside the auth module. |
| `apiInspectorProvider` | `Provider<ApiInspector>` | `ApiInspector` configured from `SymphonyConfig` | Rarely (custom limits). |
| `flutterSecureStorageProvider` | `Provider<FlutterSecureStorage>` | `const FlutterSecureStorage()` | Platform options (Android, iOS, web...). |
| `secureStorageProvider` | `Provider<KeyValueStorage>` | `SecureKeyValueStorage` with the `symphony.` key prefix | Another backend; `InMemoryKeyValueStorage()` in tests (prefer `secureStorage:`). |
| `sessionStorageProvider` | `Provider<SessionStorage>` | `SecureSessionStorage(secureStorage)` | Store the session elsewhere or under another namespace. |
| `localDatabaseProvider` | `Provider<LocalDatabase>` | `InMemoryLocalDatabase()` | Persistence (`KeyValueLocalDatabase` or your engine's adapter; `localDatabase:` for an instance you own). |
| `authAdapterProvider` | `Provider<AuthAdapter>` | none (throws until configured) | Set through `authAdapter:` / `authAdapterBuilder:`. |
| `authRepositoryProvider` | `Provider<AuthRepository>` | `AuthRepositoryImpl` (adapter, session storage, logger) | Tune `expiryLeeway`, or replace the repository. |
| `authControllerProvider` | `NotifierProvider<AuthController, AuthState>` | `AuthController` | Tests (subclass `AuthController`). |
| `accessContextProvider` | `Provider<AccessContext>` | Derived from `authControllerProvider` | Tests, or access rules not based on the auth module. |
| `currentUserProvider` | `Provider<AuthUser?>` | Derived from `authControllerProvider` | Tests. |
| `isAuthenticatedProvider` | `Provider<bool>` | Derived from `authControllerProvider` | Tests. |
| `sessionTokenDelegateProvider` | `Provider<AuthTokenDelegate>` | `SessionTokenDelegate` backed by the repository | Rarely (custom expiry handling). |
| `dashboardItemsProvider` | `Provider<List<DashboardItem>>` | `[]` | Always, to provide your menu. |
| `visibleDashboardItemsProvider` | `Provider<List<DashboardItem>>` | `dashboardItemsProvider` filtered by access | Rarely (custom filtering). |

The routing module has no provider: your app owns the router provider and
calls `SymphonyRouter.create(ref, ...)` in it.

Tuning the repository:

```dart
Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    authAdapter: InMemoryAuthAdapter(),
    overrides: [
      authRepositoryProvider.overrideWith(
        (ref) => AuthRepositoryImpl(
          adapter: ref.watch(authAdapterProvider),
          storage: ref.watch(sessionStorageProvider),
          logger: ref.watch(symphonyLoggerProvider).withTag('Auth'),
          expiryLeeway: const Duration(minutes: 2),
        ),
      ),
    ],
  );
  runApp(const SymphonyScope(child: MyApp()));
}
```

## Testing

Use `SymphonyCore.create` for an isolated instance per test, in-memory
implementations for storage and authentication, and a fake
`HttpClientAdapter` for HTTP.

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/symphony_core.dart';

/// Answers every request with a JSON body and records the requests.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.body, {this.statusCode = 200});

  final Object? body;
  final int statusCode;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('decodes the response and maps errors', () async {
    final adapter = FakeHttpAdapter({'id': 7, 'status': 'open'});
    final core = SymphonyCore.create(
      config: const SymphonyConfig(baseUrl: 'https://api.test'),
      secureStorage: InMemoryKeyValueStorage(),
      overrides: [httpClientAdapterProvider.overrideWithValue(adapter)],
    );
    addTearDown(core.dispose);

    final response = await core.apiClient.get<Map<String, dynamic>>('/orders/7');

    expect(response.data['status'], 'open');
    expect(adapter.requests.single.uri.toString(), 'https://api.test/orders/7');
  });

  test('turns HTTP errors into failures', () async {
    final core = SymphonyCore.create(
      config: const SymphonyConfig(baseUrl: 'https://api.test'),
      secureStorage: InMemoryKeyValueStorage(),
      overrides: [
        httpClientAdapterProvider.overrideWithValue(
          FakeHttpAdapter({'message': 'Order not found'}, statusCode: 404),
        ),
      ],
    );
    addTearDown(core.dispose);

    await expectLater(
      core.apiClient.get<void>('/orders/404'),
      throwsA(
        isA<NotFoundFailure>().having((f) => f.message, 'message', 'Order not found'),
      ),
    );
  });
}
```

Widget tests with authentication:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/symphony_core.dart';

void main() {
  testWidgets('signs in with the in-memory adapter', (tester) async {
    final core = SymphonyCore.create(
      config: const SymphonyConfig(baseUrl: 'https://api.test'),
      authAdapter: InMemoryAuthAdapter(
        accounts: const [
          InMemoryAccount(
            identifier: 'ada@example.com',
            password: 'secret123',
            user: AuthUser(id: '1', displayName: 'Ada', roles: {'admin'}),
          ),
        ],
      ),
      secureStorage: InMemoryKeyValueStorage(),
    );
    addTearDown(core.dispose);

    await tester.pumpWidget(
      core.wrap(const MaterialApp(home: Scaffold(body: SymphonyLoginForm()))),
    );
    await tester.enterText(
      find.byKey(SymphonyLoginForm.identifierInputKey),
      'ada@example.com',
    );
    await tester.enterText(find.byKey(SymphonyLoginForm.passwordInputKey), 'secret123');
    await tester.tap(find.byKey(SymphonyLoginForm.submitButtonKey));
    await tester.pumpAndSettle();

    expect(core.read(isAuthenticatedProvider), isTrue);
    expect(core.read(accessContextProvider).hasRole('admin'), isTrue);
  });

  testWidgets('works with a plain ProviderScope too', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: symphonyOverrides(
          config: const SymphonyConfig(baseUrl: 'https://api.test'),
          overrides: [
            accessContextProvider.overrideWithValue(
              const AccessContext(
                status: AuthStatus.authenticated,
                permissions: {'orders.write'},
              ),
            ),
          ],
        ),
        child: const MaterialApp(
          home: AccessGate(
            requirement: AccessRequirement(permissions: {'orders.write'}),
            child: Text('editor'),
          ),
        ),
      ),
    );

    expect(find.text('editor'), findsOneWidget);
  });
}
```

Pure logic needs no widgets:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/symphony_core.dart';

void main() {
  test('signed-out users are sent to the login page', () {
    const resolver = SymphonyRedirectResolver();

    final target = resolver.resolveGuard(
      AccessContext.unauthenticated,
      Uri.parse('/orders?page=2'),
    );

    expect(target, '/login?from=%2Forders%3Fpage%3D2');
  });

  test('menus hide what the user cannot open', () {
    const items = [
      DashboardItem(id: 'public', label: 'News'),
      DashboardItem(
        id: 'admin',
        label: 'Admin',
        access: AccessRequirement(roles: {'admin'}),
      ),
    ];

    final visible = DashboardMenu.filterVisibleItems(
      items,
      const AccessContext(status: AuthStatus.authenticated),
    );

    expect(visible.map((item) => item.id), ['public']);
  });
}
```

Tips:

- Code that calls `SymphonyCore.initialize` registers a global instance: add
  `tearDown(SymphonyCore.reset)`.
- `InMemoryAuthAdapter` supports `latency`, `failureInjector` (fail a given
  `InMemoryAuthOperation`) and `revokeAllSessions()` to test expiry. Mock
  adapters with mocktail (`class MockAuthAdapter extends Mock implements AuthAdapter {}`).
- Do not write the `Override` type in tests (it is not exported by
  `flutter_riverpod.dart` on Riverpod 3); let list types be inferred.
- Riverpod 3 wraps errors thrown by providers in `ProviderException`, while
  Riverpod 2 rethrows them unchanged. Match on the message, for example
  `throwsA(predicate((e) => '$e'.contains('symphonyConfigProvider is not configured')))`,
  rather than on `isA<StateError>()`.
- Riverpod 2.4 applies dependent provider updates in a microtask: after an
  authentication change in a widget test, `pump()` or `pumpAndSettle()`
  before asserting on routes and menus.
- Avoid `matchesSemantics` / `containsSemantics` if your tests must run on
  Flutter 3.10 and 3.44 alike (deprecated in recent Flutter, replacements
  missing in 3.10).

## Security notes

- **Tokens** are stored with `flutter_secure_storage` (Keychain on
  iOS/macOS, Keystore-backed encryption on Android, libsecret on Linux). On the
  web the plugin uses WebCrypto with `localStorage`, which is weaker and
  requires HTTPS; see the [platform notes](COMPATIBILITY.md#platform-notes).
  `AuthTokens.toString()` and `AuthCredentials.toString()` never print
  secret values, and the auth module never logs tokens.
- **Redaction is key-based.** Values are masked when their header, JSON field
  or URL parameter name (query and fragment) matches `sensitiveKeys`; the
  header named by `authHeaderName` is always masked, whatever its name. Add
  your own sensitive names (`otp`, `pin`, `iban`, `ssn`...) to the set.
  Free-text bodies are masked by pattern (URLs with credentials, bearer
  tokens, `key=value` pairs); formats such as XML are not masked.
- **Disable debugging tools in production**: keep `enableInspector` and
  `enableLogging` off for production builds (for example
  `enableInspector: kDebugMode`). When disabled, the inspector and logging
  interceptors are not installed. cURL exports contain masked values only.
- **Route guards and hidden tiles are UX, not authorization.** The backend
  must enforce roles and permissions on every endpoint.
- **Open redirects**: the `from` parameter is only followed for in-app paths
  (see [Routing](#other-entry-points)).
- **JWT `exp`** is read without verifying the signature and used only as an
  expiry hint. Never derive permissions from unverified token claims on the
  client.
- **`InMemoryAuthAdapter`** stores plain-text passwords and issues unsigned
  tokens: demos and tests only.
- **Certificate pinning** can be implemented with a custom
  `HttpClientAdapter` (for example Dio's `IOHttpClientAdapter` with a
  restricted `SecurityContext`) provided through `httpClientAdapterProvider`
  (not on the web).
- **Error reports** may contain request URLs and messages. Make sure your
  `ErrorReporter` scrubs personal data before sending it.
- `secureStorageProvider` only touches keys under the `symphony.` prefix, but
  its `clear()` also removes the session. Use `PrefixedKeyValueStorage` for
  feature data you need to clear on its own.

## Architecture

Feature-first clean architecture: each feature has `domain/` (pure Dart
entities, contracts and rules), `data/` (implementations: Dio, secure storage,
mappers) and `presentation/` (Riverpod providers, controllers and widgets).
Widgets hold no business logic, only Dio-based code in `networking` (and the
inspector interceptor) touches Dio, and no backend endpoint is hard-coded.

```text
lib/
├── symphony_core.dart        # the public library: exports every module
└── src/
    ├── core/                 # SymphonyCore, SymphonyScope, config, DI providers,
    │                         # errors, Result, access rules, logging, utils
    ├── features/
    │   ├── networking/       # ApiClient, interceptors, error mapping
    │   ├── inspector/        # API inspector (recording, screens, overlay)
    │   ├── auth/             # adapters, repository, controller, widgets
    │   ├── routing/          # SymphonyRouter, guards, AccessGate
    │   ├── storage/          # key/value + session storage, LocalDatabase
    │   └── dashboard/        # DashboardItem, menu logic, dashboard widgets
    └── ui/                   # theme, widgets, dialogs, responsive helpers
```

Import only `package:symphony_core/symphony_core.dart`; everything under
`lib/src/` is private implementation. Layers, dependency graphs, the request
lifecycle, the auth state machine and the redirect flow are described in
[doc/architecture.md](doc/architecture.md).

## Compatibility

| | Supported range |
|---|---|
| Flutter / Dart | `>=3.10.0` / `>=3.0.0 <4.0.0` |
| dio | `>=5.4.0 <6.0.0` |
| flutter_riverpod | `>=2.4.0 <4.0.0` (Riverpod 2 and 3) |
| go_router | `>=10.0.0 <19.0.0` |
| flutter_secure_storage | `>=9.0.0 <12.0.0` |

Verified on 2026-10-31 (analyzer clean, 1112 unit and widget tests passing)
on Flutter 3.10.6 and 3.44.8, each with the lowest and the highest dependency
versions they resolve. Versions in between, Riverpod 3.0–3.3, go_router 14–17
and builds on devices were not individually verified. Details, platform notes
and version-specific behaviour: [COMPATIBILITY.md](COMPATIBILITY.md).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `symphonyConfigProvider is not configured` | `SymphonyCore.initialize` did not run before `runApp`, or `symphonyOverrides` is not in the root `ProviderScope`. On Riverpod 3 the message is wrapped in a `ProviderException`. |
| `authAdapterProvider is not configured` | Pass `authAdapter:` or `authAdapterBuilder:`, or do not use auth widgets/providers. |
| `'Override' isn't a type` | Riverpod 3 exports `Override` from `package:flutter_riverpod/misc.dart` only. Let the type be inferred. |
| No inspector button | `enableInspector` is `false`, or `SymphonyInspectorOverlay` is not placed in `MaterialApp.builder`. |
| Requests are not authenticated | The adapter was supplied through `overrides`: use `authAdapter:` / `authAdapterBuilder:` (or override `authTokenDelegateProvider`). |
| Redirect loop error page | A location used by `SymphonyRoutePaths` (splash, login, home, unauthorized) has no route, or every fallback of a denied route is the denied page itself. |
| Name clash on `Response` | The package re-exports Dio's `Response`: `import 'package:symphony_core/symphony_core.dart' hide Response;` when you also use `package:http`. |
| Android: `InvalidKeyException` after reinstall | Auto backup restored encrypted preferences without their keys. Disable backup or exclude the plugin's preferences (see [platform notes](COMPATIBILITY.md#platform-notes)). |

## Versioning policy

symphony_core follows [semantic versioning](https://semver.org) as applied by
pub. Before 1.0.0 the minor number is the breaking digit: `0.2.0` may break
`0.1.x`, while `0.1.1` only adds features or fixes. From 1.0.0, breaking
changes require a new major version.

The public API is everything exported by
`package:symphony_core/symphony_core.dart`. Members annotated
`@visibleForTesting` and anything imported from `lib/src/` are not covered.

Breaking changes include:

- removing or renaming an exported declaration, member, parameter or enum
  value; changing a type or a signature; adding a required parameter;
- adding an abstract member to a type apps implement or extend
  (`AuthAdapter`, `AuthTokenDelegate`, `ApiErrorMapper`, `KeyValueStorage`,
  `SessionStorage`, `LocalDatabase`, `LocalStore`, `StorageCodec`,
  `ErrorReporter`, `LogSink`, `AuthRepository`). New members of these types
  always come with a default implementation, so extend them rather than
  implement them;
- changing a default value in a way that changes behaviour (for example
  `SymphonyConfig.maxRetries`), the redirect rules, the interceptor order, or
  which `Failure` type an error maps to;
- changing persisted formats (session storage keys and JSON, the layout of
  `KeyValueLocalDatabase`) without a migration;
- dropping support for a version of Flutter, Dart or a dependency (see
  [COMPATIBILITY.md](COMPATIBILITY.md#policy-for-version-ranges)).

Not breaking: new optional parameters, new types and providers, bug fixes,
visual refinements of widgets, changes to default English texts, and wider
dependency ranges. Deprecated APIs keep working until the next breaking
release and are listed in the CHANGELOG with their replacement.

## License

MIT. See [LICENSE](LICENSE).
