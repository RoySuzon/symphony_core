import 'package:flutter/foundation.dart';

import 'api_call_form_data.dart';

/// One HTTP call captured by the API inspector. All values are already
/// redacted and truncated.
@immutable
class ApiCallRecord {
  /// Creates a record.
  const ApiCallRecord({
    required this.id,
    required this.method,
    required this.uri,
    required this.startedAt,
    this.requestHeaders = const <String, String>{},
    this.requestBody,
    this.endedAt,
    this.statusCode,
    this.statusMessage,
    this.responseHeaders = const <String, String>{},
    this.responseBody,
    this.error,
    this.requestFormData,
  });

  /// Body text stored for streamed bodies, whose content is never captured.
  static const String streamBodyPlaceholder = '[stream]';

  /// Body text stored for a binary body of [length] bytes.
  static String binaryBodyPlaceholder(int length) => '[binary $length bytes]';

  static final RegExp _binaryPlaceholderPattern = RegExp(
    r'^\[binary \d+ bytes\]$',
  );

  /// Whether [body] is a placeholder standing for content that was not
  /// captured as text (see [streamBodyPlaceholder] and
  /// [binaryBodyPlaceholder]).
  static bool isBodyPlaceholder(String? body) =>
      body != null &&
      (body == streamBodyPlaceholder ||
          _binaryPlaceholderPattern.hasMatch(body));

  /// Unique, monotonically increasing identifier.
  final int id;

  /// HTTP method in upper case.
  final String method;

  /// Full request URI (sensitive query parameters masked).
  final Uri uri;

  /// When the request was sent.
  final DateTime startedAt;

  /// Redacted request headers.
  final Map<String, String> requestHeaders;

  /// Redacted, truncated request body.
  final String? requestBody;

  /// When the response or error was received.
  final DateTime? endedAt;

  /// HTTP status code, if a response was received.
  final int? statusCode;

  /// HTTP status message, if a response was received.
  final String? statusMessage;

  /// Redacted response headers.
  final Map<String, String> responseHeaders;

  /// Redacted, truncated response body.
  final String? responseBody;

  /// Error description when the call failed without (or with) a response.
  final String? error;

  /// Structured, redacted summary of a `multipart/form-data` request body
  /// (`null` for any other body). [requestBody] holds its display form.
  final ApiCallFormData? requestFormData;

  /// Whether the call is still in flight.
  bool get isPending => endedAt == null;

  /// Total duration of the call, once completed.
  Duration? get duration => endedAt?.difference(startedAt);

  /// Whether the call completed with a 2xx status and no error.
  bool get isSuccessful {
    final code = statusCode;
    return error == null && code != null && code >= 200 && code < 300;
  }

  /// Whether the call failed: an error was recorded (no response, timeout,
  /// cancellation, rejected status...) or the server answered with a status
  /// of 400 or more.
  bool get isError {
    final code = statusCode;
    return error != null || (code != null && code >= 400);
  }

  /// Path of [uri] (`/` when empty), without the query string.
  String get path => uri.path.isEmpty ? '/' : uri.path;

  /// Host of [uri], followed by the port when it is not the scheme default.
  String get host => uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

  /// Whether the call used a secure scheme (`https` or `wss`).
  bool get isSecure => uri.scheme == 'https' || uri.scheme == 'wss';

  /// Compact status: the status code when a response was received, `...`
  /// while the call is pending and `ERR` when it failed without a response.
  String get statusLabel {
    final code = statusCode;
    if (code != null) return '$code';
    return isPending ? '...' : 'ERR';
  }

  /// Human readable [duration] (e.g. `85 ms`, `1.24 s`, `2 min 5 s`), or
  /// `null` while the call is pending.
  String? get durationLabel {
    final value = duration;
    return value == null ? null : formatDuration(value);
  }

  /// [startedAt] formatted as `HH:mm:ss`.
  String get timeLabel =>
      '${_twoDigits(startedAt.hour)}:'
      '${_twoDigits(startedAt.minute)}:${_twoDigits(startedAt.second)}';

  /// `Content-Type` of the request, if known.
  String? get requestContentType => _header(requestHeaders, 'content-type');

  /// `Content-Type` of the response, if known.
  String? get responseContentType => _header(responseHeaders, 'content-type');

  /// Response size announced by the `Content-Length` header, if any.
  int? get responseContentLength {
    final value = _header(responseHeaders, 'content-length');
    return value == null ? null : int.tryParse(value.trim());
  }

  /// Formats [value] for display: `85 ms` below one second, `1.24 s` below
  /// one minute and `2 min 5 s` above.
  static String formatDuration(Duration value) {
    final micros = value.inMicroseconds;
    if (micros < Duration.microsecondsPerSecond) {
      final millis = micros <= 0 ? 0 : (micros / 1000).round();
      return '$millis ms';
    }
    if (micros < Duration.microsecondsPerMinute) {
      return '${(micros / Duration.microsecondsPerSecond).toStringAsFixed(2)} s';
    }
    final seconds = value.inSeconds;
    return '${seconds ~/ 60} min ${seconds % 60} s';
  }

  /// Formats a byte count for display: `512 B`, `1.5 KB`, `2.3 MB`.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = <String>['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final text =
        value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$text ${units[unit]}';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static String? _header(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields cannot be reset to `null` through this method.
  ApiCallRecord copyWith({
    int? id,
    String? method,
    Uri? uri,
    DateTime? startedAt,
    Map<String, String>? requestHeaders,
    String? requestBody,
    DateTime? endedAt,
    int? statusCode,
    String? statusMessage,
    Map<String, String>? responseHeaders,
    String? responseBody,
    String? error,
    ApiCallFormData? requestFormData,
  }) {
    return ApiCallRecord(
      id: id ?? this.id,
      method: method ?? this.method,
      uri: uri ?? this.uri,
      startedAt: startedAt ?? this.startedAt,
      requestHeaders: requestHeaders ?? this.requestHeaders,
      requestBody: requestBody ?? this.requestBody,
      endedAt: endedAt ?? this.endedAt,
      statusCode: statusCode ?? this.statusCode,
      statusMessage: statusMessage ?? this.statusMessage,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      responseBody: responseBody ?? this.responseBody,
      error: error ?? this.error,
      requestFormData: requestFormData ?? this.requestFormData,
    );
  }

  @override
  String toString() => 'ApiCallRecord(#$id $method $uri $statusLabel)';
}
