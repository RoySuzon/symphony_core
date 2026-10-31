import 'package:flutter/foundation.dart';

/// Keys stored in Dio's `RequestOptions.extra` by `ApiClient`.
///
/// Interceptors (including custom application interceptors and the API
/// inspector) read these keys to honour per-request policies.
abstract final class SymphonyRequestExtras {
  /// `bool` – inject the access token. Defaults to `true`.
  static const String requiresAuth = 'symphony.requiresAuth';

  /// `bool` – refresh the token and retry once on an unauthorized status.
  static const String refreshOnUnauthorized = 'symphony.refreshOnUnauthorized';

  /// `bool` – whether this request was already retried after a refresh.
  static const String authRetried = 'symphony.authRetried';

  /// `bool` – allow automatic retries on transient errors.
  static const String retry = 'symphony.retry';

  /// `int` – per-request override of the maximum number of retries.
  static const String maxRetries = 'symphony.maxRetries';

  /// `int` – current retry attempt (0 for the first try).
  static const String retryAttempt = 'symphony.retryAttempt';

  /// `bool` – record this request in the API inspector. Defaults to `true`.
  static const String inspect = 'symphony.inspect';

  /// `bool` – write this request to the logs. Defaults to `true`.
  static const String log = 'symphony.log';
}

/// Per-request options accepted by every `ApiClient` method.
///
/// ```dart
/// await apiClient.post<void>(
///   '/auth/login',
///   data: body,
///   options: ApiRequestOptions.unauthenticated,
/// );
/// ```
@immutable
class ApiRequestOptions {
  /// Creates request options.
  const ApiRequestOptions({
    this.headers = const <String, String>{},
    this.requiresAuth = true,
    this.refreshOnUnauthorized = true,
    this.retry = true,
    this.maxRetries,
    this.connectTimeout,
    this.receiveTimeout,
    this.sendTimeout,
    this.contentType,
    this.inspect = true,
    this.log = true,
    this.extra = const <String, Object?>{},
  });

  /// Options for public endpoints (login, refresh, registration...): no token
  /// is attached and unauthorized responses never trigger a refresh.
  static const ApiRequestOptions unauthenticated = ApiRequestOptions(
    requiresAuth: false,
    refreshOnUnauthorized: false,
  );

  /// Extra headers for this request only.
  final Map<String, String> headers;

  /// Whether the access token is attached.
  final bool requiresAuth;

  /// Whether an unauthorized response triggers a token refresh and a retry.
  final bool refreshOnUnauthorized;

  /// Whether transient failures may be retried automatically.
  ///
  /// Only idempotent methods (GET, HEAD, OPTIONS, PUT, DELETE) are retried.
  final bool retry;

  /// Overrides `SymphonyConfig.maxRetries` for this request.
  final int? maxRetries;

  /// Overrides the connect timeout for this request.
  ///
  /// Dio applies connect timeouts per client; `ApiClient` honours this value
  /// on a best-effort basis.
  final Duration? connectTimeout;

  /// Overrides the receive timeout for this request.
  final Duration? receiveTimeout;

  /// Overrides the send timeout for this request.
  final Duration? sendTimeout;

  /// Content type of the request body (e.g. `application/json`).
  final String? contentType;

  /// Whether the request is recorded in the API inspector.
  final bool inspect;

  /// Whether the request is written to the logs.
  final bool log;

  /// Additional values copied into Dio's `RequestOptions.extra`.
  final Map<String, Object?> extra;

  /// Returns a copy with the given fields replaced.
  ApiRequestOptions copyWith({
    Map<String, String>? headers,
    bool? requiresAuth,
    bool? refreshOnUnauthorized,
    bool? retry,
    int? maxRetries,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    String? contentType,
    bool? inspect,
    bool? log,
    Map<String, Object?>? extra,
  }) {
    return ApiRequestOptions(
      headers: headers ?? this.headers,
      requiresAuth: requiresAuth ?? this.requiresAuth,
      refreshOnUnauthorized:
          refreshOnUnauthorized ?? this.refreshOnUnauthorized,
      retry: retry ?? this.retry,
      maxRetries: maxRetries ?? this.maxRetries,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      contentType: contentType ?? this.contentType,
      inspect: inspect ?? this.inspect,
      log: log ?? this.log,
      extra: extra ?? this.extra,
    );
  }

  /// The values stored in Dio's `RequestOptions.extra` for this request.
  Map<String, Object?> toExtra() => <String, Object?>{
        ...extra,
        SymphonyRequestExtras.requiresAuth: requiresAuth,
        SymphonyRequestExtras.refreshOnUnauthorized: refreshOnUnauthorized,
        SymphonyRequestExtras.retry: retry,
        if (maxRetries != null) SymphonyRequestExtras.maxRetries: maxRetries,
        SymphonyRequestExtras.inspect: inspect,
        SymphonyRequestExtras.log: log,
      };
}
