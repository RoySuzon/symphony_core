import 'package:flutter/foundation.dart';

import '../../../core/access/access_context.dart';
import '../../../core/access/auth_status.dart';
import '../../../core/error/failure.dart';
import 'entities/auth_session.dart';
import 'entities/auth_user.dart';

/// Global authentication state.
///
/// Deliberately small (three cases) because routing reacts to it. Progress of
/// individual operations (login in progress, form errors...) is reported by
/// the futures returned from `AuthController`.
@immutable
sealed class AuthState {
  const AuthState();

  /// Initial state while the persisted session is being restored.
  const factory AuthState.unknown() = AuthUnknown;

  /// A valid session exists.
  const factory AuthState.authenticated(AuthSession session) =
      AuthAuthenticated;

  /// No session. [failure] explains why the previous session ended, if any
  /// (for example an expired refresh token).
  const factory AuthState.unauthenticated({Failure? failure}) =
      AuthUnauthenticated;

  /// Coarse status of this state.
  AuthStatus get status;

  /// The current session, if authenticated.
  AuthSession? get session => null;

  /// The current user, if authenticated and known.
  AuthUser? get user => session?.user;

  /// Whether a session exists.
  bool get isAuthenticated => status == AuthStatus.authenticated;

  /// Access snapshot used by guards and menus.
  AccessContext get accessContext => switch (status) {
    AuthStatus.unknown => AccessContext.unknown,
    AuthStatus.unauthenticated => AccessContext.unauthenticated,
    AuthStatus.authenticated =>
      session?.toAccessContext() ??
          const AccessContext(status: AuthStatus.authenticated),
  };
}

/// The persisted session has not been restored yet.
final class AuthUnknown extends AuthState {
  /// Creates the unknown state.
  const AuthUnknown();

  @override
  AuthStatus get status => AuthStatus.unknown;

  @override
  bool operator ==(Object other) => other is AuthUnknown;

  @override
  int get hashCode => (AuthUnknown).hashCode;

  @override
  String toString() => 'AuthState.unknown()';
}

/// A valid session exists.
final class AuthAuthenticated extends AuthState {
  /// Creates the authenticated state for [session].
  const AuthAuthenticated(this.authSession);

  /// The active session.
  final AuthSession authSession;

  @override
  AuthSession get session => authSession;

  @override
  AuthStatus get status => AuthStatus.authenticated;

  @override
  bool operator ==(Object other) =>
      other is AuthAuthenticated && other.authSession == authSession;

  @override
  int get hashCode => authSession.hashCode;

  @override
  String toString() => 'AuthState.authenticated(${authSession.user})';
}

/// No session exists.
final class AuthUnauthenticated extends AuthState {
  /// Creates the unauthenticated state.
  const AuthUnauthenticated({this.failure});

  /// Why the previous session ended, if known.
  final Failure? failure;

  @override
  AuthStatus get status => AuthStatus.unauthenticated;

  @override
  bool operator ==(Object other) =>
      other is AuthUnauthenticated && other.failure == failure;

  @override
  int get hashCode => Object.hash(AuthUnauthenticated, failure);

  @override
  String toString() => 'AuthState.unauthenticated(failure: $failure)';
}
