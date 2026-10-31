# Changelog

All notable changes to this package are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
as applied by pub: before 1.0.0, a minor version bump (`0.x.0`) may contain
breaking changes. See "Versioning policy" in [README.md](README.md) and
[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md).

## [Unreleased]

## [0.1.0] - 2026-10-31

First release.

### Added

#### Core

- `SymphonyCore` entry point: `initialize` (global instance, optional session
  restoration, global error handlers), `create` (independent instances for
  tests), `instance`, `read`, `apiClient`, `logger`, `auth`, `wrap`,
  `dispose`, and an advanced `parent` container mode. Named parameters
  `authAdapter` / `authAdapterBuilder`, `secureStorage`, `localDatabase`,
  `errorReporter` and `overrides`.
- `SymphonyScope` widget exposing a `SymphonyCore` container to the widget
  tree.
- `symphonyOverrides(...)` to configure the package inside an existing root
  `ProviderScope`.
- `SymphonyConfig` (base URL, environment, inspector and logging switches,
  timeouts, default headers, token header and prefix, refresh and retry
  policies, inspector limits, sensitive keys, global error handling, free-form
  `extras`) and `AppEnvironment`.
- Providers: `symphonyConfigProvider`, `symphonyLoggerProvider`,
  `logRedactorProvider`, `errorReporterProvider`.
- `Failure` hierarchy (`NetworkFailure`, `TimeoutFailure`, `ServerFailure`,
  `UnauthorizedFailure`, `ForbiddenFailure`, `NotFoundFailure`,
  `ValidationFailure`, `AuthFailure`, `CancelledFailure`, `ParsingFailure`,
  `StorageFailure`, `UnsupportedFailure`, `UnexpectedFailure`), sealed
  `Result<T>` with `guardResult`.
- `ErrorReporter` (`LoggerErrorReporter`, `NoopErrorReporter`,
  `CompositeErrorReporter`) and `GlobalErrorHandler` (`install`,
  `runGuarded`) chaining to previously installed handlers.
- `SymphonyLogger` with pluggable `LogSink`s, `LogLevel`, and `LogRedactor`
  (headers, URL query and fragment parameters, nested JSON and JSON
  strings).
- `AccessContext`, `AccessRequirement` (roles, permissions, match modes,
  predicate) and `AuthStatus`.
- Utilities: `SymphonyValidators`, `JsonReader`, `Debouncer`, `Throttler`,
  string and `BuildContext` extensions.

#### Networking

- `ApiClient` wrapping a single Dio instance: `get`, `post`, `put`, `patch`,
  `delete`, `request`, `upload` (multipart from `UploadFile`s and fields),
  `download`, `downloadBytes`, typed decoding with `ResponseDecoder`,
  `ApiResponse<T>`.
- Per-request `ApiRequestOptions` (headers, authentication, refresh, retries,
  timeouts including connect timeout, content type, inspection, logging,
  extras) and `ApiRequestOptions.unauthenticated`.
- Runtime configuration: `updateBaseUrl`, `resetBaseUrl`,
  `baseUrlListenable`, `setHeader`, `updateTimeouts`,
  `addInterceptor`/`removeInterceptor`,
  `addHeaderProvider`/`removeHeaderProvider`.
- Interceptors: `HeadersInterceptor` (dynamic header providers),
  `AuthTokenInterceptor` (token injection, single-flight refresh shared by
  concurrent `401`s, one replay, session expiry callback, loop and deadlock
  protection), `RetryInterceptor` (idempotent methods, backoff,
  `Retry-After`), `SecureLoggingInterceptor` (redacted logs; the
  `authHeaderName` header is always masked).
- `DefaultApiErrorMapper`: Dio errors and HTTP statuses to `Failure`s, with
  message, code and field-error extraction and localizable fallback
  messages; `ApiErrorMapper` contract.
- `AuthTokenDelegate` contract; providers `apiClientProvider`,
  `authTokenDelegateProvider`, `apiErrorMapperProvider`,
  `apiInterceptorsProvider`, `apiHeaderProvidersProvider`,
  `httpClientAdapterProvider`.
- Re-export of the Dio types used in public signatures.

#### Inspector

- `ApiInspector` recording calls with redacted headers, URLs and bodies,
  body truncation, entry limit and pause/resume; `ApiInspectorInterceptor`
  (the `authHeaderName` header is always masked).
- `SymphonyInspectorOverlay` (draggable floating button with call and error
  counts, in-app panel), `ApiInspectorScreen`, `showApiInspector`,
  `ApiCallDetailScreen` (overview, request and response tabs, copy actions),
  `ApiCallTile` and badges.
- `ApiCallFilter` (search terms and status filters), `CurlCommandBuilder`,
  `ApiInspectorStrings` for localization, `apiInspectorProvider`.

#### Authentication

- `AuthAdapter` contract; `RestAuthAdapter` with `RestAuthEndpoints` and
  `AuthResponseMapping` (dotted paths, sensible defaults, JWT expiry
  fallback) plus request-body and parser hooks and a session validator.
- `InMemoryAuthAdapter` (accounts, expiring tokens, rotating refresh tokens,
  registration, password recovery codes, latency, failure injection) for
  demos and tests.
- `AuthRepository` / `AuthRepositoryImpl` (persisted sessions, restoration
  with proactive refresh of expired tokens, single-flight refresh, offline
  tolerance, storage serialization), `SessionTokenDelegate`.
- `AuthController` (`Notifier<AuthState>`): `restoreSession`, `login`,
  `logout`, `register`, `requestPasswordReset`, `confirmPasswordReset`,
  `updateSession`, `handleSessionExpired`; sealed `AuthState`.
- Entities `AuthTokens`, `AuthUser`, `AuthSession`, `AuthCredentials`.
- Providers `authAdapterProvider`, `authRepositoryProvider`,
  `authControllerProvider`, `accessContextProvider`, `currentUserProvider`,
  `isAuthenticatedProvider`, `sessionTokenDelegateProvider`.
- Widgets: `SymphonySplashScreen`, `SymphonyLoginScreen`,
  `SymphonyLoginForm`, `SymphonyRegisterForm`,
  `SymphonyForgotPasswordForm`, `SymphonyAuthLayout`; every text
  configurable.

#### Routing

- `SymphonyRouter.create` (Riverpod), `SymphonyRouter.custom`
  (Riverpod-free), `SymphonyRouter.buildRedirect` and
  `accessRefreshListenable`: splash while the session is restored, sign-in
  redirects with return to the requested page, guest-only routes, session
  restoration on start, optional secure-by-default `defaultAccess`, and a
  re-check of pages opened with `push` when the access changes.
- `GuardedRoute` (authentication, roles, permissions, predicate, denied
  redirect, nested guards) and `GuestRoute`.
- `SymphonyRoutePaths`, pure `SymphonyRedirectResolver` with open-redirect
  protection.
- `AccessGate`, `WidgetRef.watchCanAccess` / `readCanAccess`,
  `SymphonyRouteErrorScreen`, `SymphonyUnauthorizedScreen`.

#### Storage

- `KeyValueStorage` with `SecureKeyValueStorage` (flutter_secure_storage,
  optional key prefix), `InMemoryKeyValueStorage` and
  `PrefixedKeyValueStorage`; JSON helpers (`JsonKeyValueStorageX`).
- `SessionStorage` / `SecureSessionStorage` (corrupted sessions are discarded
  instead of locking users out).
- `LocalDatabase`, `LocalStore` and `StorageCodec` abstractions with
  `InMemoryLocalDatabase` and `KeyValueLocalDatabase`; `StorageFailureCodes`.
- Providers `flutterSecureStorageProvider`, `secureStorageProvider` (keys
  prefixed with `symphonySecureStorageKeyPrefix`, `'symphony.'`),
  `sessionStorageProvider`, `localDatabaseProvider`.

#### Dashboard

- `DashboardItem` (nested groups, routes or named routes with parameters, go
  or push navigation, access rules, badges, colours, disabled items, custom
  taps, metadata) and pure `DashboardMenu` logic (filtering, lookup,
  breadcrumbs, tap resolution).
- `SymphonyDashboard` with inline or page submenus,
  `SymphonyDashboardController`, `SymphonyDashboardGrid`,
  `SymphonyDashboardTile`, `SymphonyDashboardSubmenuPage`,
  `navigateToDashboardItem`.
- Providers `dashboardItemsProvider`, `visibleDashboardItemsProvider` and
  `watchVisibleDashboardItems`.

#### UI

- `SymphonyTheme` (Material 3 light and dark) with `SymphonyThemeConfig`,
  `SymphonyColors`, `SymphonyRadius`, `SymphonySpacing`.
- `SymphonyButton`, `SymphonyIconButton`, `SymphonyTextField`,
  `SymphonyPasswordField`, `SymphonyPasswordStrengthMeter`,
  `PasswordStrengthEvaluator`.
- `SymphonyLoadingIndicator`, `SymphonyLoadingOverlay`, `SymphonyErrorView`,
  `SymphonyEmptyState`, `SymphonySnackbar`, `SymphonyDialogs`
  (`confirm`, `alert`, `prompt`, `showLoading`, `runWithLoading`).
- Responsive helpers: `SymphonyBreakpoints`, `SymphonyBreakpointsScope`,
  `ResponsiveBuilder`, `ResponsiveLayout`, `ResponsiveValue`,
  `SymphonyContentConstraint`, `responsiveColumns`, `BuildContext` size-class
  getters.

### Compatibility

- Supported ranges: Dart `>=3.0.0 <4.0.0`, Flutter `>=3.10.0`, dio
  `>=5.4.0 <6.0.0`, flutter_riverpod `>=2.4.0 <4.0.0`, go_router
  `>=10.0.0 <19.0.0`, flutter_secure_storage `>=9.0.0 <12.0.0`.
- Verified (analyzer clean, 1112 unit and widget tests passing) on Flutter
  3.10.6 / Dart 3.0.6 and Flutter 3.44.8 / Dart 3.12.2, each with the lowest
  and the highest dependency versions they resolve. Not individually
  verified: Flutter versions in between, Riverpod 3.0–3.3, go_router 14–17,
  native platform builds. See [COMPATIBILITY.md](COMPATIBILITY.md).
- CI runs the matrix (Flutter 3.10.6 and stable × `pub downgrade` /
  `pub upgrade`), a formatting check and `dart pub publish --dry-run`.

### Known limitations

- The system back button is not intercepted (no `PopScope` on Flutter
  3.10): inline dashboard submenus and `SymphonyDialogs.showLoading` do not
  react to it. Apps on Flutter 3.24+ can wire `SymphonyDashboardController`
  with `PopScope`.
- go_router 10 does not evaluate `ShellRoute` redirects: guard the routes
  inside shells. Some go_router 17.0.x releases evaluate the top-level
  redirect only once per navigation.
- On Riverpod 2, `symphonyOverrides` cannot drop a built-in override that the
  app overrides again; the app's override wins. Prefer the named parameters.
- `ApiClient.download()` and `UploadFile.fromPath` are not supported on the
  web (use `downloadBytes()` and `UploadFile.fromBytes`). On dio 5.4,
  multipart files without a content type are sent as
  `application/octet-stream`.
- `Retry-After` is honoured in seconds only (not the HTTP-date form); stream
  request bodies are never retried or replayed after a token refresh.
- Redaction is key-based plus patterns for free text; formats such as XML are
  not masked. Large bodies are redacted on the UI isolate before truncation.
- At runtime, token refresh is reactive (after a `401`); expired tokens are
  refreshed proactively only during session restoration.
  `AuthResponseMapping` paths cannot address keys containing a dot.
- `localDatabaseProvider` defaults to an in-memory database (data lost on
  restart). `KeyValueLocalDatabase` rewrites a whole store on every change
  and only suits small data sets.
- `secureStorageProvider.clear()` removes every entry written through that
  storage, the persisted session included.
- `dashboardItemsProvider` and `accessContextProvider` must be overridden in
  the root container; `DashboardItem` equality is by `id`.
- There is no app-wide localization hook: default English texts are
  overridden per widget or call.
- `InMemoryAuthAdapter` stores plain-text passwords and unsigned tokens:
  demos and tests only.
