import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../networking/domain/api_request_options.dart';
import '../domain/api_call_form_data.dart';
import '../domain/api_call_record.dart';
import 'api_inspector.dart';

/// Dio interceptor that records every call into an [ApiInspector].
///
/// Requests whose `RequestOptions.extra[SymphonyRequestExtras.inspect]` is
/// `false` are ignored, as is everything while [ApiInspector.enabled] is
/// false.
///
/// * `onRequest` starts a call and stores its id in
///   `RequestOptions.extra[callIdExtraKey]` (see [callIdOf]).
/// * `onResponse` / `onError` complete or fail it. Request headers and the
///   URI are read again at that point, so values added by interceptors that
///   run after this one (for example `Authorization`) are shown — masked.
/// * Bodies: maps, lists, strings and numbers are redacted by the inspector;
///   `FormData` becomes its fields (redacted) plus file metadata;
///   `application/x-www-form-urlencoded` strings are parsed into fields;
///   byte lists become `[binary N bytes]` and streams `[stream]`.
///
/// The interceptor never throws and always forwards the request, response
/// or error to the next handler.
///
/// Placement: put it **before** interceptors that may resolve or reject a
/// call themselves (cache, retry, token refresh). A request resolved by an
/// earlier interceptor without calling the following response interceptors
/// stays pending in the inspector. When the same request is sent again (a
/// retry or a token refresh) while its previous attempt is still pending,
/// that attempt is closed with [retriedCallMessage].
class ApiInspectorInterceptor extends Interceptor {
  /// Creates an interceptor feeding [inspector].
  ApiInspectorInterceptor(
    this.inspector, {
    this.retriedCallMessage = defaultRetriedCallMessage,
  });

  /// Key of `RequestOptions.extra` holding the inspector call id.
  static const String callIdExtraKey = 'symphony.inspectorId';

  /// Default for [retriedCallMessage].
  static const String defaultRetriedCallMessage =
      'No response captured: the request was sent again (retry or token '
      'refresh) before this attempt completed.';

  /// Destination store.
  final ApiInspector inspector;

  /// Error recorded on an attempt superseded by a new attempt of the same
  /// request (see the class documentation).
  final String retriedCallMessage;

  // Fallback when `RequestOptions.extra` is unmodifiable.
  final Expando<int> _callIds = Expando<int>('symphony.inspectorId');

  /// The inspector call id stored in [options] by an
  /// [ApiInspectorInterceptor], or `null` when the request was not recorded.
  ///
  /// Use it with [ApiInspector.byId], for example to link an error shown to
  /// the user with its captured call.
  static int? callIdOf(RequestOptions options) {
    final value = options.extra[callIdExtraKey];
    return value is int ? value : null;
  }

  /// A readable description of [error]: its type, message and cause.
  static String describeError(DioException error) {
    final buffer = StringBuffer('[${error.type.name}]');
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      buffer
        ..write(' ')
        ..write(message);
    }
    final cause = error.error;
    if (cause != null) {
      final causeText = '$cause'.trim();
      if (causeText.isNotEmpty &&
          (message == null || !message.contains(causeText))) {
        buffer
          ..write(message == null || message.isEmpty ? ' ' : '\n')
          ..write(causeText);
      }
    }
    return buffer.toString();
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    try {
      _start(options);
    } on Object catch (error) {
      _debugReport(error);
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    try {
      final options = response.requestOptions;
      final id = _idOf(options);
      if (id != null) {
        inspector.completeCall(
          id,
          statusCode: response.statusCode,
          statusMessage: response.statusMessage,
          requestHeaders: options.headers,
          headers: response.headers.map,
          body:
              inspector.captureResponseBodies ? _responseBody(response) : null,
          uri: options.uri,
        );
      }
    } on Object catch (error) {
      _debugReport(error);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      final options = err.requestOptions;
      final id = _idOf(options);
      if (id != null) {
        final response = err.response;
        inspector.failCall(
          id,
          error: describeError(err),
          statusCode: response?.statusCode,
          statusMessage: response?.statusMessage,
          requestHeaders: options.headers,
          headers: response?.headers.map,
          body: response != null && inspector.captureResponseBodies
              ? _responseBody(response)
              : null,
          uri: options.uri,
        );
      }
    } on Object catch (error) {
      _debugReport(error);
    }
    handler.next(err);
  }

  void _start(RequestOptions options) {
    final previous = _idOf(options);
    if (previous != null) {
      final record = inspector.byId(previous);
      if (record != null && record.isPending) {
        inspector.failCall(
          previous,
          error: retriedCallMessage,
          requestHeaders: options.headers,
        );
      }
      _forget(options);
    }
    if (!inspector.enabled ||
        options.extra[SymphonyRequestExtras.inspect] == false) {
      return;
    }
    final id = inspector.startCall(
      method: options.method,
      uri: options.uri,
      headers: options.headers,
      body: inspector.captureRequestBodies ? _requestBody(options) : null,
    );
    if (id != null) _remember(options, id);
  }

  int? _idOf(RequestOptions options) => callIdOf(options) ?? _callIds[options];

  void _remember(RequestOptions options, int id) {
    _callIds[options] = id;
    try {
      options.extra[callIdExtraKey] = id;
    } on UnsupportedError {
      // Unmodifiable extra: the Expando keeps the id.
    }
  }

  void _forget(RequestOptions options) {
    _callIds[options] = null;
    try {
      options.extra.remove(callIdExtraKey);
    } on UnsupportedError {
      // Unmodifiable extra: nothing was stored there.
    }
  }

  static Object? _requestBody(RequestOptions options) {
    final data = options.data;
    if (data is FormData) return _formData(data);
    if (data is ResponseBody) return ApiCallRecord.streamBodyPlaceholder;
    if (data is String && _isUrlEncoded(options.contentType)) {
      return _parseUrlEncoded(data);
    }
    return data;
  }

  static Object? _responseBody(Response<dynamic> response) {
    final Object? data = response.data;
    if (data is ResponseBody) return ApiCallRecord.streamBodyPlaceholder;
    if (data is String) {
      final contentTypes = response.headers[Headers.contentTypeHeader];
      final contentType = contentTypes == null || contentTypes.isEmpty
          ? null
          : contentTypes.first;
      if (_isUrlEncoded(contentType)) return _parseUrlEncoded(data);
    }
    return data;
  }

  static ApiCallFormData _formData(FormData data) {
    return ApiCallFormData(
      fields: <MapEntry<String, String>>[
        for (final field in data.fields)
          MapEntry<String, String>(field.key, field.value),
      ],
      files: <ApiCallFormFile>[
        for (final file in data.files)
          ApiCallFormFile(
            field: file.key,
            filename: file.value.filename,
            length: file.value.length,
            contentType: file.value.contentType?.mimeType,
          ),
      ],
    );
  }

  static bool _isUrlEncoded(String? contentType) =>
      contentType != null &&
      contentType
          .trimLeft()
          .toLowerCase()
          .startsWith(Headers.formUrlEncodedContentType);

  /// Parses an `application/x-www-form-urlencoded` body into fields
  /// (repeated names become lists) so that the inspector can redact it.
  static Map<String, Object> _parseUrlEncoded(String body) {
    final fields = <String, Object>{};
    for (final pair in body.split('&')) {
      if (pair.isEmpty) continue;
      final separator = pair.indexOf('=');
      final key = _decodeComponent(
        separator < 0 ? pair : pair.substring(0, separator),
      );
      final value =
          separator < 0 ? '' : _decodeComponent(pair.substring(separator + 1));
      final existing = fields[key];
      if (existing == null) {
        fields[key] = value;
      } else if (existing is List<String>) {
        existing.add(value);
      } else {
        fields[key] = <String>[existing as String, value];
      }
    }
    return fields;
  }

  static String _decodeComponent(String component) {
    try {
      return Uri.decodeQueryComponent(component);
    } on ArgumentError {
      return component;
    } on FormatException {
      return component;
    }
  }

  static void _debugReport(Object error) {
    assert(() {
      debugPrint('ApiInspectorInterceptor ignored an internal error: $error');
      return true;
    }());
  }
}
