# Compatibility

symphony_core keeps a single codebase compatible with a wide range of Flutter
and dependency versions. This page lists the supported ranges, what was
actually verified, platform notes, behaviour that differs between versions,
how to reproduce the checks, and the policy for changing the ranges.

- [Supported ranges](#supported-ranges)
- [Verified matrix](#verified-matrix)
- [Not verified](#not-verified)
- [Platform notes](#platform-notes)
- [Version-specific behaviour](#version-specific-behaviour)
- [Reproducing the matrix](#reproducing-the-matrix)
- [Policy for version ranges](#policy-for-version-ranges)

## Supported ranges

Ranges declared in `pubspec.yaml`:

| Package | Range | Notes |
|---|---|---|
| Dart SDK | `>=3.0.0 <4.0.0` | The package's language version is 3.0. |
| Flutter | `>=3.10.0` | |
| dio | `>=5.4.0 <6.0.0` | |
| flutter_riverpod | `>=2.4.0 <4.0.0` | Riverpod 2 and Riverpod 3. |
| go_router | `>=10.0.0 <19.0.0` | go_router 18 requires Flutter 3.44 / Dart 3.12, so older SDKs resolve an older major. |
| flutter_secure_storage | `>=9.0.0 <12.0.0` | 10.0 changed the Android ciphers and minimum SDK (see [Android](#android)). |
| flutter_lints (dev) | `>=3.0.0 <7.0.0` | |
| mocktail (dev) | `>=1.0.0 <2.0.0` | |

To stay inside these ranges, the code only uses APIs that exist at both ends:
the Riverpod subset common to 2.4 and 3.x (no `StateProvider`,
`StateNotifierProvider`, `ChangeNotifierProvider`, auto-dispose or family
notifiers, code generation), the go_router subset common to 10 and 18 (for
example `GoRouterState.uri`, never `location`), Flutter APIs that exist in
3.10 and are not deprecated in 3.44, and no Dart feature newer than 3.0 (no
dot shorthands, null-aware collection elements, extension types or digit
separators). `lib/` never imports `dart:io`.

## Verified matrix

Verified on **2026-10-31** on a Windows host. For each row, dependencies were
resolved with `flutter pub downgrade` (lowest) or `flutter pub upgrade`
(highest), then `flutter analyze` reported no issues and `flutter test` passed
all **1112** unit and widget tests (Flutter test VM).

| Flutter (Dart) | Resolution | dio | flutter_riverpod (riverpod) | go_router | flutter_secure_storage | flutter_lints | mocktail |
|---|---|---|---|---|---|---|---|
| 3.10.6 (3.0.6) | lowest | 5.4.0 | 2.4.0 (2.4.0) | 10.0.0 | 9.0.0 | 3.0.0 | 1.0.0 |
| 3.10.6 (3.0.6) | highest resolvable | 5.11.1 | 2.4.10 (2.5.0) | 13.1.0 | 9.2.4 | 3.0.1 | 1.0.5 |
| 3.44.8 (3.12.2) | lowest | 5.4.0 | 2.4.0 (2.4.0) | 10.0.0 | 9.0.0 | 3.0.0 | 1.0.0 |
| 3.44.8 (3.12.2) | latest | 5.11.1 | 3.4.3 (3.4.3) | 18.1.2 | 11.2.0 | 6.0.0 | 1.0.5 |

"Highest resolvable" on Flutter 3.10.6 stops below the latest releases
because newer releases of Riverpod, go_router, flutter_secure_storage and
flutter_lints require a newer SDK; pub then selects the newest compatible
release.

The Dart snippets of the documentation (README, migration guide and this
page) are analyzed and compiled against the first and the last row as well,
and the README's test snippets are run there.

## Not verified

Known gaps, to keep in mind before relying on a combination:

- **Flutter versions between 3.10.6 and 3.44.8**, and 3.10.0–3.10.5. They
  are inside the declared range but were not run.
- **Riverpod 3.0–3.3.** Not run. The import path the package uses for
  `Override` and `ProviderListenable` (see
  [Version-specific behaviour](#version-specific-behaviour)) was additionally
  checked on flutter_riverpod 2.6.1, 3.0.3 and 3.4.2.
- **go_router 14–17.** Not run as a whole. The way `GuardedRoute` /
  `GuestRoute` find their router's access source was additionally checked on
  go_router 14.8.1, 17.0.1 and 17.5.0 (the 17.0.x redirect difference listed
  below was observed there).
- **Intermediate dio and flutter_secure_storage releases** (for example dio
  5.5–5.10 and flutter_secure_storage 10.x).
- **Native platforms.** No device, emulator, browser or desktop build was
  run. Tests run on the Flutter test VM, where platform plugins
  (flutter_secure_storage) are replaced by fakes, so the platform side of
  secure storage is not covered.

Please report combinations that fail, with the output of `flutter --version`
and the resolved versions (`flutter pub deps --style=compact`).

## Platform notes

### Web

- `lib/` does not import `dart:io`, so nothing in the package itself blocks a
  web build (web builds are not part of the verified matrix).
- `ApiClient.download()` (to a file) throws an `UnsupportedFailure`; use
  `downloadBytes()`. `UploadFile.fromPath` throws an `UnsupportedFailure`;
  use `UploadFile.fromBytes`.
- A relative `SymphonyConfig.baseUrl` (for example `/api`) is accepted on the
  web only; other platforms require an absolute URL.
- `sendTimeout` is not applied to requests without a body (Dio would log a
  warning for every such request).
- The backend must allow the app's origin (CORS); the browser blocks the
  requests otherwise.
- flutter_secure_storage stores data in `localStorage`, encrypted with
  WebCrypto. The plugin documents this implementation as experimental,
  requires HTTPS (or `localhost`) and recommends HTTP Strict Transport
  Security. Data is bound to the browser and origin. Any script running on
  the origin can reach `localStorage`, so assess XSS risk for persisted
  sessions. To keep the session in memory only on the web (signed out on
  reload):

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:symphony_core/symphony_core.dart';

Future<void> main() async {
  await SymphonyCore.initialize(
    config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
    authAdapterBuilder: (ref) => RestAuthAdapter(
      apiClient: ref.watch(apiClientProvider),
      endpoints: const RestAuthEndpoints(login: '/auth/login'),
    ),
    overrides: [
      if (kIsWeb)
        sessionStorageProvider.overrideWith(
          (ref) => SecureSessionStorage(InMemoryKeyValueStorage()),
        ),
    ],
  );
  runApp(const SymphonyScope(child: MyApp()));
}
```

### Android

- flutter_secure_storage 9.x requires `minSdkVersion` 18. Version 10.0 and
  later require **minSdk 23**, use new default ciphers (RSA OAEP + AES-GCM)
  and migrate data written by 9.x automatically (see the plugin's
  documentation). Check `android/app/build.gradle` when your resolution moves
  to 10.x or 11.x.
- Android Auto Backup can restore the plugin's encrypted preferences on a new
  device without the Keystore keys, which fails with
  `InvalidKeyException` (surfacing as a `StorageFailure`). Disable backup
  (`android:allowBackup="false"`) or exclude the plugin's shared preferences
  from backup.
- The system back button is not intercepted by the package (see
  [Version-specific behaviour](#version-specific-behaviour)). In
  `MaterialApp.router` apps, back closes the inspector's pages and then the
  inspector panel; in `Navigator`-based `MaterialApp` apps the app's
  navigator handles back first. Android 14 predictive back is not handled
  specifically.

### iOS and macOS

- Secrets are stored in the Keychain. Pass `IOSOptions` (for example
  `accessibility: KeychainAccessibility.first_unlock` for background access)
  by overriding `flutterSecureStorageProvider`.
- macOS: add the `keychain-access-groups` entitlement to both
  `DebugProfile.entitlements` and `Release.entitlements` (plugin
  requirement), and `com.apple.security.network.client` for outgoing HTTP
  requests from the sandboxed app.
- iOS Keychain items survive uninstalling the app, so a reinstalled app can
  restore the previous session. Clear the session on first launch if that is
  not wanted (`ref.read(authRepositoryProvider).clearSession()`).

### Windows

- flutter_secure_storage 9.x documents that `readAll` and `deleteAll` are not
  supported on Windows. `SecureKeyValueStorage.readAll()` and `clear()` rely
  on them (the default `secureStorageProvider`, which uses a key prefix,
  clears through `readAll`); `SecureSessionStorage` (the auth session) only
  uses `read`, `write` and `delete`. Check the plugin's notes for the version
  you resolve.
- flutter_secure_storage 11.x needs the C++ ATL libraries of the Visual Studio
  Build Tools to build.

### Linux

- flutter_secure_storage uses `libsecret`: the development package is needed
  to build and the runtime package to run (for example
  `libsecret-1-dev` / `libsecret-1-0` on Debian and Ubuntu).

## Version-specific behaviour

| Area | Versions | Behaviour | What to do |
|---|---|---|---|
| Riverpod types | 3.x | `Override` and `ProviderListenable` are not exported by `package:flutter_riverpod/flutter_riverpod.dart`, only by `package:flutter_riverpod/misc.dart` (which does not exist in 2.x). Internally the package imports them from `flutter_riverpod/src/internals.dart`, the only path common to both majors. | In app code, let override lists be inferred (`overrides: [p.overrideWithValue(x)]`). To write `List<Override>` on Riverpod 3, import `misc.dart`. |
| Provider errors | 3.x | Errors thrown while a provider builds are rethrown wrapped in a `ProviderException`; 2.x rethrows the original error (for example the `StateError` of an unconfigured `symphonyConfigProvider`). | In tests, match on the message text, not on the error type. |
| Duplicate overrides | 2.x vs 3.x | When `overrides` targets a provider that `symphonyOverrides` also overrides (config, adapter, token delegate, secure storage, error reporter): on 3.x the built-in override is dropped (3.x asserts on duplicates in debug); on 2.x both are kept and the last one, yours, wins. A `ProviderScope` rebuilt with such a list may assert in debug on 2.x when the two overrides are of different kinds (`overrideWith` vs `overrideWithValue`). | Use the named parameters (`config`, `authAdapter`, `secureStorage`, `errorReporter`) instead of overriding these providers. |
| Automatic retry | 3.x | Riverpod 3 retries providers that fail with an `Exception` (up to 10 times, 200 ms to 6.4 s backoff; `Error`s are not retried). `Failure` implements `Exception`, so your `FutureProvider`s that throw failures are retried. The container created by `SymphonyCore` keeps Riverpod's default policy. | Configure retries per provider with Riverpod 3's `retry:` parameter if needed. Riverpod 2 never retries. |
| Dependent updates | 2.4 | Providers depending on a changed provider are refreshed in a microtask. | In widget tests, `pump()` / `pumpAndSettle()` after an authentication change before asserting. |
| Shell routes | go_router 10 | `ShellRoute` redirects are not evaluated. | Protect the `GoRoute`s inside the shell with `GuardedRoute`, or wrap the shell UI with `AccessGate`. |
| Pushed pages | go_router 10 vs 13+ | When the router refreshes (access change), go_router 13 and later only re-evaluate the redirects of the page below the pages opened with `push`; go_router 10 evaluates the pushed routes' redirects, but against the base location. | Nothing: `SymphonyRouter`'s global redirect re-checks every pushed page itself on all versions and replaces the stack when one is no longer allowed. |
| Redirect limit | go_router 10 | Each redirect hop is counted twice against `redirectLimit`, so the default limit of 5 allows about 3 hops. The built-in flows need at most 2. | Raise `redirectLimit` if your own redirects chain several hops. |
| Top-level redirect | some go_router 17.x (seen on 17.0.1; behaves normally again on 17.5.0 and 18.x) | The top-level redirect is evaluated at most once per navigation. The built-in rules still resolve (they are idempotent and route guards return final targets), but your global `redirect` is not re-run on a location the built-in rules produced during the same navigation. | Prefer route-level redirects for app rules, or avoid the affected 17.x releases. |
| Case sensitivity | go_router 15+ | URL matching is case-sensitive by default (`caseSensitive: true`, a parameter that does not exist before 15). The package's own checks (splash, login, guest-only and public paths) are case-insensitive on every version, but `/Login` no longer matches a `/login` route and shows the error page. | Use lower-case links; the package does not pass `caseSensitive`. |
| Minimum SDK | go_router 18 | Requires Flutter 3.44 / Dart 3.12. Flutter 3.10.6 resolves at most go_router 13.1.0. | Nothing; pub picks a compatible major. |
| Multipart | dio 5.4 | Files without an explicit content type are sent as `application/octet-stream`; dio 5.11 infers it from the file name. | Always set `UploadFile.contentType`. |
| Connect timeout | dio on native platforms | Per-request `connectTimeout` is applied on both dio ends by an internal interceptor; on `dart:io` platforms Dio applies it to its shared `HttpClient`, so concurrent requests with different connect timeouts are best-effort. | Prefer one connect timeout per app (`SymphonyConfig.connectTimeout`). |
| Back button | Flutter 3.10 (no `PopScope`) | To support 3.10 without deprecated APIs, the package intercepts no back navigation: inline dashboard submenus do not close on system back, and `SymphonyDialogs.showLoading` can be dismissed with Android back (its handle then reports `isOpen == false` and completes `closed`). | On Flutter 3.24+, wire `SymphonyDashboardController` with `PopScope(onPopInvokedWithResult: ...)` (README, Dashboard). Use `submenuPresentation: DashboardSubmenuPresentation.page` for route-based submenus. |
| Snack bars | recent Flutter (3.44 has `SnackBar.persist`) vs 3.10 | On recent Flutter, snack bars with an action stay on screen until dismissed; Flutter 3.10 hides them after `duration`. | `SymphonySnackbar` shows a close icon whenever an action is set (`showCloseIcon`). |
| Lints | flutter_lints 3.x and 4.x | `prefer_const_constructors` and related rules are enabled (removed in 5.0). | Add `const` where suggested (for example to the quick-start `SymphonyConfig`). |
| Test matchers | Flutter 3.44 vs 3.10 | `matchesSemantics`, `containsSemantics` and `SemanticsData.hasFlag` are deprecated in 3.44, and their replacements do not exist in 3.10. | For tests that must run on both, assert on `SemanticsData.label` / `value` / `hint` / `hasAction`. |

Toolchain note: the analyzer accepts, but the compiler rejects (on both
3.10.6 and 3.44.8), a list literal with an explicit
`<ThemeExtension<dynamic>>` type argument that spreads another iterable, for
example `<ThemeExtension<dynamic>>[...extra, BrandColors()]`. Pass the
iterable directly (`SymphonyThemeConfig(extensions: extra)`) or let the type
be inferred (`extensions: [...extra]`). Always compile (run the tests);
`flutter analyze` alone does not catch it.

## Reproducing the matrix

### Locally

Run both resolutions with the oldest and with the newest SDK you support:

```sh
# Lowest versions allowed by pubspec.yaml
flutter pub downgrade
flutter analyze
flutter test

# Highest versions your SDK can resolve
flutter pub upgrade
flutter analyze
flutter test

# Show what was resolved
flutter pub deps --style=compact | grep -E "^- (dio|flutter_riverpod|riverpod|go_router|flutter_secure_storage) "
```

- Keep a second SDK for the minimum (for example a Flutter checkout at tag
  `3.10.6`: `git clone -b 3.10.6 https://github.com/flutter/flutter.git
  flutter-3.10.6`) and call its `bin/flutter` explicitly, or use a version
  manager such as FVM.
- `pub downgrade` needs network access to reach the oldest versions; offline
  it may stop at versions already in the cache.
- `downgrade` and `upgrade` rewrite `pubspec.lock` (not committed for the
  package). Run `flutter pub get` afterwards to return to your usual
  resolution.
- Repeat the same commands in `example/`.

### In CI

[`.github/workflows/ci.yaml`](.github/workflows/ci.yaml) reproduces the
matrix on every push to `main` and every pull request:

- **test**: `flutter: [3.10.6, stable]` × `deps: [downgrade, upgrade]`. Each
  job resolves with `flutter pub <deps>`, prints the resolved versions, runs
  `flutter analyze` and `flutter test`, then does the same in `example/`.
- **format**: `dart format --output=none --set-exit-if-changed lib test
  example/lib example/test` on stable.
- **publish-dry-run**: `dart pub publish --dry-run` on stable.

The `stable` jobs move with Flutter and dependency releases: a failure there
without a code change usually means a new release changed behaviour or
deprecated an API. Fix it, or pin the upper bound until it is fixed.

## Policy for version ranges

1. Every change to a range lands with a green CI matrix that covers the new
   bounds, and is listed under **Compatibility** in the CHANGELOG.
2. **Widening an upper bound** (allowing a new major, such as go_router 19 or
   Riverpod 4) is non-breaking: a patch release before 1.0 (`0.1.x`), a minor
   release from 1.0. It is only done once the whole test suite passes on the
   new version, with any version-specific behaviour documented here.
3. **Raising a minimum** (the Flutter / Dart SDK or a dependency's lower
   bound):
   - before 1.0: a breaking release (`0.x` → `0.(x+1).0`);
   - from 1.0: a **minor** release when the new minimum stays within the same
     major (for example dio 5.4 → 5.6, Flutter 3.10 → 3.16), because pub
     never selects a release whose constraints an app cannot satisfy: apps on
     older stacks keep the previous release;
   - from 1.0: a **major** release when a whole major is dropped (Riverpod 2,
     go_router 10–12, Dart 3).
   - never in a patch release.
4. Minimums are raised only for a concrete reason (a needed API, a security
   fix, a bug that cannot be worked around) and announced in the CHANGELOG
   one release in advance when possible.
5. Upper bounds stay at `<next major>`. Compatibility shims (such as the
   internal Riverpod type bridge) are removed only when the versions that need
   them are dropped.
