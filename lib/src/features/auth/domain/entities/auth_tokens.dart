import 'package:flutter/foundation.dart';

/// Credentials returned by the backend after a successful sign-in or refresh.
@immutable
class AuthTokens {
  /// Creates a token set.
  const AuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.tokenType,
    this.expiresAt,
    this.extra = const <String, Object?>{},
  });

  /// Restores tokens serialized with [toJson].
  ///
  /// Throws a [FormatException] when `accessToken` is missing.
  factory AuthTokens.fromJson(Map<String, Object?> json) {
    final accessToken = json['accessToken'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const FormatException('AuthTokens.accessToken is missing');
    }
    final expiresAt = json['expiresAt'];
    final extra = json['extra'];
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: json['refreshToken'] as String?,
      tokenType: json['tokenType'] as String?,
      expiresAt: expiresAt is String ? DateTime.tryParse(expiresAt) : null,
      extra: extra is Map
          ? Map<String, Object?>.from(extra)
          : const <String, Object?>{},
    );
  }

  /// Token sent with authenticated requests.
  final String accessToken;

  /// Token used to obtain a new [accessToken], if the backend issues one.
  final String? refreshToken;

  /// Token type reported by the backend (e.g. `Bearer`).
  final String? tokenType;

  /// Expiry of [accessToken], when known.
  final DateTime? expiresAt;

  /// Additional values returned by the backend (id token, scopes...).
  final Map<String, Object?> extra;

  /// Whether a refresh token is available.
  bool get canRefresh => refreshToken != null && refreshToken!.isNotEmpty;

  /// Whether the access token is expired (or expires within [leeway]).
  ///
  /// Returns `false` when [expiresAt] is unknown.
  bool isExpired({Duration leeway = Duration.zero, DateTime? now}) {
    final expiry = expiresAt;
    if (expiry == null) return false;
    final current = now ?? DateTime.now();
    return !current.add(leeway).isBefore(expiry);
  }

  /// Serializes the tokens (for secure storage only).
  Map<String, Object?> toJson() => <String, Object?>{
        'accessToken': accessToken,
        if (refreshToken != null) 'refreshToken': refreshToken,
        if (tokenType != null) 'tokenType': tokenType,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (extra.isNotEmpty) 'extra': extra,
      };

  /// Returns a copy with the given fields replaced.
  AuthTokens copyWith({
    String? accessToken,
    String? refreshToken,
    String? tokenType,
    DateTime? expiresAt,
    Map<String, Object?>? extra,
  }) {
    return AuthTokens(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenType: tokenType ?? this.tokenType,
      expiresAt: expiresAt ?? this.expiresAt,
      extra: extra ?? this.extra,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AuthTokens &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.tokenType == tokenType &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode =>
      Object.hash(accessToken, refreshToken, tokenType, expiresAt);

  /// Never prints the token values.
  @override
  String toString() => 'AuthTokens(accessToken: ***, '
      'refreshToken: ${refreshToken == null ? 'null' : '***'}, '
      'expiresAt: $expiresAt)';
}
