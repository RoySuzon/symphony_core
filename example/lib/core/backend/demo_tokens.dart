import 'dart:convert';

import 'demo_http.dart';

/// Claims of a verified demo token.
class DemoTokenClaims {
  /// Creates claims.
  const DemoTokenClaims({
    required this.subject,
    required this.type,
    required this.id,
    required this.sequence,
    required this.issuedAt,
    required this.expiresAt,
  });

  /// Account id (`sub`).
  final String subject;

  /// `access` or `refresh` (`typ`).
  final String type;

  /// Unique token id (`jti`).
  final String id;

  /// Issue order: tokens issued later have a higher sequence.
  final int sequence;

  /// Issue instant (second precision, like the JWT `iat` claim).
  final DateTime issuedAt;

  /// Expiry instant.
  final DateTime expiresAt;
}

/// Issues and verifies the demo backend's JWT-shaped tokens.
///
/// Tokens are self-describing (`header.payload.signature`, base64url JSON),
/// so a session persisted by the app survives an app restart although the
/// backend keeps no session table. The "signature" is a simple checksum:
/// these tokens are for demonstrations only and are **not** secure.
class DemoTokenService {
  /// Creates the service.
  DemoTokenService({
    required DateTime Function() clock,
    required this.accessTokenLifetime,
    required this.refreshTokenLifetime,
  }) : _clock = clock,
       // Monotonic across app restarts: tokens persisted by a previous run
       // always have a lower sequence than the tokens issued now.
       _sequence = clock().millisecondsSinceEpoch * 1000;

  final DateTime Function() _clock;

  /// Lifetime of access tokens (short, so refreshes are easy to observe).
  final Duration accessTokenLifetime;

  /// Lifetime of refresh tokens.
  final Duration refreshTokenLifetime;

  static const String _secret = 'symphony-demo-backend';
  static const String _access = 'access';
  static const String _refresh = 'refresh';

  int _sequence;
  int _accessTokensValidAfter = 0;
  int _refreshTokensValidAfter = 0;
  final Set<String> _revokedIds = <String>{};

  /// Issues an access token for [subject].
  String issueAccessToken(String subject) =>
      _issue(subject, _access, accessTokenLifetime);

  /// Issues a refresh token for [subject].
  String issueRefreshToken(String subject) =>
      _issue(subject, _refresh, refreshTokenLifetime);

  /// Verifies an access token. With [allowExpired], an expired (but
  /// authentic) token is accepted — used by the sign-out endpoint.
  ///
  /// Throws a `401` [DemoHttpException] when the token is invalid.
  DemoTokenClaims verifyAccessToken(String token, {bool allowExpired = false}) {
    final claims = _verify(token, _access);
    if (!allowExpired && _isExpired(claims, _accessTokensValidAfter)) {
      throw const DemoHttpException.unauthorized(
        'token_expired',
        'The access token has expired.',
      );
    }
    return claims;
  }

  /// Verifies a refresh token (expiry and revocation included).
  ///
  /// Throws a `401` [DemoHttpException] when the token cannot be used.
  DemoTokenClaims verifyRefreshToken(String token) {
    final claims = _verify(token, _refresh);
    if (_revokedIds.contains(claims.id) ||
        _isExpired(claims, _refreshTokensValidAfter)) {
      throw const DemoHttpException.unauthorized(
        'invalid_refresh_token',
        'The session has expired. Please sign in again.',
      );
    }
    return claims;
  }

  /// Prevents [claims]' token from being used again (rotation, sign-out).
  void revoke(DemoTokenClaims claims) => _revokedIds.add(claims.id);

  /// Makes every access token issued so far expired.
  void expireAccessTokens() => _accessTokensValidAfter = _sequence;

  /// Makes every refresh token issued so far unusable.
  void revokeRefreshTokens() => _refreshTokensValidAfter = _sequence;

  String _issue(String subject, String type, Duration lifetime) {
    final now = _clock().toUtc();
    final expiry = now.add(lifetime);
    _sequence++;
    final header = _encode(<String, Object?>{'alg': 'DEMO', 'typ': 'JWT'});
    final payload = _encode(<String, Object?>{
      'sub': subject,
      'typ': type,
      'jti': '$type-$_sequence-${now.microsecondsSinceEpoch}',
      'seq': _sequence,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': expiry.millisecondsSinceEpoch ~/ 1000,
      'exp_ms': expiry.millisecondsSinceEpoch,
    });
    final unsigned = '$header.$payload';
    return '$unsigned.${_sign(unsigned)}';
  }

  DemoTokenClaims _verify(String token, String expectedType) {
    const invalid = DemoHttpException.unauthorized(
      'invalid_token',
      'The token is invalid.',
    );
    final segments = token.split('.');
    if (segments.length != 3) throw invalid;
    if (_sign('${segments[0]}.${segments[1]}') != segments[2]) throw invalid;

    final Object? payload;
    try {
      payload = jsonDecode(utf8.decode(base64Url.decode(_pad(segments[1]))));
    } on FormatException {
      throw invalid;
    }
    if (payload is! Map) throw invalid;
    final subject = payload['sub'];
    final type = payload['typ'];
    final id = payload['jti'];
    final sequence = payload['seq'];
    final issuedAt = payload['iat'];
    final expiresAt = payload['exp_ms'];
    if (subject is! String ||
        type != expectedType ||
        id is! String ||
        sequence is! int ||
        issuedAt is! int ||
        expiresAt is! int) {
      throw invalid;
    }
    return DemoTokenClaims(
      subject: subject,
      type: expectedType,
      id: id,
      sequence: sequence,
      issuedAt: DateTime.fromMillisecondsSinceEpoch(
        issuedAt * 1000,
        isUtc: true,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true),
    );
  }

  /// Expired by time, or issued before the last bulk expiry (compared by
  /// issue order, so it is reliable even with a frozen test clock).
  bool _isExpired(DemoTokenClaims claims, int validAfterSequence) =>
      !_clock().isBefore(claims.expiresAt) ||
      claims.sequence <= validAfterSequence;

  static String _encode(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

  static String _pad(String value) =>
      value.padRight(value.length + (4 - value.length % 4) % 4, '=');

  /// Deterministic checksum, identical on every platform (web included).
  static String _sign(String input) {
    var first = 5381;
    var second = 52711;
    for (final unit in utf8.encode('$_secret.$input')) {
      first = ((first * 33) ^ unit) & 0x7fffffff;
      second = ((second * 31) + unit) & 0x7fffffff;
    }
    return '${first.toRadixString(36)}${second.toRadixString(36)}';
  }
}
