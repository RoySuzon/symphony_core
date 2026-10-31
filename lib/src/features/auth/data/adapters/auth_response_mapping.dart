import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/entities/auth_user.dart';

/// Describes where token and user fields live in the JSON responses of an
/// authentication backend. Used by `RestAuthAdapter`.
///
/// Every field is a list of candidate *paths*; the first path that resolves to
/// a usable value wins. A path is a dot separated list of map keys
/// (`data.user.id`), numeric segments index into lists (`items.0.token`) and
/// the empty string `''` designates the whole document.
///
/// The defaults understand the most common response shapes, for example:
///
/// ```json
/// {"access_token": "…", "refresh_token": "…", "expires_in": 3600}
/// {"accessToken": "…", "user": {"id": 7, "roles": ["admin"]}}
/// {"data": {"token": "…", "user": {"id": 7, "role": "editor"}}}
/// {"access": "…", "refresh": "…"}
/// ```
///
/// Override only what differs. The `default…Paths` constants make it easy to
/// extend a default instead of replacing it:
///
/// ```dart
/// const mapping = AuthResponseMapping(
///   accessToken: ['result.jwt'],
///   user: ['result.account'],
///   userRoles: ['groups', ...AuthResponseMapping.defaultUserRolesPaths],
/// );
/// ```
@immutable
class AuthResponseMapping {
  /// Creates a mapping. Every parameter defaults to the matching
  /// `default…Paths` constant.
  const AuthResponseMapping({
    this.accessToken = defaultAccessTokenPaths,
    this.refreshToken = defaultRefreshTokenPaths,
    this.tokenType = defaultTokenTypePaths,
    this.expiresIn = defaultExpiresInPaths,
    this.expiresAt = defaultExpiresAtPaths,
    this.tokenExtras = const <String>[],
    this.useJwtExpiry = true,
    this.user = defaultUserPaths,
    this.currentUser = defaultCurrentUserPaths,
    this.userId = defaultUserIdPaths,
    this.userDisplayName = defaultUserDisplayNamePaths,
    this.userFirstName = defaultUserFirstNamePaths,
    this.userLastName = defaultUserLastNamePaths,
    this.userEmail = defaultUserEmailPaths,
    this.userUsername = defaultUserUsernamePaths,
    this.userAvatarUrl = defaultUserAvatarUrlPaths,
    this.userRoles = defaultUserRolesPaths,
    this.userPermissions = defaultUserPermissionsPaths,
    this.entryNameKeys = defaultEntryNameKeys,
  });

  /// Default candidates for [accessToken].
  static const List<String> defaultAccessTokenPaths = <String>[
    'access_token',
    'accessToken',
    'access',
    'token',
    'jwt',
    'data.access_token',
    'data.accessToken',
    'data.access',
    'data.token',
    'tokens.access_token',
    'tokens.accessToken',
    'tokens.access',
    'data.tokens.access_token',
    'data.tokens.accessToken',
    'data.tokens.access',
  ];

  /// Default candidates for [refreshToken].
  static const List<String> defaultRefreshTokenPaths = <String>[
    'refresh_token',
    'refreshToken',
    'refresh',
    'data.refresh_token',
    'data.refreshToken',
    'data.refresh',
    'tokens.refresh_token',
    'tokens.refreshToken',
    'tokens.refresh',
    'data.tokens.refresh_token',
    'data.tokens.refreshToken',
    'data.tokens.refresh',
  ];

  /// Default candidates for [tokenType].
  static const List<String> defaultTokenTypePaths = <String>[
    'token_type',
    'tokenType',
    'data.token_type',
    'data.tokenType',
    'tokens.token_type',
    'tokens.tokenType',
  ];

  /// Default candidates for [expiresIn].
  static const List<String> defaultExpiresInPaths = <String>[
    'expires_in',
    'expiresIn',
    'data.expires_in',
    'data.expiresIn',
    'tokens.expires_in',
    'tokens.expiresIn',
  ];

  /// Default candidates for [expiresAt].
  static const List<String> defaultExpiresAtPaths = <String>[
    'expires_at',
    'expiresAt',
    'expiry',
    'data.expires_at',
    'data.expiresAt',
    'tokens.expires_at',
    'tokens.expiresAt',
  ];

  /// Default candidates for [user].
  static const List<String> defaultUserPaths = <String>[
    'user',
    'data.user',
    'profile',
    'data.profile',
    'account',
    'data.account',
  ];

  /// Default candidates for [currentUser].
  static const List<String> defaultCurrentUserPaths = <String>[
    'data.user',
    'user',
    'data.profile',
    'profile',
    'data',
    '',
  ];

  /// Default candidates for [userId].
  static const List<String> defaultUserIdPaths = <String>[
    'id',
    'user_id',
    'userId',
    'uid',
    'uuid',
    'sub',
    '_id',
  ];

  /// Default candidates for [userDisplayName].
  static const List<String> defaultUserDisplayNamePaths = <String>[
    'display_name',
    'displayName',
    'name',
    'full_name',
    'fullName',
  ];

  /// Default candidates for [userFirstName].
  static const List<String> defaultUserFirstNamePaths = <String>[
    'first_name',
    'firstName',
    'given_name',
    'givenName',
  ];

  /// Default candidates for [userLastName].
  static const List<String> defaultUserLastNamePaths = <String>[
    'last_name',
    'lastName',
    'family_name',
    'familyName',
  ];

  /// Default candidates for [userEmail].
  static const List<String> defaultUserEmailPaths = <String>[
    'email',
    'email_address',
    'emailAddress',
    'mail',
  ];

  /// Default candidates for [userUsername].
  static const List<String> defaultUserUsernamePaths = <String>[
    'username',
    'user_name',
    'userName',
    'login',
    'preferred_username',
  ];

  /// Default candidates for [userAvatarUrl].
  static const List<String> defaultUserAvatarUrlPaths = <String>[
    'avatar_url',
    'avatarUrl',
    'avatar',
    'picture',
    'photo_url',
    'photoUrl',
    'image_url',
    'imageUrl',
    'image',
  ];

  /// Default candidates for [userRoles].
  static const List<String> defaultUserRolesPaths = <String>['roles', 'role'];

  /// Default candidates for [userPermissions].
  static const List<String> defaultUserPermissionsPaths = <String>[
    'permissions',
    'scopes',
    'scope',
  ];

  /// Default value of [entryNameKeys].
  static const List<String> defaultEntryNameKeys = <String>[
    'name',
    'slug',
    'key',
    'code',
    'id',
  ];

  /// Paths of the access token (a non-empty string) in sign-in and refresh
  /// responses.
  final List<String> accessToken;

  /// Paths of the refresh token.
  final List<String> refreshToken;

  /// Paths of the token type (for example `Bearer`).
  final List<String> tokenType;

  /// Paths of the access token lifetime in seconds (number or numeric
  /// string). Converted into an absolute expiry using the adapter clock.
  final List<String> expiresIn;

  /// Paths of the absolute access token expiry: an ISO-8601 string or a Unix
  /// epoch in seconds or milliseconds. Used when no [expiresIn] is found.
  final List<String> expiresAt;

  /// Paths copied into `AuthTokens.extra` (for example `id_token`). Each
  /// value is stored under its path.
  final List<String> tokenExtras;

  /// Whether the `exp` claim of a JWT access token is used as expiry when
  /// the response contains neither [expiresIn] nor [expiresAt].
  final bool useJwtExpiry;

  /// Paths of the user object inside sign-in and registration responses.
  final List<String> user;

  /// Paths of the user object inside current-user responses. The default
  /// ends with `''`, so a bare user object is understood too.
  final List<String> currentUser;

  /// Paths of the user id, relative to the user object. Falls back to the
  /// e-mail, then the username, when none is found.
  final List<String> userId;

  /// Paths of the display name, relative to the user object.
  final List<String> userDisplayName;

  /// Paths of the first name, combined with [userLastName] when no
  /// [userDisplayName] is found.
  final List<String> userFirstName;

  /// Paths of the last name. See [userFirstName].
  final List<String> userLastName;

  /// Paths of the e-mail address, relative to the user object.
  final List<String> userEmail;

  /// Paths of the username, relative to the user object.
  final List<String> userUsername;

  /// Paths of the avatar URL, relative to the user object.
  final List<String> userAvatarUrl;

  /// Paths of the roles, relative to the user object.
  ///
  /// The value may be a string (`"admin"` or `"admin,editor"`), a list of
  /// strings, a list of objects (named by [entryNameKeys]) or a map of
  /// boolean flags (`{"admin": true}`).
  final List<String> userRoles;

  /// Paths of the permissions, relative to the user object. Accepts the same
  /// shapes as [userRoles]; strings are also split on whitespace, so OAuth
  /// scopes (`"orders.read orders.write"`) work out of the box.
  final List<String> userPermissions;

  /// Keys used to name role / permission entries that are objects, for
  /// example `{"name": "admin"}`.
  final List<String> entryNameKeys;

  /// Returns the first non-null value found at one of [paths] inside [data].
  ///
  /// [data] may be a decoded JSON value or a JSON encoded string.
  Object? read(Object? data, List<String> paths) =>
      _firstValue(_decodeJson(data), paths, _identity);

  /// Reads the tokens of a sign-in or refresh response.
  ///
  /// Returns `null` when no access token is present. [now] (defaults to the
  /// current time) turns relative lifetimes into an absolute expiry.
  AuthTokens? readTokens(Object? data, {DateTime? now}) {
    final root = _decodeJson(data);
    final access = _firstValue(root, accessToken, _text);
    if (access == null) return null;
    final extras = <String, Object?>{};
    for (final path in tokenExtras) {
      final value = _resolvePath(root, path);
      if (value != null) extras[path] = value;
    }
    return AuthTokens(
      accessToken: access,
      refreshToken: _firstValue(root, refreshToken, _text),
      tokenType: _firstValue(root, tokenType, _text),
      expiresAt: _readExpiry(root, now ?? DateTime.now(), access),
      extra: extras,
    );
  }

  /// Reads a complete session (tokens plus the embedded user, if any) from a
  /// sign-in or registration response. Returns `null` when no access token
  /// is present.
  AuthSession? readSession(Object? data, {DateTime? now}) {
    final root = _decodeJson(data);
    final tokens = readTokens(root, now: now);
    if (tokens == null) return null;
    return AuthSession(tokens: tokens, user: readSessionUser(root));
  }

  /// Locates the user object of a sign-in or registration response (see
  /// [user]) and maps it with [readUser].
  AuthUser? readSessionUser(Object? data) =>
      readUser(_firstValue(_decodeJson(data), user, _map));

  /// Locates the user object of a current-user response (see [currentUser])
  /// and maps it with [readUser].
  AuthUser? readCurrentUser(Object? data) =>
      readUser(_firstValue(_decodeJson(data), currentUser, _map));

  /// Maps a user object (a JSON map) into an [AuthUser].
  ///
  /// The raw map is kept in `AuthUser.data`. Returns `null` when [json] is
  /// not a map.
  AuthUser? readUser(Object? json) {
    final decoded = _decodeJson(json);
    if (decoded is! Map) return null;
    final map = <String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    };
    final email = _firstValue(map, userEmail, _text);
    final username = _firstValue(map, userUsername, _text);
    final id = _firstValue(map, userId, _scalar) ?? email ?? username ?? '';
    var displayName = _firstValue(map, userDisplayName, _text);
    if (displayName == null) {
      final parts = <String?>[
        _firstValue(map, userFirstName, _text),
        _firstValue(map, userLastName, _text),
      ].whereType<String>();
      if (parts.isNotEmpty) displayName = parts.join(' ');
    }
    return AuthUser(
      id: id,
      displayName: displayName,
      email: email,
      username: username,
      avatarUrl: _firstValue(map, userAvatarUrl, _text),
      roles: _readSet(
        _firstValue(map, userRoles, _identity),
        splitOnWhitespace: false,
      ),
      permissions: _readSet(
        _firstValue(map, userPermissions, _identity),
        splitOnWhitespace: true,
      ),
      data: Map<String, Object?>.unmodifiable(map),
    );
  }

  DateTime? _readExpiry(Object? root, DateTime now, String accessToken) {
    final lifetime = _firstValue(root, expiresIn, _number);
    if (lifetime != null) {
      return now.add(Duration(milliseconds: (lifetime * 1000).round()));
    }
    final absolute = _firstValue(root, expiresAt, _dateTime);
    if (absolute != null) return absolute;
    return useJwtExpiry ? _jwtExpiry(accessToken) : null;
  }

  Set<String> _readSet(Object? value, {required bool splitOnWhitespace}) {
    if (value == null) return const <String>{};
    if (value is String) {
      final pattern = splitOnWhitespace ? RegExp(r'[,\s]+') : RegExp(',');
      return value
          .split(pattern)
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toSet();
    }
    if (value is Iterable) {
      final result = <String>{};
      for (final item in value) {
        final name = item is Map
            ? _firstValue(item, entryNameKeys, _scalar)
            : _scalar(item);
        if (name != null) result.add(name);
      }
      return result;
    }
    if (value is Map) {
      if (value.isNotEmpty && value.values.every((v) => v is bool)) {
        return <String>{
          for (final entry in value.entries)
            if (entry.value == true) '${entry.key}',
        };
      }
      final name = _firstValue(value, entryNameKeys, _scalar);
      return name == null ? const <String>{} : <String>{name};
    }
    final single = _scalar(value);
    return single == null ? const <String>{} : <String>{single};
  }
}

// ---------------------------------------------------------------------------
// Private, dependency free dotted-path JSON reader.
// ---------------------------------------------------------------------------

/// Decodes [data] when it is a JSON object or array encoded as a string.
Object? _decodeJson(Object? data) {
  if (data is String) {
    final trimmed = data.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return jsonDecode(data);
      } on FormatException {
        return data;
      }
    }
  }
  return data;
}

/// Resolves a dotted [path] inside [root]. `''` returns [root] itself.
Object? _resolvePath(Object? root, String path) {
  if (path.isEmpty) return root;
  Object? current = root;
  for (final segment in path.split('.')) {
    if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
    if (current == null) return null;
  }
  return current;
}

/// Returns the first value at [paths] that [convert] accepts (non-null).
T? _firstValue<T>(
  Object? root,
  List<String> paths,
  T? Function(Object? value) convert,
) {
  for (final path in paths) {
    final converted = convert(_resolvePath(root, path));
    if (converted != null) return converted;
  }
  return null;
}

Object? _identity(Object? value) => value;

Map<Object?, Object?>? _map(Object? value) =>
    value is Map ? Map<Object?, Object?>.from(value) : null;

/// A non-empty, trimmed string.
String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// A non-empty string or a number, as a string.
String? _scalar(Object? value) => value is num ? '$value' : _text(value);

num? _number(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim());
  return null;
}

DateTime? _dateTime(Object? value) {
  if (value is num) return _fromEpoch(value);
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final numeric = num.tryParse(text);
    return numeric != null ? _fromEpoch(numeric) : DateTime.tryParse(text);
  }
  return null;
}

/// Unix epochs above 1e11 are milliseconds (1973+), smaller ones seconds.
DateTime _fromEpoch(num value) {
  final milliseconds =
      value.abs() >= 100000000000 ? value.round() : (value * 1000).round();
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

/// Reads the `exp` claim of a JWT without verifying it.
DateTime? _jwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3 || parts[1].isEmpty) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is Map) {
      final exp = payload['exp'];
      if (exp is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (exp * 1000).round(),
          isUtc: true,
        );
      }
    }
  } on FormatException {
    // Not a JWT.
  }
  return null;
}
