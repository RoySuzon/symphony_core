import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

/// Authentication endpoints of the demo backend.
///
/// Every project declares its own paths — `symphony_core` has no defaults.
const RestAuthEndpoints exampleAuthEndpoints = RestAuthEndpoints(
  login: '/auth/login',
  refresh: '/auth/token/refresh',
  logout: '/auth/logout',
  currentUser: '/auth/me',
  register: '/auth/register',
  requestPasswordReset: '/auth/password/forgot',
  confirmPasswordReset: '/auth/password/reset',
);

/// Where the demo backend puts tokens and user fields.
///
/// Its responses use a non-default shape on purpose:
///
/// ```json
/// {
///   "status": "ok",
///   "result": {
///     "credentials": {"jwt": "…", "renewal_token": "…", "kind": "Bearer",
///                     "ttl": 30},
///     "account": {
///       "uid": "usr_admin",
///       "profile": {"given_name": "Alice", "family_name": "Admin"},
///       "contact": {"mail": "admin@example.com"},
///       "groups": [{"slug": "admin", "label": "Admin"}],
///       "grants": "audit.view orders.read …"
///     }
///   }
/// }
/// ```
const AuthResponseMapping exampleAuthResponseMapping = AuthResponseMapping(
  accessToken: <String>['result.credentials.jwt'],
  refreshToken: <String>['result.credentials.renewal_token'],
  tokenType: <String>['result.credentials.kind'],
  expiresIn: <String>['result.credentials.ttl'],
  user: <String>['result.account'],
  currentUser: <String>['result.account'],
  userId: <String>['uid'],
  userFirstName: <String>['profile.given_name'],
  userLastName: <String>['profile.family_name'],
  userEmail: <String>['contact.mail'],
  userAvatarUrl: <String>['profile.avatar'],
  // Objects named by their `slug`: [{"slug": "admin"}].
  userRoles: <String>['groups'],
  // OAuth style scopes: "orders.read reports.view".
  userPermissions: <String>['grants'],
  entryNameKeys: <String>['slug'],
);

/// Builds the application's [AuthAdapter]; passed to `SymphonyCore` as
/// `authAdapterBuilder`.
///
/// A [RestAuthAdapter] configured for the demo backend: its endpoints, its
/// request bodies (`login`/`secret` instead of `email`/`password`...), its
/// response format and a project specific business rule. Every request goes
/// through the central `ApiClient`, so authentication calls show up in the
/// API inspector like any other call.
AuthAdapter createExampleAuthAdapter(Ref ref) {
  return RestAuthAdapter(
    apiClient: ref.watch(apiClientProvider),
    endpoints: exampleAuthEndpoints,
    mapping: exampleAuthResponseMapping,
    loginBody:
        (credentials) => <String, Object?>{
          'login': credentials['email'],
          'secret': credentials['password'],
          'client': 'symphony-example',
        },
    refreshBody:
        (tokens) => <String, Object?>{'renewal_token': tokens.refreshToken},
    logoutBody:
        (session) => <String, Object?>{
          'renewal_token': session.tokens.refreshToken,
        },
    registerBody:
        (data) => <String, Object?>{
          'full_name': data['name'],
          'email': data['email'],
          'password': data['password'],
        },
    requestPasswordResetBody:
        (data) => <String, Object?>{'email': data['email']},
    confirmPasswordResetBody:
        (data) => <String, Object?>{
          'email': data['email'],
          'code': data['code'],
          'new_password': data['password'],
        },
    sessionValidator: requireVerifiedEmail,
  );
}

/// Business rule of this project, run after every sign-in and session
/// restoration: accounts must have a verified e-mail address.
///
/// Sign in as `unverified@example.com` to see the rule reject a session that
/// the backend accepted.
void requireVerifiedEmail(AuthSession session) {
  if (session.user?.data['email_verified'] == false) {
    throw const AuthFailure(
      'Please verify your e-mail address before signing in.',
      code: 'email_not_verified',
    );
  }
}
