import 'package:flutter/foundation.dart';

import '../../../../core/access/access_context.dart';
import '../../../../core/access/auth_status.dart';
import 'auth_tokens.dart';
import 'auth_user.dart';

/// An authenticated session: tokens plus the (optional) user profile.
@immutable
class AuthSession {
  /// Creates a session.
  const AuthSession({required this.tokens, this.user});

  /// Credentials of the session.
  final AuthTokens tokens;

  /// Profile of the signed-in user, when the backend returns one.
  final AuthUser? user;

  /// Builds the [AccessContext] used by guards and menus.
  AccessContext toAccessContext() => AccessContext(
    status: AuthStatus.authenticated,
    roles: user?.roles ?? const <String>{},
    permissions: user?.permissions ?? const <String>{},
    attributes: user?.data ?? const <String, Object?>{},
  );

  /// Returns a copy with the given fields replaced.
  AuthSession copyWith({AuthTokens? tokens, AuthUser? user}) =>
      AuthSession(tokens: tokens ?? this.tokens, user: user ?? this.user);

  @override
  bool operator ==(Object other) =>
      other is AuthSession && other.tokens == tokens && other.user == user;

  @override
  int get hashCode => Object.hash(tokens, user);

  @override
  String toString() => 'AuthSession(user: $user, tokens: $tokens)';
}
