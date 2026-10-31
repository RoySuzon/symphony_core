import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/error/failure.dart';
import '../../domain/adapters/auth_adapter.dart';
import '../../domain/entities/auth_credentials.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/entities/auth_user.dart';

/// An account known to an [InMemoryAuthAdapter].
@immutable
class InMemoryAccount {
  /// Creates an account signing in with [identifier] and [password].
  const InMemoryAccount({
    required this.identifier,
    required this.password,
    required this.user,
  });

  /// Value of the identifier field (e-mail, username, phone...).
  final String identifier;

  /// Plain text password (demo data only).
  final String password;

  /// Profile returned after sign-in. Its roles and permissions drive route
  /// guards and dashboard visibility.
  final AuthUser user;

  /// Returns a copy with the given fields replaced.
  InMemoryAccount copyWith({
    String? identifier,
    String? password,
    AuthUser? user,
  }) {
    return InMemoryAccount(
      identifier: identifier ?? this.identifier,
      password: password ?? this.password,
      user: user ?? this.user,
    );
  }

  /// Never prints the password.
  @override
  String toString() => 'InMemoryAccount(identifier: $identifier, user: $user)';
}

/// Operations of an [InMemoryAuthAdapter], used for failure injection.
enum InMemoryAuthOperation {
  /// [InMemoryAuthAdapter.login].
  login,

  /// [InMemoryAuthAdapter.refresh].
  refresh,

  /// [InMemoryAuthAdapter.logout].
  logout,

  /// [InMemoryAuthAdapter.fetchCurrentUser].
  fetchCurrentUser,

  /// [InMemoryAuthAdapter.validateSession].
  validateSession,

  /// [InMemoryAuthAdapter.register].
  register,

  /// [InMemoryAuthAdapter.requestPasswordReset].
  requestPasswordReset,

  /// [InMemoryAuthAdapter.confirmPasswordReset].
  confirmPasswordReset,
}

/// A self-contained, in-memory authentication backend for demos, prototypes,
/// widget tests and the example app.
///
/// **Not for production**: passwords are kept in plain text and the issued
/// tokens are unsigned. Use `RestAuthAdapter` or a custom `AuthAdapter` for a
/// real backend.
///
/// Features: sign-in against [accounts], expiring access tokens, rotating
/// refresh tokens, sign-out (token revocation), registration, password
/// recovery with generated reset codes, simulated latency and failure
/// injection. Tokens are self-describing, so a session persisted by the app
/// can be restored by a new adapter instance after a restart (as long as the
/// account still exists).
///
/// ```dart
/// final adapter = InMemoryAuthAdapter(
///   accounts: const [
///     InMemoryAccount(
///       identifier: 'admin@example.com',
///       password: 'secret123',
///       user: AuthUser(id: '1', displayName: 'Ada', roles: {'admin'}),
///     ),
///   ],
///   latency: const Duration(milliseconds: 400),
///   onResetCodeIssued: (identifier, code) => debugPrint('Code: $code'),
/// );
/// ```
class InMemoryAuthAdapter extends AuthAdapter {
  /// Creates the adapter.
  InMemoryAuthAdapter({
    List<InMemoryAccount> accounts = const <InMemoryAccount>[],
    this.identifierField = 'email',
    this.passwordField = 'password',
    this.nameField = 'name',
    this.codeField = 'code',
    this.caseSensitiveIdentifiers = false,
    this.latency = Duration.zero,
    this.tokenLifetime = const Duration(hours: 1),
    this.refreshTokenLifetime = const Duration(days: 30),
    this.refreshEnabled = true,
    this.registrationEnabled = true,
    this.passwordRecoveryEnabled = true,
    this.signInAfterRegistration = true,
    this.registeredUserRoles = const <String>{'user'},
    this.registeredUserPermissions = const <String>{},
    this.onResetCodeIssued,
    this.failureInjector,
    this.sessionValidator,
    this.invalidCredentialsMessage = 'Invalid e-mail or password.',
    this.missingFieldMessage = 'This field is required.',
    this.duplicateAccountMessage =
        'An account with this identifier already exists.',
    this.invalidResetCodeMessage = 'The code is invalid or has expired.',
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random() {
    for (final account in accounts) {
      _accounts[_normalize(account.identifier)] = account;
    }
  }

  /// Credentials field holding the identifier (e-mail, username...).
  final String identifierField;

  /// Credentials field holding the password (also the new password when
  /// confirming a password reset).
  final String passwordField;

  /// Optional registration field holding the display name.
  final String nameField;

  /// Credentials field holding the password reset code.
  final String codeField;

  /// Whether identifiers are compared case-sensitively.
  final bool caseSensitiveIdentifiers;

  /// Simulated network latency applied to every operation.
  final Duration latency;

  /// Lifetime of issued access tokens.
  final Duration tokenLifetime;

  /// Lifetime of issued refresh tokens.
  final Duration refreshTokenLifetime;

  /// Whether refresh tokens are issued and accepted.
  final bool refreshEnabled;

  /// Whether [register] is available.
  final bool registrationEnabled;

  /// Whether password recovery is available.
  final bool passwordRecoveryEnabled;

  /// Whether [register] signs the new user in (returns a session).
  final bool signInAfterRegistration;

  /// Roles granted to registered users.
  final Set<String> registeredUserRoles;

  /// Permissions granted to registered users.
  final Set<String> registeredUserPermissions;

  /// Called with the identifier and the generated code whenever a password
  /// reset is requested (the "e-mail" of this fake backend).
  final void Function(String identifier, String code)? onResetCodeIssued;

  /// Returns a failure to throw for an operation (or `null` to proceed).
  /// Useful to demonstrate error handling: offline mode, server errors...
  final Failure? Function(InMemoryAuthOperation operation)? failureInjector;

  /// Project specific business rules, see [AuthAdapter.validateSession].
  final FutureOr<void> Function(AuthSession session)? sessionValidator;

  /// Message of the [AuthFailure] thrown for wrong credentials.
  final String invalidCredentialsMessage;

  /// Message reported for missing fields.
  final String missingFieldMessage;

  /// Message reported when registering an existing identifier.
  final String duplicateAccountMessage;

  /// Message reported for a wrong password reset code.
  final String invalidResetCodeMessage;

  final DateTime Function() _clock;
  final Random _random;
  final Map<String, InMemoryAccount> _accounts = <String, InMemoryAccount>{};
  final Map<String, String> _resetCodes = <String, String>{};
  final Set<String> _revokedTokenIds = <String>{};
  int _generation = 0;
  int _sequence = 0;
  String? _lastResetCode;

  static const String _tokenPrefix = 'symphony-demo';

  /// Snapshot of the known accounts (including registered ones).
  List<InMemoryAccount> get accounts =>
      List<InMemoryAccount>.unmodifiable(_accounts.values);

  /// The most recently issued password reset code.
  String? get lastResetCode => _lastResetCode;

  /// The pending password reset code of [identifier], if any.
  String? resetCodeFor(String identifier) =>
      _resetCodes[_normalize(identifier)];

  /// Adds (or replaces) an account.
  void addAccount(InMemoryAccount account) {
    _accounts[_normalize(account.identifier)] = account;
  }

  /// Invalidates every session issued so far (simulates a server-side
  /// sign-out, a password change on another device...). The next refresh or
  /// user lookup fails with [UnauthorizedFailure].
  void revokeAllSessions() => _generation++;

  @override
  bool get supportsRegistration => registrationEnabled;

  @override
  bool get supportsPasswordRecovery => passwordRecoveryEnabled;

  @override
  Future<AuthSession> login(AuthCredentials credentials) async {
    await _simulate(InMemoryAuthOperation.login);
    final identifier = credentials[identifierField]?.trim() ?? '';
    final password = credentials[passwordField] ?? '';
    _requireFields(<String, String>{
      identifierField: identifier,
      passwordField: password,
    });
    final account = _accounts[_normalize(identifier)];
    if (account == null || account.password != password) {
      throw AuthFailure(
        invalidCredentialsMessage,
        code: 'invalid_credentials',
        statusCode: 401,
      );
    }
    return _issueSession(account);
  }

  @override
  Future<AuthTokens> refresh(AuthTokens current) async {
    await _simulate(InMemoryAuthOperation.refresh);
    final refreshToken = current.refreshToken;
    if (!refreshEnabled || refreshToken == null) {
      throw const UnauthorizedFailure();
    }
    final claims = _verify(refreshToken, type: 'refresh');
    final account = _accountOf(claims);
    _revokedTokenIds.add('${claims['jti']}');
    return _issueTokens(account);
  }

  @override
  Future<void> logout(AuthSession session) async {
    await _simulate(InMemoryAuthOperation.logout);
    for (final token in <String?>[
      session.tokens.accessToken,
      session.tokens.refreshToken,
    ]) {
      final claims = token == null ? null : _decode(token);
      if (claims != null) _revokedTokenIds.add('${claims['jti']}');
    }
  }

  @override
  Future<AuthUser?> fetchCurrentUser(AuthSession session) async {
    await _simulate(InMemoryAuthOperation.fetchCurrentUser);
    final claims = _verify(session.tokens.accessToken, type: 'access');
    return _accountOf(claims).user;
  }

  @override
  Future<void> validateSession(AuthSession session) async {
    await _simulate(InMemoryAuthOperation.validateSession);
    final validator = sessionValidator;
    if (validator != null) await validator(session);
  }

  @override
  Future<AuthSession?> register(AuthCredentials data) async {
    if (!registrationEnabled) return super.register(data);
    await _simulate(InMemoryAuthOperation.register);
    final identifier = data[identifierField]?.trim() ?? '';
    final password = data[passwordField] ?? '';
    _requireFields(<String, String>{
      identifierField: identifier,
      passwordField: password,
    });
    final key = _normalize(identifier);
    if (_accounts.containsKey(key)) {
      throw ValidationFailure(
        duplicateAccountMessage,
        code: 'account_exists',
        statusCode: 422,
        fieldErrors: <String, List<String>>{
          identifierField: <String>[duplicateAccountMessage],
        },
      );
    }
    final name = data[nameField]?.trim();
    final isEmail = identifier.contains('@');
    final account = InMemoryAccount(
      identifier: identifier,
      password: password,
      user: AuthUser(
        id: 'user-${++_sequence}-${_randomHex(4)}',
        displayName: name == null || name.isEmpty ? identifier : name,
        email: isEmail ? identifier : null,
        username: isEmail ? null : identifier,
        roles: registeredUserRoles,
        permissions: registeredUserPermissions,
      ),
    );
    _accounts[key] = account;
    return signInAfterRegistration ? _issueSession(account) : null;
  }

  @override
  Future<void> requestPasswordReset(AuthCredentials data) async {
    if (!passwordRecoveryEnabled) return super.requestPasswordReset(data);
    await _simulate(InMemoryAuthOperation.requestPasswordReset);
    final identifier = data[identifierField]?.trim() ?? '';
    _requireFields(<String, String>{identifierField: identifier});
    final account = _accounts[_normalize(identifier)];
    // Unknown identifiers succeed silently, like real backends do, so the
    // endpoint cannot be used to discover accounts.
    if (account == null) return;
    final code =
        List<String>.generate(6, (_) => '${_random.nextInt(10)}').join();
    _resetCodes[_normalize(identifier)] = code;
    _lastResetCode = code;
    onResetCodeIssued?.call(account.identifier, code);
  }

  @override
  Future<void> confirmPasswordReset(AuthCredentials data) async {
    if (!passwordRecoveryEnabled) return super.confirmPasswordReset(data);
    await _simulate(InMemoryAuthOperation.confirmPasswordReset);
    final identifier = data[identifierField]?.trim() ?? '';
    final code = data[codeField]?.trim() ?? '';
    final password = data[passwordField] ?? '';
    _requireFields(<String, String>{
      identifierField: identifier,
      codeField: code,
      passwordField: password,
    });
    final key = _normalize(identifier);
    final account = _accounts[key];
    if (account == null || _resetCodes[key] != code) {
      throw ValidationFailure(
        invalidResetCodeMessage,
        code: 'invalid_reset_code',
        statusCode: 422,
        fieldErrors: <String, List<String>>{
          codeField: <String>[invalidResetCodeMessage],
        },
      );
    }
    _resetCodes.remove(key);
    _accounts[key] = account.copyWith(password: password);
  }

  Future<void> _simulate(InMemoryAuthOperation operation) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final failure = failureInjector?.call(operation);
    if (failure != null) throw failure;
  }

  void _requireFields(Map<String, String> values) {
    final errors = <String, List<String>>{
      for (final entry in values.entries)
        if (entry.value.isEmpty) entry.key: <String>[missingFieldMessage],
    };
    if (errors.isNotEmpty) {
      throw ValidationFailure(
        missingFieldMessage,
        code: 'missing_fields',
        statusCode: 422,
        fieldErrors: errors,
      );
    }
  }

  String _normalize(String identifier) {
    final trimmed = identifier.trim();
    return caseSensitiveIdentifiers ? trimmed : trimmed.toLowerCase();
  }

  AuthSession _issueSession(InMemoryAccount account) =>
      AuthSession(tokens: _issueTokens(account), user: account.user);

  AuthTokens _issueTokens(InMemoryAccount account) {
    final now = _clock();
    final expiresAt = now.add(tokenLifetime);
    return AuthTokens(
      accessToken: _encode('access', account.identifier, expiresAt),
      refreshToken:
          refreshEnabled
              ? _encode(
                'refresh',
                account.identifier,
                now.add(refreshTokenLifetime),
              )
              : null,
      tokenType: 'Bearer',
      expiresAt: expiresAt,
    );
  }

  String _encode(String type, String identifier, DateTime expiresAt) {
    final claims = <String, Object?>{
      'typ': type,
      'sub': identifier,
      'exp': expiresAt.millisecondsSinceEpoch,
      'gen': _generation,
      'jti': '${++_sequence}-${_randomHex(8)}',
    };
    final payload = base64Url.encode(utf8.encode(jsonEncode(claims)));
    return '$_tokenPrefix.$type.$payload';
  }

  Map<String, Object?>? _decode(String token) {
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != _tokenPrefix) return null;
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(parts[2])));
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  /// Returns the claims of a valid token of [type], or throws
  /// [UnauthorizedFailure].
  Map<String, Object?> _verify(String token, {required String type}) {
    final claims = _decode(token);
    final expiry = claims?['exp'];
    final generation = claims?['gen'];
    if (claims == null ||
        claims['typ'] != type ||
        expiry is! int ||
        generation is! int ||
        generation < _generation ||
        _revokedTokenIds.contains('${claims['jti']}') ||
        !_clock().isBefore(DateTime.fromMillisecondsSinceEpoch(expiry))) {
      throw const UnauthorizedFailure();
    }
    return claims;
  }

  InMemoryAccount _accountOf(Map<String, Object?> claims) {
    final account = _accounts[_normalize('${claims['sub']}')];
    if (account == null) throw const UnauthorizedFailure();
    return account;
  }

  String _randomHex(int bytes) =>
      List<String>.generate(
        bytes,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
}
