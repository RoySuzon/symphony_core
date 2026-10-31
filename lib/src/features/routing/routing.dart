/// Routing: GoRouter integration with authentication, role and permission
/// guards.
///
/// * [SymphonyRouter] builds a `GoRouter` wired to the authentication state
///   (splash while the session is restored, sign-in redirects returning to
///   the requested page, guest-only pages, error page).
/// * [GuardedRoute] protects a route and its nested routes with an
///   `AccessRequirement` (authentication, roles, permissions, predicate).
/// * [GuestRoute] reserves a route to signed-out users (login, register...).
/// * [AccessGate] shows or hides UI depending on the user's access.
/// * [SymphonyRedirectResolver] holds the pure, unit-testable redirect rules
///   configured by [SymphonyRoutePaths].
library;

export 'domain/redirect_logic.dart';
export 'domain/symphony_route_paths.dart';
export 'presentation/guarded_route.dart';
export 'presentation/symphony_router.dart';
export 'presentation/widgets/access_gate.dart';
export 'presentation/widgets/symphony_route_error_screen.dart';
export 'presentation/widgets/symphony_unauthorized_screen.dart';
