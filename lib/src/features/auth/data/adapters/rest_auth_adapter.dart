import 'dart:async';

import '../../../../core/error/failure.dart';
import '../../../networking/data/api_client.dart';
import '../../../networking/data/default_api_error_mapper.dart';
import '../../../networking/domain/api_request_options.dart';
import '../../../networking/domain/api_response.dart';
import '../../domain/adapters/auth_adapter.dart';
import '../../domain/entities/auth_credentials.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/entities/auth_user.dart';
import 'auth_response_mapping.dart';
import 'rest_auth_endpoints.dart';

/// A fully configurable [AuthAdapter] for REST/JSON backends.
///
/// Every request goes through the application's central [ApiClient], so the
/// base URL, headers, logging, the API inspector and error mapping apply to
/// authentication calls too. Nothing is hardcoded: endpoints come from
/// [endpoints], response fields from [mapping], and each request body or
/// response parser can be replaced by a hook.
///
/// ```dart
/// RestAuthAdapter(
///   apiClient: ref.watch(apiClientProvider),
///   endpoints: const RestAuthEndpoints(
///     login: '/auth/login',
///     refresh: '/auth/refresh',
///     logout: '/auth/logout',
///     currentUser: '/me',
///   ),
///   // {"username": ..., "password": ..., "device": "mobile"}
///   loginBody: (credentials) => {...credentials.fields, 'device': 'mobile'},
///   mapping: const AuthResponseMapping(accessToken: ['data.jwt']),
///   sessionValidator: (session) {
///     if (!session.user!.roles.contains('staff')) {
///       throw const AuthFailure('This app is reserved for staff members.');
///     }
///   },
/// );
/// ```
///
/// Request policies:
///
/// * sign-in, refresh, registration and password recovery are public calls
///   ([ApiRequestOptions.unauthenticated]);
/// * sign-out sends the session's access token explicitly and never triggers
///   a token refresh;
/// * the current-user call is a regular authenticated request.
///
/// Failures thrown by the [ApiClient] propagate unchanged, except a `401` on
/// the sign-in call which becomes an [AuthFailure] using
/// [invalidCredentialsMessage] (unless the backend supplied its own message;
/// the generic, possibly localized, "unauthorized" message of a
/// `DefaultApiErrorMapper` is never used for it).
class RestAuthAdapter extends AuthAdapter {
  /// Creates the adapter.
  ///
  /// Provide either [apiClient] or [apiClientResolver] (resolved lazily on
  /// every request, which helps when the adapter must be created before the
  /// client exists).
  RestAuthAdapter({
    ApiClient? apiClient,
    ApiClient Function()? apiClientResolver,
    required this.endpoints,
    this.mapping = const AuthResponseMapping(),
    this.refreshTokenField = 'refresh_token',
    this.loginBody,
    this.refreshBody,
    this.refreshHeaders,
    this.logoutBody,
    this.registerBody,
    this.requestPasswordResetBody,
    this.confirmPasswordResetBody,
    this.parseSession,
    this.parseRefresh,
    this.parseUser,
    this.parseRegistration,
    this.fetchUserAfterLogin = true,
    this.authHeaderName,
    this.authTokenPrefix,
    this.sessionValidator,
    this.invalidResponseMessage = 'Invalid authentication response',
    this.invalidCredentialsMessage = 'Invalid credentials. Please try again.',
    DateTime Function()? clock,
  }) : assert(
         apiClient != null || apiClientResolver != null,
         'RestAuthAdapter needs an apiClient or an apiClientResolver.',
       ),
       _apiClient = apiClient,
       _apiClientResolver = apiClientResolver,
       _clock = clock ?? DateTime.now;

  final ApiClient? _apiClient;
  final ApiClient Function()? _apiClientResolver;
  final DateTime Function() _clock;

  /// Paths and HTTP methods of the backend's authentication endpoints.
  final RestAuthEndpoints endpoints;

  /// Locations of token and user fields in responses (used when the
  /// matching `parse…` hook is not set).
  final AuthResponseMapping mapping;

  /// Field holding the refresh token in the default refresh request body
  /// (`{"refresh_token": "…"}`).
  final String refreshTokenField;

  /// Builds the sign-in request body. Defaults to `credentials.fields`.
  final Object? Function(AuthCredentials credentials)? loginBody;

  /// Builds the refresh request body. Defaults to
  /// `{refreshTokenField: tokens.refreshToken}`.
  final Object? Function(AuthTokens tokens)? refreshBody;

  /// Extra headers of the refresh request (for backends expecting the
  /// refresh or the expired access token in a header).
  final Map<String, String> Function(AuthTokens tokens)? refreshHeaders;

  /// Builds the sign-out request body. Defaults to no body.
  final Object? Function(AuthSession session)? logoutBody;

  /// Builds the registration request body. Defaults to `data.fields`.
  final Object? Function(AuthCredentials data)? registerBody;

  /// Builds the password reset request body. Defaults to `data.fields`.
  final Object? Function(AuthCredentials data)? requestPasswordResetBody;

  /// Builds the password reset confirmation body. Defaults to `data.fields`.
  final Object? Function(AuthCredentials data)? confirmPasswordResetBody;

  /// Converts the sign-in response body into a session. Defaults to
  /// [AuthResponseMapping.readSession].
  final AuthSession Function(Object? data)? parseSession;

  /// Converts the refresh response body into tokens. `previous` are the
  /// tokens that were refreshed. Defaults to
  /// [AuthResponseMapping.readTokens]; the previous refresh token is kept
  /// when the response does not contain a new one.
  final AuthTokens Function(Object? data, AuthTokens previous)? parseRefresh;

  /// Converts the current-user response body into a user. Defaults to
  /// [AuthResponseMapping.readCurrentUser].
  final AuthUser? Function(Object? data)? parseUser;

  /// Converts the registration response body into a session, or `null` when
  /// the backend does not sign the new user in. Defaults to
  /// [AuthResponseMapping.readSession] (a session exists when the response
  /// contains an access token).
  final AuthSession? Function(Object? data)? parseRegistration;

  /// Whether the [RestAuthEndpoints.currentUser] endpoint is called right
  /// after sign-in (and registration) when the response contains no user.
  final bool fetchUserAfterLogin;

  /// Header carrying the access token on calls that send it explicitly
  /// (sign-out, user lookup after sign-in). Defaults to
  /// `SymphonyConfig.authHeaderName` of the [ApiClient].
  final String? authHeaderName;

  /// Prefix of the access token on calls that send it explicitly. Defaults
  /// to `SymphonyConfig.authTokenPrefix` of the [ApiClient].
  final String? authTokenPrefix;

  /// Project specific business rules executed after sign-in and session
  /// restoration. Throw a [Failure] (for example an [AuthFailure]) to reject
  /// the session.
  final FutureOr<void> Function(AuthSession session)? sessionValidator;

  /// Message of the [AuthFailure] thrown when a response does not contain an
  /// access token (or cannot be parsed).
  final String invalidResponseMessage;

  /// Message of the [AuthFailure] thrown when the backend rejects the
  /// credentials with a `401` without providing its own message.
  final String invalidCredentialsMessage;

  /// The [ApiClient] used for every request.
  ApiClient get apiClient {
    final client = _apiClient ?? _apiClientResolver?.call();
    if (client == null) {
      throw StateError(
        'RestAuthAdapter needs an apiClient or an apiClientResolver.',
      );
    }
    return client;
  }

  @override
  bool get supportsRegistration => endpoints.register != null;

  @override
  bool get supportsPasswordRecovery => endpoints.requestPasswordReset != null;

  @override
  Future<AuthSession> login(AuthCredentials credentials) async {
    final ApiResponse<Object?> response;
    try {
      response = await _send(
        endpoints.login,
        method: endpoints.loginMethod,
        data: loginBody != null ? loginBody!(credentials) : credentials.fields,
        options: ApiRequestOptions.unauthenticated,
      );
    } on UnauthorizedFailure catch (failure) {
      throw _invalidCredentials(failure);
    }
    final session = _parse(
      () =>
          parseSession != null
              ? parseSession!(response.data)
              : _requireSession(response.data),
    );
    _requireAccessToken(session.tokens);
    return _completeUser(session);
  }

  @override
  Future<AuthTokens> refresh(AuthTokens current) async {
    final path = endpoints.refresh;
    if (path == null || !current.canRefresh) {
      throw const UnauthorizedFailure();
    }
    final headers = refreshHeaders?.call(current);
    final response = await _send(
      path,
      method: endpoints.refreshMethod,
      data:
          refreshBody != null
              ? refreshBody!(current)
              : <String, Object?>{refreshTokenField: current.refreshToken},
      options:
          headers == null || headers.isEmpty
              ? ApiRequestOptions.unauthenticated
              : ApiRequestOptions.unauthenticated.copyWith(headers: headers),
    );
    final tokens = _parse(
      () =>
          parseRefresh != null
              ? parseRefresh!(response.data, current)
              : mapping.readTokens(response.data, now: _clock()) ??
                  (throw AuthFailure(invalidResponseMessage)),
    );
    _requireAccessToken(tokens);
    return tokens.canRefresh
        ? tokens
        : tokens.copyWith(refreshToken: current.refreshToken);
  }

  @override
  Future<void> logout(AuthSession session) async {
    final path = endpoints.logout;
    if (path == null) return;
    await _send(
      path,
      method: endpoints.logoutMethod,
      data: logoutBody?.call(session),
      options: ApiRequestOptions(
        refreshOnUnauthorized: false,
        headers: _authorizationHeader(session.tokens),
      ),
    );
  }

  @override
  Future<AuthUser?> fetchCurrentUser(AuthSession session) async {
    if (endpoints.currentUser == null) return session.user;
    final user = await _requestUser(session.tokens, explicitToken: false);
    return user ?? session.user;
  }

  @override
  Future<void> validateSession(AuthSession session) async {
    final validator = sessionValidator;
    if (validator != null) await validator(session);
  }

  @override
  Future<AuthSession?> register(AuthCredentials data) async {
    final path = endpoints.register;
    if (path == null) return super.register(data);
    final response = await _send(
      path,
      method: endpoints.registerMethod,
      data: registerBody != null ? registerBody!(data) : data.fields,
      options: ApiRequestOptions.unauthenticated,
    );
    final session = _parse(
      () =>
          parseRegistration != null
              ? parseRegistration!(response.data)
              : mapping.readSession(response.data, now: _clock()),
    );
    if (session == null) return null;
    _requireAccessToken(session.tokens);
    return _completeUser(session);
  }

  @override
  Future<void> requestPasswordReset(AuthCredentials data) async {
    final path = endpoints.requestPasswordReset;
    if (path == null) return super.requestPasswordReset(data);
    await _send(
      path,
      method: endpoints.requestPasswordResetMethod,
      data:
          requestPasswordResetBody != null
              ? requestPasswordResetBody!(data)
              : data.fields,
      options: ApiRequestOptions.unauthenticated,
    );
  }

  @override
  Future<void> confirmPasswordReset(AuthCredentials data) async {
    final path = endpoints.confirmPasswordReset;
    if (path == null) return super.confirmPasswordReset(data);
    await _send(
      path,
      method: endpoints.confirmPasswordResetMethod,
      data:
          confirmPasswordResetBody != null
              ? confirmPasswordResetBody!(data)
              : data.fields,
      options: ApiRequestOptions.unauthenticated,
    );
  }

  Future<ApiResponse<Object?>> _send(
    String path, {
    required String method,
    required ApiRequestOptions options,
    Object? data,
  }) {
    return apiClient.request<Object?>(
      path,
      method: method,
      data: data,
      options: options,
    );
  }

  /// Loads the user when the sign-in / registration response had none.
  Future<AuthSession> _completeUser(AuthSession session) async {
    if (session.user != null ||
        !fetchUserAfterLogin ||
        endpoints.currentUser == null) {
      return session;
    }
    final user = await _requestUser(session.tokens, explicitToken: true);
    return AuthSession(tokens: session.tokens, user: user);
  }

  /// Calls the current-user endpoint. With [explicitToken] the access token
  /// of [tokens] is sent explicitly because the session is not active yet.
  Future<AuthUser?> _requestUser(
    AuthTokens tokens, {
    required bool explicitToken,
  }) async {
    final response = await _send(
      endpoints.currentUser!,
      method: endpoints.currentUserMethod,
      options:
          explicitToken
              ? ApiRequestOptions(
                requiresAuth: false,
                refreshOnUnauthorized: false,
                headers: _authorizationHeader(tokens),
              )
              : const ApiRequestOptions(),
    );
    return _parse(
      () =>
          parseUser != null
              ? parseUser!(response.data)
              : mapping.readCurrentUser(response.data),
    );
  }

  AuthSession _requireSession(Object? data) {
    final session = mapping.readSession(data, now: _clock());
    if (session == null) throw AuthFailure(invalidResponseMessage);
    return session;
  }

  /// Rejects tokens without an access token (custom parsers included).
  void _requireAccessToken(AuthTokens tokens) {
    if (tokens.accessToken.trim().isEmpty) {
      throw AuthFailure(invalidResponseMessage);
    }
  }

  Map<String, String> _authorizationHeader(AuthTokens tokens) {
    final name = authHeaderName ?? apiClient.config.authHeaderName;
    final prefix = (authTokenPrefix ?? apiClient.config.authTokenPrefix).trim();
    return <String, String>{
      name:
          prefix.isEmpty ? tokens.accessToken : '$prefix ${tokens.accessToken}',
    };
  }

  AuthFailure _invalidCredentials(UnauthorizedFailure failure) {
    final message =
        _isGenericUnauthorizedMessage(failure.message)
            ? invalidCredentialsMessage
            : failure.message;
    return AuthFailure(
      message,
      code: failure.code,
      statusCode: failure.statusCode,
      cause: failure,
      stackTrace: failure.stackTrace,
    );
  }

  /// Whether [message] is the generic "unauthorized" message of the error
  /// mapper (the backend sent none), including a localized
  /// `DefaultApiErrorMapper.unauthorizedMessage`.
  bool _isGenericUnauthorizedMessage(String message) {
    if (message == const UnauthorizedFailure().message) return true;
    try {
      final mapper = apiClient.errorMapper;
      return mapper is DefaultApiErrorMapper &&
          message == mapper.unauthorizedMessage;
    } on Object {
      return false;
    }
  }

  /// Runs a response parser, converting unexpected errors (bad casts in a
  /// custom hook...) into a [ParsingFailure].
  T _parse<T>(T Function() parser) {
    try {
      return parser();
    } on Failure {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw ParsingFailure(
        invalidResponseMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}
