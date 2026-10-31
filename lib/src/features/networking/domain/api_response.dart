import 'package:flutter/foundation.dart';

/// Typed result of a successful HTTP call made through `ApiClient`.
@immutable
class ApiResponse<T> {
  /// Creates a response.
  const ApiResponse({
    required this.data,
    this.statusCode,
    this.statusMessage,
    this.headers = const <String, List<String>>{},
    this.requestUri,
  });

  /// Decoded body.
  final T data;

  /// HTTP status code.
  final int? statusCode;

  /// HTTP status message.
  final String? statusMessage;

  /// Response headers (lower-cased names).
  final Map<String, List<String>> headers;

  /// Final URI of the request.
  final Uri? requestUri;

  /// Whether [statusCode] is in the 2xx range.
  bool get isSuccessful {
    final code = statusCode;
    return code != null && code >= 200 && code < 300;
  }

  /// First value of header [name] (case-insensitive), or `null`.
  String? header(String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower && entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  /// Returns a response with the same metadata and transformed [data].
  ApiResponse<R> map<R>(R Function(T data) transform) => ApiResponse<R>(
        data: transform(data),
        statusCode: statusCode,
        statusMessage: statusMessage,
        headers: headers,
        requestUri: requestUri,
      );

  /// Prints the status and the request URI without its user info, its
  /// fragment and its query values (`?token=***`), which may carry
  /// credentials.
  @override
  String toString() =>
      'ApiResponse<$T>(status: $statusCode, uri: ${_describe(requestUri)})';

  static String? _describe(Uri? uri) {
    if (uri == null) return null;
    final base = Uri(
      scheme: uri.scheme.isEmpty ? null : uri.scheme,
      host: uri.hasAuthority ? uri.host : null,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
    if (!uri.hasQuery) return base;
    try {
      final names = uri.queryParametersAll.keys
          .map((name) => '${Uri.encodeQueryComponent(name)}=***');
      return '$base?${names.join('&')}';
    } on Object {
      // Undecodable query (invalid percent-encoding): hide it entirely.
      return '$base?***';
    }
  }
}
