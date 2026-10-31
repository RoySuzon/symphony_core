import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/symphony_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/logging/symphony_logger.dart';
import '../../inspector/data/api_inspector.dart';
import '../../inspector/data/api_inspector_interceptor.dart';
import '../domain/api_error_mapper.dart';
import '../domain/api_request_options.dart';
import '../domain/api_response.dart';
import '../domain/auth_token_delegate.dart';
import '../domain/upload_file.dart';
import 'default_api_error_mapper.dart';
import 'interceptors/auth_token_interceptor.dart';
import 'interceptors/headers_interceptor.dart';
import 'interceptors/interceptor_support.dart';
import 'interceptors/retry_interceptor.dart';
import 'interceptors/secure_logging_interceptor.dart';
import 'upload_form_data.dart';

/// Converts a decoded JSON body into a model.
typedef ResponseDecoder<T> = T Function(Object? data);

/// Supplies dynamic headers for every request (locale, app version...).
typedef HeaderProvider = FutureOr<Map<String, String>> Function();

/// Lazily resolves the [AuthTokenDelegate] (breaks provider cycles between
/// networking and authentication).
typedef AuthTokenDelegateResolver = AuthTokenDelegate? Function();

/// The single, central HTTP client of an application.
///
/// Wraps one [Dio] instance and owns every cross-cutting networking concern:
/// base URL (changeable at runtime), headers, timeouts, token injection and
/// refresh, retries, the API inspector, secure logging and error mapping.
/// Feature repositories only call [get], [post], [put], [patch], [delete],
/// [upload] or [download]; they never touch Dio directly.
///
/// Every method throws a `Failure` (see `ApiErrorMapper`) when the call fails.
///
/// ```dart
/// final client = ApiClient(
///   config: const SymphonyConfig(baseUrl: 'https://api.example.com'),
///   tokenDelegate: () => myTokenDelegate,
///   headerProviders: [() => {'Accept-Language': currentLocale}],
/// );
/// final response = await client.get<Map<String, dynamic>>('/me');
/// final user = User.fromJson(response.data);
/// ```
///
/// Interceptors run in this order for requests, responses and errors:
/// API inspector (when `SymphonyConfig.enableInspector` and an [ApiInspector]
/// is given) → [SecureLoggingInterceptor] (when `SymphonyConfig.enableLogging`)
/// → custom interceptors (constructor list, then [addInterceptor]) →
/// [HeadersInterceptor] → [AuthTokenInterceptor] → [RetryInterceptor].
///
/// Per-request [ApiRequestOptions] control authentication, refresh, retries,
/// logging, inspection, headers, content type and timeouts (including the
/// connect timeout, applied to the request by an internal interceptor).
class ApiClient {
  /// Creates a client from [config].
  ///
  /// * [logger] receives the HTTP logs and internal warnings; defaults to a
  ///   logger configured from [config].
  /// * [inspector] records traffic when `config.enableInspector` is true.
  /// * [tokenDelegate] is resolved lazily on every request, so the delegate
  ///   may be created after the client (see `apiClientProvider`).
  /// * [errorMapper] converts errors into failures; defaults to
  ///   [DefaultApiErrorMapper].
  /// * [interceptors] are installed between the logging interceptor and the
  ///   header / token interceptors.
  /// * [headerProviders] add dynamic headers to every request.
  /// * [httpClientAdapter] replaces Dio's adapter (tests, mocks, certificate
  ///   pinning). An injected adapter is shared infrastructure: [close] never
  ///   closes it.
  /// * [dio] is used instead of a new instance. Its options are kept, except
  ///   the base URL, the timeouts and the default headers, which come from
  ///   [config]; the client's interceptors are appended to its interceptors.
  /// * [retryDelayCallback] waits between automatic retries (defaults to
  ///   [Future.delayed]; the delay itself comes from
  ///   `SymphonyConfig.retryDelay`).
  ///
  /// Throws an [ArgumentError] when `config.baseUrl` is not an absolute URL
  /// (relative URLs are accepted on the web only).
  ApiClient({
    required SymphonyConfig config,
    SymphonyLogger? logger,
    ApiInspector? inspector,
    AuthTokenDelegateResolver? tokenDelegate,
    ApiErrorMapper? errorMapper,
    List<Interceptor> interceptors = const <Interceptor>[],
    List<HeaderProvider> headerProviders = const <HeaderProvider>[],
    HttpClientAdapter? httpClientAdapter,
    Dio? dio,
    RetryDelayCallback? retryDelayCallback,
  })  : _config = config,
        _baseUrl = ValueNotifier<String>(_checkBaseUrl(config.baseUrl)),
        _logger = logger ??
            SymphonyLogger(
              enabled: config.enableLogging,
              minLevel: config.logLevel,
              tag: 'HTTP',
            ),
        _errorMapper = errorMapper ?? const DefaultApiErrorMapper(),
        _dio = dio ?? _createDio(config),
        _ownsAdapter = httpClientAdapter == null {
    final options = _dio.options;
    if (dio != null) {
      options
        ..connectTimeout = config.connectTimeout
        ..receiveTimeout = config.receiveTimeout
        ..sendTimeout = config.sendTimeout;
      options.headers.addAll(config.defaultHeaders);
    }
    options.baseUrl = config.baseUrl;
    if (httpClientAdapter != null) _dio.httpClientAdapter = httpClientAdapter;

    _customInterceptors.addAll(interceptors);
    _headersInterceptor = HeadersInterceptor(headerProviders, logger: _logger);
    _authInterceptor = AuthTokenInterceptor(
      dio: _dio,
      config: config,
      tokenDelegate: tokenDelegate,
      logger: _logger,
    );
    _retryInterceptor = RetryInterceptor(
      dio: _dio,
      config: config,
      delay: retryDelayCallback,
      logger: _logger,
    );
    _dio.interceptors.addAll(<Interceptor>[
      const _RequestTimeoutsInterceptor(),
      if (config.enableInspector && inspector != null)
        ApiInspectorInterceptor(inspector),
      if (config.enableLogging)
        SecureLoggingInterceptor.fromConfig(config, logger: _logger),
      ..._customInterceptors,
      _headersInterceptor,
      _authInterceptor,
      _retryInterceptor,
    ]);
  }

  final SymphonyConfig _config;
  final ValueNotifier<String> _baseUrl;
  final SymphonyLogger _logger;
  final ApiErrorMapper _errorMapper;
  final Dio _dio;
  final bool _ownsAdapter;
  final List<Interceptor> _customInterceptors = <Interceptor>[];
  late final HeadersInterceptor _headersInterceptor;
  late final AuthTokenInterceptor _authInterceptor;
  late final RetryInterceptor _retryInterceptor;
  bool _closed = false;

  static Dio _createDio(SymphonyConfig config) => Dio(
        BaseOptions(
          connectTimeout: config.connectTimeout,
          receiveTimeout: config.receiveTimeout,
          sendTimeout: config.sendTimeout,
          headers: <String, dynamic>{...config.defaultHeaders},
          responseType: ResponseType.json,
        ),
      );

  /// The configuration this client was created with.
  SymphonyConfig get config => _config;

  /// The underlying Dio instance (advanced use only).
  Dio get dio => _dio;

  /// The logger receiving HTTP logs and networking warnings.
  SymphonyLogger get logger => _logger;

  /// The mapper converting errors into failures.
  ApiErrorMapper get errorMapper => _errorMapper;

  /// The interceptor attaching and refreshing access tokens.
  AuthTokenInterceptor get authTokenInterceptor => _authInterceptor;

  /// The interceptor retrying transient failures.
  RetryInterceptor get retryInterceptor => _retryInterceptor;

  /// The custom interceptors currently installed (constructor list followed
  /// by those added with [addInterceptor]).
  List<Interceptor> get interceptors =>
      List<Interceptor>.unmodifiable(_customInterceptors);

  /// The dynamic header providers currently applied.
  List<HeaderProvider> get headerProviders => _headersInterceptor.providers;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// The base URL currently in use.
  String get baseUrl => _dio.options.baseUrl;

  /// Notifies listeners whenever the base URL changes.
  ///
  /// Must not be listened to after [close].
  ValueListenable<String> get baseUrlListenable => _baseUrl;

  /// Changes the base URL for all subsequent requests.
  ///
  /// Throws an [ArgumentError] when [baseUrl] is not an absolute URL (relative
  /// URLs are accepted on the web only).
  void updateBaseUrl(String baseUrl) {
    _checkBaseUrl(baseUrl);
    _dio.options.baseUrl = baseUrl;
    if (!_closed) _baseUrl.value = baseUrl;
    _logger.info(
      'Base URL changed to ${loggableUrl(_config.redactor, baseUrl)}',
    );
  }

  /// Restores the base URL from [config].
  void resetBaseUrl() => updateBaseUrl(_config.baseUrl);

  /// The headers currently sent with every request (a case-insensitive,
  /// read-only snapshot).
  Map<String, Object?> get headers {
    final snapshot = LinkedHashMap<String, Object?>(
      equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
      hashCode: (key) => key.toLowerCase().hashCode,
    )..addAll(_dio.options.headers);
    return UnmodifiableMapView<String, Object?>(snapshot);
  }

  /// Sets (or removes, when [value] is `null`) a default header.
  void setHeader(String name, String? value) {
    if (value == null) {
      removeHeader(_dio.options.headers, name);
    } else {
      _dio.options.headers[name] = value;
    }
  }

  /// Changes default timeouts for all subsequent requests.
  void updateTimeouts({
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) {
    final options = _dio.options;
    if (connectTimeout != null) options.connectTimeout = connectTimeout;
    if (receiveTimeout != null) options.receiveTimeout = receiveTimeout;
    if (sendTimeout != null) options.sendTimeout = sendTimeout;
  }

  /// Adds a custom interceptor (runs before the token interceptor).
  ///
  /// It is inserted after the custom interceptors already installed and
  /// before the [HeadersInterceptor]. Adding the same instance twice has no
  /// effect.
  void addInterceptor(Interceptor interceptor) {
    if (_customInterceptors.any((item) => identical(item, interceptor))) {
      return;
    }
    _customInterceptors.add(interceptor);
    final installed = _dio.interceptors;
    final anchor = installed.indexOf(_headersInterceptor);
    if (anchor < 0) {
      installed.add(interceptor);
    } else {
      installed.insert(anchor, interceptor);
    }
  }

  /// Removes an interceptor previously added with [addInterceptor] (or passed
  /// to the constructor).
  void removeInterceptor(Interceptor interceptor) {
    if (_customInterceptors.remove(interceptor)) {
      _dio.interceptors.remove(interceptor);
    }
  }

  /// Adds a dynamic header provider, evaluated after the existing ones.
  void addHeaderProvider(HeaderProvider provider) =>
      _headersInterceptor.addProvider(provider);

  /// Removes a header provider. Returns whether it was registered.
  bool removeHeaderProvider(HeaderProvider provider) =>
      _headersInterceptor.removeProvider(provider);

  /// Converts any [error] into a `Failure` with the configured
  /// [errorMapper]. Never throws.
  ///
  /// Handy for `guardResult(..., mapError: apiClient.mapError)`.
  Failure mapError(Object error, StackTrace stackTrace) {
    if (error is Failure) return error;
    try {
      return _errorMapper.map(error, stackTrace);
    } on Object catch (mapperError, mapperStackTrace) {
      _logger.warning(
        'The ApiErrorMapper threw ${mapperError.runtimeType} while mapping '
        '${error.runtimeType}.',
        stackTrace: mapperStackTrace,
      );
      return UnexpectedFailure.fromError(error, stackTrace);
    }
  }

  /// Sends a request with an arbitrary HTTP [method].
  ///
  /// The body is decoded with [decoder] when given, otherwise cast to [T]
  /// (`Map<String, dynamic>`, `List<dynamic>`, `String`, `void`, ...). A
  /// decoder error or a failed cast throws a `ParsingFailure`. Use
  /// [responseType] to receive plain text, bytes or a stream instead of JSON.
  Future<ApiResponse<T>> request<T>(
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, dynamic>? queryParameters,
    ApiRequestOptions options = const ApiRequestOptions(),
    ResponseDecoder<T>? decoder,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    ResponseType? responseType,
  }) async {
    _ensureOpen();
    final Response<dynamic> response;
    try {
      response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: _dioOptions(method, options, responseType: responseType),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
    return ApiResponse<T>(
      data: _decode<T>(response.data, decoder),
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      headers: _normalizeHeaders(response.headers),
      requestUri: response.realUri,
    );
  }

  /// Sends a GET request.
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    ApiRequestOptions options = const ApiRequestOptions(),
    ResponseDecoder<T>? decoder,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) =>
      request<T>(
        path,
        queryParameters: queryParameters,
        options: options,
        decoder: decoder,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );

  /// Sends a POST request.
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    ApiRequestOptions options = const ApiRequestOptions(),
    ResponseDecoder<T>? decoder,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) =>
      request<T>(
        path,
        method: 'POST',
        data: data,
        queryParameters: queryParameters,
        options: options,
        decoder: decoder,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );

  /// Sends a PUT request.
  Future<ApiResponse<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    ApiRequestOptions options = const ApiRequestOptions(),
    ResponseDecoder<T>? decoder,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) =>
      request<T>(
        path,
        method: 'PUT',
        data: data,
        queryParameters: queryParameters,
        options: options,
        decoder: decoder,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );

  /// Sends a PATCH request.
  Future<ApiResponse<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    ApiRequestOptions options = const ApiRequestOptions(),
    ResponseDecoder<T>? decoder,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) =>
      request<T>(
        path,
        method: 'PATCH',
        data: data,
        queryParameters: queryParameters,
        options: options,
        decoder: decoder,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );

  /// Sends a DELETE request.
  Future<ApiResponse<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    ApiRequestOptions options = const ApiRequestOptions(),
    ResponseDecoder<T>? decoder,
    CancelToken? cancelToken,
  }) =>
      request<T>(
        path,
        method: 'DELETE',
        data: data,
        queryParameters: queryParameters,
        options: options,
        decoder: decoder,
        cancelToken: cancelToken,
      );

  /// Uploads [files] (plus optional form [fields]) as `multipart/form-data`.
  ///
  /// See [buildUploadFormData] for how [fields] are encoded. Path based
  /// files are not supported on the web (an `UnsupportedFailure` is thrown).
  Future<ApiResponse<T>> upload<T>(
    String path, {
    required List<UploadFile> files,
    Map<String, Object?> fields = const <String, Object?>{},
    String method = 'POST',
    Map<String, dynamic>? queryParameters,
    ApiRequestOptions options = const ApiRequestOptions(),
    ResponseDecoder<T>? decoder,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    _ensureOpen();
    final FormData formData;
    try {
      formData = await buildUploadFormData(files: files, fields: fields);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
    return request<T>(
      path,
      method: method,
      data: formData,
      queryParameters: queryParameters,
      options: options,
      decoder: decoder,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
  }

  /// Downloads [path] to the file at [savePath] (not available on the web;
  /// use [downloadBytes] there).
  ///
  /// When [deleteOnError] is true, a partially written file is deleted if the
  /// download fails.
  Future<ApiResponse<void>> download(
    String path,
    String savePath, {
    Map<String, dynamic>? queryParameters,
    ApiRequestOptions options = const ApiRequestOptions(),
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    bool deleteOnError = true,
  }) async {
    _ensureOpen();
    if (kIsWeb) {
      throw const UnsupportedFailure(
        'Downloading to a file is not supported on the web. '
        'Use downloadBytes instead.',
      );
    }
    final Response<dynamic> response;
    try {
      response = await _dio.download(
        path,
        savePath,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
        deleteOnError: deleteOnError,
        options: _dioOptions('GET', options),
      );
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
    return ApiResponse<void>(
      data: null,
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      headers: _normalizeHeaders(response.headers),
      requestUri: response.realUri,
    );
  }

  /// Downloads [path] into memory.
  Future<ApiResponse<Uint8List>> downloadBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
    ApiRequestOptions options = const ApiRequestOptions(),
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) =>
      request<Uint8List>(
        path,
        queryParameters: queryParameters,
        options: options,
        decoder: _asBytes,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
        responseType: ResponseType.bytes,
      );

  /// Closes the client. Pending requests are cancelled when [force] is true.
  ///
  /// Subsequent calls throw a `Failure`. Calling [close] again has no effect.
  /// An adapter passed as `httpClientAdapter` is detached but not closed.
  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    if (!_ownsAdapter) _dio.httpClientAdapter = _DetachedHttpClientAdapter();
    _dio.close(force: force);
    _baseUrl.dispose();
  }

  void _ensureOpen() {
    if (_closed) {
      throw mapError(
        StateError('This ApiClient has been closed.'),
        StackTrace.current,
      );
    }
  }

  Options _dioOptions(
    String method,
    ApiRequestOptions options, {
    ResponseType? responseType,
  }) {
    final requestHeaders = options.headers;
    return Options(
      method: method.toUpperCase(),
      headers:
          requestHeaders.isEmpty ? null : <String, dynamic>{...requestHeaders},
      extra: <String, dynamic>{
        ...options.toExtra(),
        if (requestHeaders.isNotEmpty)
          requestHeaderNamesExtraKey: <String>[
            for (final name in requestHeaders.keys) name.toLowerCase(),
          ],
        if (options.connectTimeout != null)
          connectTimeoutExtraKey: options.connectTimeout,
      },
      contentType: options.contentType,
      sendTimeout: options.sendTimeout,
      receiveTimeout: options.receiveTimeout,
      responseType: responseType,
    );
  }

  T _decode<T>(Object? data, ResponseDecoder<T>? decoder) {
    try {
      if (decoder != null) return decoder(data);
      return data as T;
    } on Failure {
      rethrow;
    } on Object catch (error, stackTrace) {
      final failure = mapError(error, stackTrace);
      if (failure is ParsingFailure) throw failure;
      throw ParsingFailure(
        failure.message,
        code: failure.code,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Uint8List _asBytes(Object? data) {
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data == null) return Uint8List(0);
    throw FormatException(
      'Expected binary data but received ${data.runtimeType}.',
    );
  }

  static Map<String, List<String>> _normalizeHeaders(Headers headers) {
    final normalized = <String, List<String>>{};
    headers.forEach((name, values) {
      (normalized[name.toLowerCase()] ??= <String>[]).addAll(values);
    });
    return Map<String, List<String>>.unmodifiable(<String, List<String>>{
      for (final entry in normalized.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
  }

  /// Returns [baseUrl] when it is usable by Dio on the current platform.
  static String _checkBaseUrl(String baseUrl) {
    if (baseUrl.isEmpty || kIsWeb) return baseUrl;
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Must be an absolute URL such as https://api.example.com',
      );
    }
    return baseUrl;
  }
}

/// Applies per-request settings Dio cannot express through `Options` on
/// every supported version.
class _RequestTimeoutsInterceptor extends Interceptor {
  const _RequestTimeoutsInterceptor();

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final connectTimeout = options.extra[connectTimeoutExtraKey];
    if (connectTimeout is Duration) options.connectTimeout = connectTimeout;
    // Browsers cannot enforce a send timeout without a body; Dio warns about
    // it on every such request, so it is dropped there.
    if (kIsWeb && options.data == null) options.sendTimeout = null;
    handler.next(options);
  }
}

/// Replaces an injected adapter when the client is closed, so that closing
/// the client never closes shared infrastructure.
class _DetachedHttpClientAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      Future<ResponseBody>.error(StateError('This ApiClient has been closed.'));

  @override
  void close({bool force = false}) {}
}
