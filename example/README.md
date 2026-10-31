# symphony_core example

A complete, feature-first application built on `symphony_core`. It runs
**without any server**: an in-process demo backend (a Dio
`HttpClientAdapter`) answers every request of the package's `ApiClient`, so
the whole client pipeline — token injection and refresh, retries, the API
inspector, secure logging and error mapping — runs for real.

Every module of the package is used: core (config, DI, `Result`/`Failure`,
utilities), storage, networking, inspector, auth, routing, dashboard and UI.

## Run it

```bash
cd example
flutter pub get
flutter run            # any platform: Android, iOS, web, Windows, macOS, Linux
flutter test           # widget, integration and backend tests
```

Supported toolchains are the package's: Flutter 3.29 (Dart 3.7) → latest
stable, Riverpod 3.x (`flutter_riverpod >=3.0.1`), go_router 10 → 18.

## Demo accounts

Password for every account: **`password123`** (also shown on the login
screen; tap an account to sign in in one tap).

| Account                  | Role     | Permissions                    | What you see                              |
|--------------------------|----------|--------------------------------|-------------------------------------------|
| `admin@example.com`      | `admin`  | all                            | every module, Admin submenu, exports      |
| `staff@example.com`      | `staff`  | `orders.read`                  | Orders; `/admin` → unauthorized page      |
| `viewer@example.com`     | `viewer` | none                           | Files, Components, Profile, Settings only |
| `unverified@example.com` | `viewer` | none                           | rejected by a client-side `sessionValidator` |

Registration creates a `viewer` account; the password reset code is always
`123456`.

## What each screen demonstrates

| Screen | Route | Demonstrates |
|--------|-------|--------------|
| Splash | `/splash` | `SymphonySplashScreen` with `onInitialize` (restore preferences, apply the stored base URL, health check `GET /status`), then session restoration |
| Login | `/login` | `SymphonyLoginScreen` + `SymphonyLoginForm`, `GuestRoute`, "session expired" banner from `AuthUnauthenticated.failure` |
| Register / Forgot password | `/register`, `/forgot-password` | `SymphonyRegisterForm` (strength meter, server field errors), `SymphonyForgotPasswordForm` with the confirmation step |
| Dashboard | `/` | `SymphonyDashboard`: permission-filtered modules, nested submenu (Admin → Overview / Users / Audit log), custom icon (`iconBuilder`), badges (live pending-orders count, `New`, dot), custom action (`onTap` opens the inspector); a drawer built with `watchVisibleDashboardItems` |
| Orders | `/orders`, `/orders/:orderId` | Clean architecture feature: entities + repository interface (domain), `ApiClient` repository with decoders and `guardResult` (data), `FutureProvider`s returning `Result` (presentation); debounced search (`Debouncer`), status filter, pull to refresh, nested detail route, `AccessGate` on the refund button |
| Reports | `/reports` | `GuardedRoute` with a permission, KPIs laid out with `responsiveColumns` / `ResponsiveBuilder`, CSV export with `downloadBytes` + `SymphonyDialogs.runWithLoading`, `AccessGate` (`reports.export`) |
| Admin | `/admin`, `/admin/users`, `/admin/audit-log` | Role guard covering nested routes; the audit log lists real events recorded by the backend (sign-ins, refreshes, uploads…) |
| Files | `/files` | Multipart upload of `UploadFile.fromBytes` files with send progress, `downloadBytes` with receive progress, text preview, transfer history in the package `LocalDatabase` (`localDatabaseProvider`) shown through a `StreamProvider` |
| Settings | `/settings` | Light/dark theme (`SymphonyTheme`), runtime environment switch with `apiClient.updateBaseUrl` (`baseUrlListenable`), `showApiInspector`, demo backend tools (expire access tokens, revoke sessions, simulate an outage), storage status, sign-out with `SymphonyDialogs.confirm` |
| Profile | `/profile` | Current user, roles and permissions mapped by `AuthResponseMapping`, `AccessGate` examples (role, permission, any-of, predicate), `ref.watchCanAccess` |
| Components | `/components` | Every `SymphonyButton` variant/size/loading state, `SymphonyIconButton`, text and password fields with `SymphonyValidators` and the strength meter, all dialogs, all snackbar types, `SymphonyLoadingOverlay`, empty and error states, `ResponsiveLayout` / `ResponsiveBuilder` / `ResponsiveValue` |
| Unauthorized / error | `/unauthorized`, any unknown path | `SymphonyUnauthorizedScreen`, `SymphonyRouteErrorScreen` |

The draggable **HTTP** button (`SymphonyInspectorOverlay`, installed in
`MaterialApp.router(builder: ...)`) opens the API inspector from any screen.

### Things to try

* Wait 30 seconds after signing in (access tokens live 30 s), or tap
  *Settings → Expire access token*, then open Orders: the inspector shows
  `GET /orders 401` → `POST /auth/token/refresh 200` → `GET /orders 200`,
  and the UI never notices.
* *Settings → Revoke sessions*, then refresh a page: the refresh fails, you
  are signed out, and signing in again returns to the page you were on.
* Sign in as `staff@example.com` and open `/admin` (web: type the URL).
* Switch to *Staging* in the settings: every request now goes to
  `https://staging.api.example.com` (look at the hosts in the inspector).
* Turn on *Simulate a network outage* and open any module: `NetworkFailure`
  → `SymphonyErrorView` with a retry button.

## Where to look in the code

```
lib/
  main.dart                    SymphonyCore.initialize(...) + SymphonyScope
  app/
    example_app.dart           MaterialApp.router, themes, inspector overlay
    app_router.dart            routerProvider = SymphonyRouter.create(...)
    app_startup.dart           start-up tasks run by the splash screen
    app_theme.dart             SymphonyThemeConfig → SymphonyTheme.light/dark
  core/
    backend/                   the in-process demo backend (HttpClientAdapter)
    network/api_envelope.dart  decoding helpers for {"status","result"} bodies
    storage/                   ResilientKeyValueStorage (secure storage + fallback)
    routing/app_routes.dart    route paths
    widgets/                   AsyncResultView, AppPage, SectionCard...
  features/<feature>/
    domain/                    entities, repository interfaces (pure logic)
    data/                      ApiClient repositories, decoders, storage
    presentation/              providers/controllers, pages, widgets
```

Key integration points:

* **Wiring** — [`lib/main.dart`](lib/main.dart): configuration, the auth
  adapter (`authAdapterBuilder`), the secure storage and the single override
  that plugs in the demo backend
  (`httpClientAdapterProvider.overrideWithValue(DemoBackend())`). Remove that
  override (and point `baseUrl` to your server) to use a real API.
* **Authentication** —
  [`features/auth/data/example_auth_adapter.dart`](lib/features/auth/data/example_auth_adapter.dart):
  `RestAuthEndpoints` (the backend's own paths), custom request bodies
  (`login`/`secret`, `renewal_token`...), a custom `AuthResponseMapping` for
  the backend's non-default response shape
  (`result.credentials.jwt`, `result.account.groups[].slug`, space-separated
  `grants`...) and a `sessionValidator` business rule.
* **Routing** — [`app/app_router.dart`](lib/app/app_router.dart): `GuardedRoute`
  (authentication, permissions, roles) protecting nested routes, `GuestRoute`
  pages, `restoreSessionOnStart: false` because the splash restores the
  session after the start-up tasks.
* **A data feature** — [`features/orders`](lib/features/orders): the
  reference for writing a feature with `ApiClient`, decoders, `Result` and
  providers.

### Riverpod 3 notes

* The data providers return `Result<T>` instead of throwing. Riverpod 3
  automatically retries providers that throw (and reports them as loading
  meanwhile), which would delay error screens by many seconds.
  [`AsyncResultView`](lib/core/widgets/async_result_view.dart) renders them.
* Override lists are passed as literals (`overrides: [...]`): Riverpod 3
  exports the `Override` type from `package:flutter_riverpod/misc.dart`, not
  from `flutter_riverpod.dart`.
* The providers are plain `Provider`, `FutureProvider(.family)`,
  `StreamProvider` and `NotifierProvider` (no code generation).

## Tests

* `test/app_flow_test.dart` — widget tests on an isolated
  `SymphonyCore.create(...)` + `SymphonyScope(core: ...)`: splash → login,
  admin sees every module, viewer does not see gated modules, staff on
  `/admin` lands on the unauthorized page, deep link resumes after sign-in,
  orders list/detail, transparent refresh and revoked session in the UI,
  sign-out.
* `test/token_refresh_test.dart` — integration tests through `ApiClient` and
  the providers: custom response mapping, expired token refreshed and the
  request replayed (also visible in the inspector), single-flight refresh,
  revoked session, session restored after an app restart.
* `test/demo_backend_test.dart` — authentication flows, permissions enforced
  by the backend, repositories and decoders, multipart round trip with
  progress, environments, network outage, multipart parser.
* `test/screens_test.dart` — every screen renders without layout errors on
  desktop and phone sizes, profile, settings, files and guest pages.

The tests use `tester.pump` with durations (`pumpUntilFound`) rather than
`pumpAndSettle`, which never settles while progress indicators animate.

## Notes

* The demo backend (`lib/core/backend`) is for demonstrations only: plain
  text passwords, checksum-"signed" tokens, data in memory (sessions survive
  restarts because tokens are self-describing).
* On macOS, `flutter_secure_storage` needs the Keychain Sharing entitlement;
  without it the example falls back to in-memory storage
  (`ResilientKeyValueStorage`) and the session is not persisted.
