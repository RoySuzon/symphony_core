import 'package:flutter/foundation.dart';

import '../logging/log_level.dart';
import '../logging/log_redactor.dart';
import 'app_environment.dart';

/// Immutable, application-wide configuration for `symphony_core`.
///
/// Every value has a sensible default except [baseUrl]. Pass an instance to
/// `SymphonyCore.initialize` (or `symphonyOverrides`) and use [copyWith] to
/// derive variants, for example per environment.
///
/// ```dart
/// SymphonyCore.initialize(
///   config: SymphonyConfig(
///     baseUrl: 'https://api.example.com',
///     enableInspector: true,
///     enableLogging: true,
///     connectTimeout: Duration(seconds: 30),
///   ),
/// );
/// ```
@immutable
class SymphonyConfig {
  /// Creates a configuration. Only [baseUrl] is required.
  const SymphonyConfig({
    required this.baseUrl,
    this.appName = 'Symphony App',
    this.environment = AppEnvironment.development,
    this.enableInspector = false,
    this.enableLogging = false,
    this.logLevel = LogLevel.debug,
    this.logRequestBodies = true,
    this.logResponseBodies = true,
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.defaultHeaders = const <String, String>{},
    this.authHeaderName = 'Authorization',
    this.authTokenPrefix = 'Bearer',
    this.refreshTokenStatusCodes = const <int>{401},
    this.maxRetries = 0,
    this.retryDelay = const Duration(milliseconds: 500),
    this.retryStatusCodes = const <int>{408, 429, 502, 503, 504},
    this.inspectorMaxEntries = 200,
    this.maxLoggedBodyLength = 4000,
    this.sensitiveKeys = LogRedactor.defaultSensitiveKeys,
    this.handleGlobalErrors = true,
    this.extras = const <String, Object?>{},
  })  : assert(maxRetries >= 0, 'maxRetries must be >= 0'),
        assert(inspectorMaxEntries > 0, 'inspectorMaxEntries must be > 0'),
        assert(maxLoggedBodyLength > 0, 'maxLoggedBodyLength must be > 0');

  /// Base URL used by the central `ApiClient`.
  ///
  /// It can be changed at runtime through `ApiClient.updateBaseUrl` without
  /// touching any repository.
  final String baseUrl;

  /// Display name of the application (used by default UI such as the splash
  /// screen and the inspector).
  final String appName;

  /// Environment the application currently runs in.
  final AppEnvironment environment;

  /// Records HTTP traffic in the in-app API inspector.
  ///
  /// Recommended: `enableInspector: kDebugMode` or only for non-production
  /// environments.
  final bool enableInspector;

  /// Enables console logging (including redacted HTTP logs).
  final bool enableLogging;

  /// Minimum level written by the logger when [enableLogging] is true.
  final LogLevel logLevel;

  /// Whether request bodies are included in logs and in the inspector.
  final bool logRequestBodies;

  /// Whether response bodies are included in logs and in the inspector.
  final bool logResponseBodies;

  /// Maximum time to establish a connection.
  final Duration connectTimeout;

  /// Maximum time between two received data packets.
  final Duration receiveTimeout;

  /// Maximum time to send the request body.
  final Duration sendTimeout;

  /// Headers sent with every request (for example `Accept-Language`).
  final Map<String, String> defaultHeaders;

  /// Header used to transport the access token.
  final String authHeaderName;

  /// Prefix placed before the access token, e.g. `Bearer` produces
  /// `Authorization: Bearer <token>`. Use an empty string to send the raw
  /// token.
  final String authTokenPrefix;

  /// HTTP status codes that trigger a token refresh followed by one retry.
  final Set<int> refreshTokenStatusCodes;

  /// Number of automatic retries for idempotent requests that failed because
  /// of connectivity problems, timeouts or a status in [retryStatusCodes].
  final int maxRetries;

  /// Base delay between retries (multiplied by the attempt number).
  final Duration retryDelay;

  /// HTTP status codes considered transient and therefore retryable.
  final Set<int> retryStatusCodes;

  /// Maximum number of calls kept by the API inspector (oldest are dropped).
  final int inspectorMaxEntries;

  /// Bodies longer than this many characters are truncated in logs and in the
  /// inspector.
  final int maxLoggedBodyLength;

  /// Keys (headers, JSON fields, query parameters) whose values are masked in
  /// logs and in the inspector. Matching is case-insensitive and ignores `-`,
  /// `_` and spaces; a key matches when it contains one of these entries.
  final Set<String> sensitiveKeys;

  /// Installs global Flutter / platform error handlers during initialization.
  final bool handleGlobalErrors;

  /// Free-form, project specific configuration values.
  final Map<String, Object?> extras;

  /// Returns the extra value stored under [key] when it is a [T].
  T? extra<T>(String key) {
    final value = extras[key];
    return value is T ? value : null;
  }

  /// Creates a copy of this configuration with the given fields replaced.
  SymphonyConfig copyWith({
    String? baseUrl,
    String? appName,
    AppEnvironment? environment,
    bool? enableInspector,
    bool? enableLogging,
    LogLevel? logLevel,
    bool? logRequestBodies,
    bool? logResponseBodies,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Map<String, String>? defaultHeaders,
    String? authHeaderName,
    String? authTokenPrefix,
    Set<int>? refreshTokenStatusCodes,
    int? maxRetries,
    Duration? retryDelay,
    Set<int>? retryStatusCodes,
    int? inspectorMaxEntries,
    int? maxLoggedBodyLength,
    Set<String>? sensitiveKeys,
    bool? handleGlobalErrors,
    Map<String, Object?>? extras,
  }) {
    return SymphonyConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      appName: appName ?? this.appName,
      environment: environment ?? this.environment,
      enableInspector: enableInspector ?? this.enableInspector,
      enableLogging: enableLogging ?? this.enableLogging,
      logLevel: logLevel ?? this.logLevel,
      logRequestBodies: logRequestBodies ?? this.logRequestBodies,
      logResponseBodies: logResponseBodies ?? this.logResponseBodies,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      authHeaderName: authHeaderName ?? this.authHeaderName,
      authTokenPrefix: authTokenPrefix ?? this.authTokenPrefix,
      refreshTokenStatusCodes:
          refreshTokenStatusCodes ?? this.refreshTokenStatusCodes,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      retryStatusCodes: retryStatusCodes ?? this.retryStatusCodes,
      inspectorMaxEntries: inspectorMaxEntries ?? this.inspectorMaxEntries,
      maxLoggedBodyLength: maxLoggedBodyLength ?? this.maxLoggedBodyLength,
      sensitiveKeys: sensitiveKeys ?? this.sensitiveKeys,
      handleGlobalErrors: handleGlobalErrors ?? this.handleGlobalErrors,
      extras: extras ?? this.extras,
    );
  }

  /// A [LogRedactor] configured with [sensitiveKeys].
  LogRedactor get redactor => LogRedactor(sensitiveKeys: sensitiveKeys);

  @override
  String toString() => 'SymphonyConfig(appName: $appName, '
      'environment: ${environment.name}, baseUrl: $baseUrl, '
      'enableInspector: $enableInspector, enableLogging: $enableLogging)';
}
