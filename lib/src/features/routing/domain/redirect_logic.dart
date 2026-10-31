import 'package:flutter/foundation.dart';

import '../../../core/access/access_context.dart';
import '../../../core/access/access_requirement.dart';
import 'symphony_route_paths.dart';

/// Pure redirect rules used by `SymphonyRouter`, `GuardedRoute` and
/// `GuestRoute`.
///
/// Every method is synchronous, side-effect free and independent of Flutter
/// widgets, so the whole routing policy can be unit tested with plain
/// [AccessContext] and [Uri] values. A method returns the location to
/// redirect to, or `null` to let the navigation proceed.
///
/// ### Global rules ([resolveGlobal])
/// * Status unknown (session being restored): every location except the
///   splash route and the [publicPaths] goes to
///   `splash?from=<requested location>`.
/// * Status known while on the splash route: signed-in users go to the
///   remembered location (or [SymphonyRoutePaths.home]); signed-out users go
///   to the remembered location (or [SymphonyRoutePaths.login]) where the
///   route guards take over — a guarded location sends them to
///   `login?from=...`, a guest-only or unguarded one is simply shown.
/// * Signed-in users on a guest-only route (the login route included) go to
///   the remembered location (or home).
///
/// ### Route rules ([resolveGuard], [resolveGuest])
/// * Requirement not met and the status unknown: `splash?from=<location>`.
/// * Requirement not met and signed out: `login?from=<location>`.
/// * Requirement not met although signed in (missing roles, permissions or
///   predicate): the route's `deniedRedirect`, else
///   [SymphonyRoutePaths.unauthorized], else home. A target pointing at the
///   current page is skipped so a denied page is never shown.
///
/// ### Open-redirect protection ([sanitizeTarget])
/// Remembered locations are only followed when they are in-app paths: they
/// must start with exactly one `/`, contain no scheme, host, backslash or
/// control character, and must not point at the splash or login routes
/// (which would create loops).
@immutable
class SymphonyRedirectResolver {
  /// Creates a resolver for [paths].
  ///
  /// [publicPaths] are reachable without waiting for the session restoration
  /// (for example `/terms` or `/reset-password`). Each entry also covers its
  /// descendants. Route guards still apply to them.
  const SymphonyRedirectResolver({
    this.paths = const SymphonyRoutePaths(),
    this.publicPaths = const <String>{},
  });

  /// Locations of the splash, login, home and unauthorized routes.
  final SymphonyRoutePaths paths;

  /// Paths never redirected to the splash route while the status is unknown.
  final Set<String> publicPaths;

  /// Whether [path] is one of [publicPaths] (or below one of them).
  bool isPublicPath(String path) => publicPaths
      .any((String entry) => SymphonyRoutePaths.matchesPath(path, entry));

  /// The in-app location of [uri]: its path, query and fragment, without
  /// scheme or authority.
  ///
  /// Deep links can reach the router as absolute URIs
  /// (`https://example.com/orders?page=2`); remembering only the in-app part
  /// keeps them valid redirect targets.
  static String locationOf(Uri uri) {
    final path = uri.path;
    final buffer = StringBuffer(path.startsWith('/') ? path : '/$path');
    if (uri.hasQuery) buffer.write('?${uri.query}');
    if (uri.hasFragment) buffer.write('#${uri.fragment}');
    return buffer.toString();
  }

  /// Returns [target] when it is a safe in-app location to redirect to,
  /// otherwise `null`.
  ///
  /// Rejected values: `null`/empty, values not starting with exactly one `/`
  /// (relative paths, `//host` protocol-relative URLs), values with a scheme
  /// or authority, backslashes or control/whitespace characters (also when
  /// percent-encoded), invalid percent-encoding, and locations on the splash
  /// or login routes.
  String? sanitizeTarget(String? target) {
    if (target == null || target.isEmpty) return null;
    if (!target.startsWith('/') || target.startsWith('//')) return null;
    if (_hasForbiddenCharacter(target, rejectSpace: true)) return null;
    final uri = Uri.tryParse(target);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
    final String decodedPath;
    try {
      decodedPath = Uri.decodeFull(uri.path);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    if (decodedPath.startsWith('//') ||
        _hasForbiddenCharacter(decodedPath, rejectSpace: false)) {
      return null;
    }
    final path = SymphonyRoutePaths.normalizePath(uri.path);
    if (paths.isSplash(path) || paths.isLogin(path)) return null;
    return target;
  }

  /// The sanitized location remembered in the
  /// [SymphonyRoutePaths.redirectParameter] of [location], if any.
  ///
  /// Malformed query strings yield `null` instead of throwing.
  String? redirectTargetOf(Uri location) {
    final String? raw;
    try {
      raw = location.queryParameters[paths.redirectParameter];
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    return sanitizeTarget(raw);
  }

  /// Global rule evaluated before any route-level guard.
  ///
  /// [location] is the requested URI (`GoRouterState.uri`). See the class
  /// documentation for the rules.
  String? resolveGlobal(AccessContext access, Uri location) {
    final path = SymphonyRoutePaths.normalizePath(location.path);
    if (access.isUnknown) {
      if (paths.isSplash(path) || isPublicPath(path)) return null;
      return paths.splashLocation(from: _originOf(location));
    }
    if (paths.isSplash(path)) {
      final from = redirectTargetOf(location);
      if (access.isAuthenticated) return _signedInTarget(from);
      return from ?? paths.login;
    }
    if (access.isAuthenticated && paths.isGuestOnly(path)) {
      final target = _signedInTarget(redirectTargetOf(location));
      return _isSamePath(target, path) ? null : target;
    }
    return null;
  }

  /// Rule of a guarded route: lets [access] through when it satisfies
  /// [requirement], otherwise returns where to send the user.
  ///
  /// [location] is the requested URI (`GoRouterState.uri`). [deniedRedirect]
  /// overrides [SymphonyRoutePaths.unauthorized] for signed-in users lacking
  /// the required roles or permissions.
  String? resolveGuard(
    AccessContext access,
    Uri location, {
    AccessRequirement requirement = AccessRequirement.authenticated,
    String? deniedRedirect,
  }) {
    if (requirement.isSatisfiedBy(access)) return null;
    final origin = _originOf(location);
    if (access.isUnknown) return paths.splashLocation(from: origin);
    if (!access.isAuthenticated) {
      return paths.loginLocation(from: _isPlainHome(origin) ? null : origin);
    }
    final path = SymphonyRoutePaths.normalizePath(location.path);
    final candidates = <String?>[
      deniedRedirect,
      paths.unauthorized,
      paths.home,
      paths.login,
    ];
    for (final candidate in candidates) {
      if (candidate != null && !_isSamePath(candidate, path)) return candidate;
    }
    return paths.splash;
  }

  /// Rule of a guest-only route (sign-in, registration...): signed-in users
  /// are sent to [authenticatedRedirect] when given, otherwise to the
  /// remembered location or home. Other users are let through.
  String? resolveGuest(
    AccessContext access,
    Uri location, {
    String? authenticatedRedirect,
  }) {
    if (!access.isAuthenticated) return null;
    final target =
        authenticatedRedirect ?? _signedInTarget(redirectTargetOf(location));
    final path = SymphonyRoutePaths.normalizePath(location.path);
    return _isSamePath(target, path) ? null : target;
  }

  /// Location worth remembering for [location]: the location itself, or the
  /// location it already remembers when it is the splash or login route.
  String? _originOf(Uri location) {
    final path = SymphonyRoutePaths.normalizePath(location.path);
    if (paths.isSplash(path) || paths.isLogin(path)) {
      return redirectTargetOf(location);
    }
    return sanitizeTarget(locationOf(location));
  }

  /// Destination of a signed-in user leaving the splash or a guest-only
  /// route: the remembered location unless it is guest-only, else home.
  String _signedInTarget(String? from) {
    if (from != null && !paths.isGuestOnly(_pathOf(from))) return from;
    return paths.home;
  }

  /// Whether [location] is the bare home route. The default post-login
  /// destination is home, so remembering it would only clutter the URL.
  bool _isPlainHome(String? location) {
    if (location == null) return false;
    final uri = Uri.tryParse(location);
    return uri != null &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        _isSamePath(location, paths.home);
  }

  bool _isSamePath(String location, String path) =>
      SymphonyRoutePaths.normalizePath(_pathOf(location)).toLowerCase() ==
      SymphonyRoutePaths.normalizePath(path).toLowerCase();

  static String _pathOf(String location) =>
      Uri.tryParse(location)?.path ?? location;

  static bool _hasForbiddenCharacter(String value,
      {required bool rejectSpace}) {
    for (final unit in value.codeUnits) {
      if (unit < 0x20 || unit == 0x7F || unit == 0x5C) return true;
      if (rejectSpace && unit == 0x20) return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is SymphonyRedirectResolver &&
      other.paths == paths &&
      setEquals(other.publicPaths, publicPaths);

  @override
  int get hashCode => Object.hash(paths, Object.hashAllUnordered(publicPaths));

  @override
  String toString() =>
      'SymphonyRedirectResolver(paths: $paths, publicPaths: $publicPaths)';
}
