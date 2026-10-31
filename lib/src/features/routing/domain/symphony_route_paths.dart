import 'package:flutter/foundation.dart';

/// Locations of the application routes that the routing guards redirect to.
///
/// These are *app routes* — paths registered in the application's
/// `GoRouter` — not backend endpoints. Every path must start with `/`.
///
/// ```dart
/// const paths = SymphonyRoutePaths(
///   splash: '/splash',
///   login: '/auth/login',
///   home: '/dashboard',
///   unauthorized: '/forbidden',
///   guestOnlyPaths: {'/auth/register', '/auth/forgot-password'},
/// );
/// ```
///
/// Path comparisons made by the guards are case-insensitive, ignore trailing
/// slashes and treat an entry as covering its descendants: `/auth/register`
/// also matches `/auth/register/step-2`. The root path `/` only matches
/// itself.
@immutable
class SymphonyRoutePaths {
  /// Creates the route paths.
  const SymphonyRoutePaths({
    this.splash = '/splash',
    this.login = '/login',
    this.home = '/',
    this.unauthorized = '/unauthorized',
    this.redirectParameter = 'from',
    this.guestOnlyPaths = const <String>{},
  });

  /// Route shown while the persisted session is being restored (the access
  /// status is still unknown).
  ///
  /// Locations requested during that time are remembered in the
  /// [redirectParameter] and resumed once the status is known.
  final String splash;

  /// Sign-in route. It is always guest-only: signed-in users visiting it are
  /// sent to the location remembered in [redirectParameter], or to [home].
  final String login;

  /// Default destination of signed-in users (after sign-in, when leaving the
  /// splash screen or when visiting a guest-only page).
  final String home;

  /// Route shown to signed-in users who lack the roles or permissions of a
  /// guarded route. When `null`, such users are sent to [home].
  ///
  /// A guarded route can override it with its own `deniedRedirect`.
  final String? unauthorized;

  /// Name of the query parameter carrying the originally requested location,
  /// for example `/login?from=%2Forders%3Fpage%3D2`.
  final String redirectParameter;

  /// Additional guest-only paths (for example `/register` or
  /// `/forgot-password`). Signed-in users visiting them are redirected like
  /// on [login]. Each entry also covers its descendants.
  final Set<String> guestOnlyPaths;

  /// Normalizes [path] for comparisons: guarantees a leading `/` and removes
  /// trailing slashes (the root path stays `/`).
  static String normalizePath(String path) {
    var end = path.length;
    while (end > 1 && path.codeUnitAt(end - 1) == 0x2F) {
      end--;
    }
    final trimmed = path.substring(0, end);
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  /// Whether [path] equals [entry] or is one of its descendants.
  ///
  /// The comparison is case-insensitive and ignores trailing slashes. The
  /// root entry `/` only matches the root path.
  static bool matchesPath(String path, String entry) {
    final candidate = normalizePath(path).toLowerCase();
    final reference = normalizePath(entry).toLowerCase();
    if (candidate == reference) return true;
    if (reference == '/') return false;
    return candidate.startsWith('$reference/');
  }

  /// Whether [path] is the [splash] route (or below it).
  bool isSplash(String path) => matchesPath(path, splash);

  /// Whether [path] is the [login] route (or below it).
  bool isLogin(String path) => matchesPath(path, login);

  /// Whether [path] is reserved to signed-out users: the [login] route or
  /// one of [guestOnlyPaths] (including their descendants).
  bool isGuestOnly(String path) =>
      isLogin(path) ||
      guestOnlyPaths.any((String entry) => matchesPath(path, entry));

  /// Returns [location] with the [redirectParameter] set to [from].
  ///
  /// Existing query parameters of [location] are kept. When [from] is `null`
  /// the location is returned unchanged.
  String withRedirectParameter(String location, String? from) {
    if (from == null) return location;
    final uri = Uri.parse(location);
    return uri
        .replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            redirectParameter: from,
          },
        )
        .toString();
  }

  /// The [splash] location, remembering [from] when given.
  String splashLocation({String? from}) => withRedirectParameter(splash, from);

  /// The [login] location, remembering [from] when given.
  String loginLocation({String? from}) => withRedirectParameter(login, from);

  /// Returns a copy with the given fields replaced.
  ///
  /// [unauthorized] cannot be cleared with this method; create a new instance
  /// instead.
  SymphonyRoutePaths copyWith({
    String? splash,
    String? login,
    String? home,
    String? unauthorized,
    String? redirectParameter,
    Set<String>? guestOnlyPaths,
  }) {
    return SymphonyRoutePaths(
      splash: splash ?? this.splash,
      login: login ?? this.login,
      home: home ?? this.home,
      unauthorized: unauthorized ?? this.unauthorized,
      redirectParameter: redirectParameter ?? this.redirectParameter,
      guestOnlyPaths: guestOnlyPaths ?? this.guestOnlyPaths,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SymphonyRoutePaths &&
      other.splash == splash &&
      other.login == login &&
      other.home == home &&
      other.unauthorized == unauthorized &&
      other.redirectParameter == redirectParameter &&
      setEquals(other.guestOnlyPaths, guestOnlyPaths);

  @override
  int get hashCode => Object.hash(
    splash,
    login,
    home,
    unauthorized,
    redirectParameter,
    Object.hashAllUnordered(guestOnlyPaths),
  );

  @override
  String toString() =>
      'SymphonyRoutePaths(splash: $splash, login: $login, '
      'home: $home, unauthorized: $unauthorized, '
      'redirectParameter: $redirectParameter, '
      'guestOnlyPaths: $guestOnlyPaths)';
}
