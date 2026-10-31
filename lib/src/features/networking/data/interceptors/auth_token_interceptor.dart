import 'dart:async';

import 'package:dio/dio.dart';

import '../../../../core/config/symphony_config.dart';
import '../../../../core/logging/symphony_logger.dart';
import '../../domain/api_request_options.dart';
import '../../domain/auth_token_delegate.dart';
import '../api_client.dart';
import 'interceptor_support.dart';

/// Attaches the access token to requests and transparently refreshes it when
/// the server rejects it.
///
/// **Token injection** (`onRequest`): unless the request is marked
/// unauthenticated (`ApiRequestOptions.requiresAuth == false`), the token
/// returned by `AuthTokenDelegate.getAccessToken` is sent in
/// `SymphonyConfig.authHeaderName` as `'<authTokenPrefix> <token>'` (or the
/// raw token when the prefix is empty). A header set explicitly by the caller
/// (per request, as a default header or by an earlier interceptor) is never
/// replaced. Requests started while a refresh is in progress wait for it, so
/// they are sent with the new token.
///
/// **Refresh** (`onError`): when a response status is in
/// `SymphonyConfig.refreshTokenStatusCodes`, the request required
/// authentication, allows refreshing (`refreshOnUnauthorized`), was not
/// already replayed after a refresh and carried a token injected by this
/// interceptor, then:
///
/// * concurrent failures share a single `refreshAccessToken` call;
/// * a request sent with an older token than the current one is replayed
///   with the current token without refreshing again;
/// * the request is replayed once with the new token and the replayed
///   response is returned to the caller;
/// * when the refresh yields no token, or the replayed request is rejected
///   again, `AuthTokenDelegate.onSessionExpired` is awaited (once for
///   concurrent failures) and the error is propagated;
/// * a session that was signed out since the request was sent (no current
///   token), or that is being expired, is never refreshed: the error is
///   propagated (the request is only replayed when a different token, i.e. a
///   new sign-in, is available).
///
/// Requests issued from inside `refreshAccessToken` or `onSessionExpired`
/// (for example a refresh or logout call) while it runs never trigger a
/// refresh themselves and never wait for the refresh in progress, which
/// rules out refresh loops and deadlocks even if such a call is not marked
/// unauthenticated. Work they schedule for later (timers, listeners...) is
/// treated normally once the refresh or expiry is over. Requests whose body
/// is a `Stream` cannot be replayed and are never refreshed.
///
/// Errors thrown by the delegate are logged without their message (which may
/// contain credentials) and treated as "no token".
class AuthTokenInterceptor extends Interceptor {
  /// Creates the interceptor.
  ///
  /// [dio] replays requests after a refresh (pass the same instance this
  /// interceptor is installed on). [tokenDelegate] is called lazily, on every
  /// use, so the delegate can be created after the client.
  AuthTokenInterceptor({
    required this.dio,
    required this.config,
    AuthTokenDelegateResolver? tokenDelegate,
    SymphonyLogger? logger,
  })  : _resolveDelegate = tokenDelegate,
        _logger = logger ?? SymphonyLogger.disabled();

  /// Dio instance used to replay requests after a token refresh.
  final Dio dio;

  /// Configuration providing the header name, the token prefix and the
  /// status codes that trigger a refresh.
  final SymphonyConfig config;

  final AuthTokenDelegateResolver? _resolveDelegate;
  final SymphonyLogger _logger;

  Future<String?>? _refreshing;
  Future<void>? _expiring;
  int _generation = 0;

  static const String _injectedKey = 'symphony.internal.authInjected';
  static const String _generationKey = 'symphony.internal.authGeneration';
  static final Object _guardZoneKey = Object();

  /// Whether a token refresh is currently in progress.
  bool get isRefreshing => _refreshing != null;

  /// The value sent in the authorization header for [token]: the token
  /// preceded by `SymphonyConfig.authTokenPrefix` and a space, or the raw
  /// token when the prefix is empty.
  String authorizationValue(String token) {
    final prefix = config.authTokenPrefix.trim();
    return prefix.isEmpty ? token : '$prefix $token';
  }

  /// Whether the current zone belongs to a refresh or expiry still running.
  bool get _inGuardedZone {
    final guard = Zone.current[_guardZoneKey];
    return guard is _FlowGuard && guard.active;
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      await _attachToken(options);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Could not attach the access token (${error.runtimeType}).',
        stackTrace: stackTrace,
      );
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final recovery = await _recover(err);
    if (recovery == null) {
      handler.next(err);
      return;
    }
    final response = recovery.response;
    if (response != null) {
      handler.resolve(response);
    } else {
      handler.reject(recovery.error ?? err);
    }
  }

  Future<void> _attachToken(RequestOptions options) async {
    final extra = options.extra;
    if (!readBoolExtra(
      extra,
      SymphonyRequestExtras.requiresAuth,
      defaultValue: true,
    )) {
      return;
    }
    final headerName = config.authHeaderName;
    final injected = extra[_injectedKey] == true;
    // A header we did not inject was provided by the caller: keep it.
    if (!injected && findHeader(options.headers, headerName) != null) return;
    // Replay after a refresh: the refreshed token is already in place.
    if (injected && extra[SymphonyRequestExtras.authRetried] == true) return;

    final delegate = _delegate();
    if (delegate == null) {
      if (injected) _clearToken(options);
      return;
    }
    final pending = _refreshing;
    var token = pending != null && !_inGuardedZone ? await pending : null;
    final generation = _generation;
    token ??= await _readToken(delegate);
    if (token == null) {
      if (injected) _clearToken(options);
      return;
    }
    removeHeader(options.headers, headerName);
    options.headers[headerName] = authorizationValue(token);
    extra[_injectedKey] = true;
    extra[_generationKey] = generation;
  }

  void _clearToken(RequestOptions options) {
    removeHeader(options.headers, config.authHeaderName);
    options.extra.remove(_injectedKey);
    options.extra.remove(_generationKey);
  }

  /// Returns `null` when the error is not handled by this interceptor.
  Future<_Recovery?> _recover(DioException err) async {
    try {
      if (!_isRefreshCandidate(err)) return null;
      final delegate = _delegate();
      if (delegate == null) return null;

      final options = err.requestOptions;
      final sentHeader = findHeader(options.headers, config.authHeaderName);
      final (String? token, bool refreshed) = sentHeader == null
          // Sent without credentials (signed out at that time): only replay
          // when a token became available meanwhile.
          ? (await _readToken(delegate), false)
          : await _tokenForRetry(
              delegate,
              '$sentHeader',
              options.extra[_generationKey],
            );

      if (token == null) {
        // No refresh was attempted for this request (the session was already
        // cleared elsewhere): propagate the error unchanged.
        if (!refreshed) return null;
        await _expireSession(delegate);
        return _Recovery.rejected(err);
      }

      _logger.debug(
        'Replaying ${options.method.toUpperCase()} '
        '${loggableUri(config.redactor, options.uri)} with a new access token.',
      );
      try {
        final response = await dio.fetch<dynamic>(
          _replayOptions(options, token),
        );
        return _Recovery.resolved(response);
      } on DioException catch (replayError) {
        final status = replayError.response?.statusCode;
        if (status != null && config.refreshTokenStatusCodes.contains(status)) {
          await _expireSession(delegate);
        }
        return _Recovery.rejected(replayError);
      }
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Access token recovery failed (${error.runtimeType}).',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  bool _isRefreshCandidate(DioException err) {
    final status = err.response?.statusCode;
    if (status == null || !config.refreshTokenStatusCodes.contains(status)) {
      return false;
    }
    final options = err.requestOptions;
    final extra = options.extra;
    if (!readBoolExtra(
          extra,
          SymphonyRequestExtras.requiresAuth,
          defaultValue: true,
        ) ||
        !readBoolExtra(
          extra,
          SymphonyRequestExtras.refreshOnUnauthorized,
          defaultValue: true,
        ) ||
        readBoolExtra(
          extra,
          SymphonyRequestExtras.authRetried,
          defaultValue: false,
        )) {
      return false;
    }
    if (_inGuardedZone) return false;
    if (options.cancelToken?.isCancelled ?? false) return false;
    if (!isReplayableBody(options.data)) return false;
    // Credentials supplied explicitly by the caller are never replaced.
    if (extra[_injectedKey] != true &&
        findHeader(options.headers, config.authHeaderName) != null) {
      return false;
    }
    return true;
  }

  /// Resolves the token to replay a rejected request with. The record's
  /// second value tells whether the token comes from a refresh attempt.
  Future<(String?, bool)> _tokenForRetry(
    AuthTokenDelegate delegate,
    String sentHeader,
    Object? sentGeneration,
  ) async {
    final pending = _refreshing;
    if (pending != null) return (await pending, true);
    if (_expiring != null) {
      return (await _tokenAfterExpiry(delegate, sentHeader), false);
    }

    final generation = _generation;
    if (sentGeneration is int && sentGeneration < generation) {
      // A refresh completed after this request was sent: use its result.
      return (await _readToken(delegate), false);
    }

    final current = await _readToken(delegate);
    final started = _refreshing;
    if (started != null) return (await started, true);
    if (_expiring != null) {
      return (await _tokenAfterExpiry(delegate, sentHeader), false);
    }
    if (_generation != generation) {
      // A refresh completed while the current token was being read.
      return (await _readToken(delegate), false);
    }
    // Signed out since the request was sent: there is no session to refresh
    // (refreshing could even resurrect it).
    if (current == null) return (null, false);
    if (authorizationValue(current) != sentHeader) {
      // The token changed since the request was sent (refreshed elsewhere or
      // a new sign-in): replay without refreshing again.
      return (current, false);
    }
    return (await _refreshOnce(delegate), true);
  }

  /// Waits for the session expiry in progress, then returns the token to
  /// replay with: a token different from [sentHeader] (a new sign-in), or
  /// `null`. The rejected session is never refreshed a second time.
  Future<String?> _tokenAfterExpiry(
    AuthTokenDelegate delegate,
    String sentHeader,
  ) async {
    final expiring = _expiring;
    if (expiring != null) await expiring;
    final token = await _readToken(delegate);
    if (token == null || authorizationValue(token) == sentHeader) return null;
    return token;
  }

  Future<String?> _refreshOnce(AuthTokenDelegate delegate) {
    final pending = _refreshing;
    if (pending != null) return pending;
    final completer = Completer<String?>();
    // Assigned before the refresh starts so that a synchronously completing
    // delegate cannot leave a stale future behind.
    _refreshing = completer.future;
    unawaited(_runRefresh(delegate, completer));
    return completer.future;
  }

  Future<void> _runRefresh(
    AuthTokenDelegate delegate,
    Completer<String?> completer,
  ) async {
    String? token;
    try {
      _logger.info('Access token rejected; refreshing the session.');
      token = await _guarded(delegate.refreshAccessToken);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Session refresh failed (${error.runtimeType}).',
        stackTrace: stackTrace,
      );
      token = null;
    }
    if (token != null && token.isEmpty) token = null;
    if (token == null) {
      _logger.info('Session refresh did not produce a new access token.');
    }
    _generation++;
    _refreshing = null;
    completer.complete(token);
  }

  Future<void> _expireSession(AuthTokenDelegate delegate) {
    final pending = _expiring;
    if (pending != null) return pending;
    final completer = Completer<void>();
    _expiring = completer.future;
    unawaited(_runExpiry(delegate, completer));
    return completer.future;
  }

  Future<void> _runExpiry(
    AuthTokenDelegate delegate,
    Completer<void> completer,
  ) async {
    try {
      _logger.warning('The session has expired.');
      await _guarded(delegate.onSessionExpired);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'onSessionExpired failed (${error.runtimeType}).',
        stackTrace: stackTrace,
      );
    }
    _expiring = null;
    completer.complete();
  }

  /// Runs [body] in a zone marking the requests it issues as part of the
  /// refresh / expiry flow. The mark is lifted when [body] completes, so
  /// work it schedules for later (timers, listeners, streams...) is not
  /// exempted from refreshing forever.
  Future<T> _guarded<T>(Future<T> Function() body) async {
    final guard = _FlowGuard();
    try {
      final result = await runZoned(
        body,
        zoneValues: <Object?, Object?>{_guardZoneKey: guard},
      );
      return result;
    } finally {
      guard.active = false;
    }
  }

  Future<String?> _readToken(AuthTokenDelegate delegate) async {
    try {
      final token = await delegate.getAccessToken();
      return token == null || token.isEmpty ? null : token;
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Could not read the access token (${error.runtimeType}).',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  AuthTokenDelegate? _delegate() {
    final resolve = _resolveDelegate;
    if (resolve == null) return null;
    try {
      return resolve();
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Could not resolve the AuthTokenDelegate (${error.runtimeType}).',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  RequestOptions _replayOptions(RequestOptions options, String token) {
    final headers = <String, dynamic>{...options.headers};
    removeHeader(headers, config.authHeaderName);
    headers[config.authHeaderName] = authorizationValue(token);
    return options.copyWith(
      headers: headers,
      extra: <String, dynamic>{
        ...options.extra,
        SymphonyRequestExtras.authRetried: true,
        _injectedKey: true,
        _generationKey: _generation,
      },
      data: replayableBody(options.data),
    );
  }
}

/// Zone value marking a refresh / expiry flow of [AuthTokenInterceptor];
/// [active] until that flow completes.
class _FlowGuard {
  bool active = true;
}

/// Outcome of [AuthTokenInterceptor._recover].
class _Recovery {
  const _Recovery.resolved(Response<dynamic> this.response) : error = null;

  const _Recovery.rejected(DioException this.error) : response = null;

  final Response<dynamic>? response;
  final DioException? error;
}
