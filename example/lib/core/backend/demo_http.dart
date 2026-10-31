import 'dart:convert';
import 'dart:typed_data';

import 'package:symphony_core/symphony_core.dart';

import 'demo_multipart.dart';

/// An HTTP request as received by the in-process demo backend.
///
/// Built from the Dio [RequestOptions] and the raw body bytes that Dio
/// streamed to the adapter, exactly like a real server would see them.
class DemoRequest {
  /// Creates a request.
  DemoRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  /// Converts what Dio hands to an `HttpClientAdapter` into a request.
  factory DemoRequest.fromOptions(RequestOptions options, Uint8List body) {
    final headers = <String, String>{};
    options.headers.forEach((String name, dynamic value) {
      if (value == null) return;
      headers[name.toLowerCase()] =
          value is Iterable ? value.join(', ') : '$value';
    });
    final contentType = options.contentType;
    if (contentType != null) {
      headers.putIfAbsent('content-type', () => contentType);
    }
    return DemoRequest(
      method: options.method.toUpperCase(),
      uri: options.uri,
      headers: headers,
      body: body,
    );
  }

  /// Upper-case HTTP method.
  final String method;

  /// Full request URI (any host is accepted).
  final Uri uri;

  /// Request headers with lower-case names.
  final Map<String, String> headers;

  /// Raw request body.
  final Uint8List body;

  /// Values captured by `:name` segments of the matched route.
  Map<String, String> pathParameters = const <String, String>{};

  Map<String, Object?>? _json;
  List<DemoMultipartPart>? _parts;

  /// Request path.
  String get path => uri.path;

  /// Host the client believes it talks to (see `ApiClient.updateBaseUrl`).
  String get host => uri.hasPort && !_isDefaultPort(uri)
      ? '${uri.host}:${uri.port}'
      : uri.host;

  /// Header [name] (case-insensitive), or `null`.
  String? header(String name) => headers[name.toLowerCase()];

  /// Query parameter [name], or `null`.
  String? query(String name) => uri.queryParameters[name];

  /// The JSON object sent as body (an empty map when there is none).
  Map<String, Object?> get json => _json ??= _decodeJson();

  /// String field [name] of the JSON body, trimmed; `null` when blank.
  String? field(String name) {
    final value = json[name];
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  /// The parts of a `multipart/form-data` body (empty for other bodies).
  List<DemoMultipartPart> get multipart => _parts ??= _decodeMultipart();

  Map<String, Object?> _decodeJson() {
    if (body.isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is Map) {
        return <String, Object?>{
          for (final entry in decoded.entries) '${entry.key}': entry.value,
        };
      }
    } on FormatException {
      // Not JSON: handlers validate the fields they need.
    }
    return const <String, Object?>{};
  }

  List<DemoMultipartPart> _decodeMultipart() {
    final boundary = multipartBoundary(header('content-type'));
    if (boundary == null) return const <DemoMultipartPart>[];
    return parseMultipart(body, boundary);
  }

  static bool _isDefaultPort(Uri uri) =>
      (uri.scheme == 'https' && uri.port == 443) ||
      (uri.scheme == 'http' && uri.port == 80);
}

/// A response produced by the demo backend.
class DemoResponse {
  /// Creates a response with a raw [body].
  DemoResponse(
    this.statusCode, {
    required this.body,
    this.contentType,
    this.headers = const <String, String>{},
    this.simulateTransfer = false,
  });

  /// A JSON response.
  factory DemoResponse.json(
    int statusCode,
    Object? json, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return DemoResponse(
      statusCode,
      body: Uint8List.fromList(utf8.encode(jsonEncode(json))),
      contentType: 'application/json; charset=utf-8',
      headers: headers,
    );
  }

  /// A successful response wrapped in the backend's envelope:
  /// `{"status": "ok", "result": ...}`.
  factory DemoResponse.ok(Object? result, {int statusCode = 200}) =>
      DemoResponse.json(
        statusCode,
        <String, Object?>{'status': 'ok', 'result': result},
      );

  /// An empty `204 No Content` response.
  factory DemoResponse.noContent() => DemoResponse(204, body: Uint8List(0));

  /// A binary download, streamed in chunks to simulate the network.
  factory DemoResponse.file(
    Uint8List bytes, {
    required String contentType,
    required String filename,
  }) {
    return DemoResponse(
      200,
      body: bytes,
      contentType: contentType,
      headers: <String, String>{
        'content-disposition': 'attachment; filename="$filename"',
      },
      simulateTransfer: true,
    );
  }

  /// HTTP status code.
  final int statusCode;

  /// Raw body.
  final Uint8List body;

  /// `Content-Type` header value.
  final String? contentType;

  /// Additional headers (lower-case names).
  final Map<String, String> headers;

  /// Whether the body is streamed slowly (downloads), so that receive
  /// progress is visible.
  final bool simulateTransfer;
}

/// Thrown by request handlers to answer with an error response:
/// `{"status": "error", "error": {"code": ..., "message": ...}}` plus
/// optional field errors under `errors`.
class DemoHttpException implements Exception {
  /// Creates an error response description.
  const DemoHttpException(
    this.statusCode,
    this.code,
    this.message, {
    this.fieldErrors,
    this.headers = const <String, String>{},
  });

  /// `400 Bad Request`.
  const DemoHttpException.badRequest(String message)
      : this(400, 'bad_request', message);

  /// `401 Unauthorized` with a `WWW-Authenticate` challenge.
  const DemoHttpException.unauthorized(String code, String message)
      : this(
          401,
          code,
          message,
          headers: const <String, String>{
            'www-authenticate': 'Bearer realm="symphony-demo"',
          },
        );

  /// `403 Forbidden`.
  const DemoHttpException.forbidden(String message)
      : this(403, 'forbidden', message);

  /// `404 Not Found`.
  const DemoHttpException.notFound(String message)
      : this(404, 'not_found', message);

  /// `422 Unprocessable Entity` with per-field messages.
  const DemoHttpException.validation(
    String message,
    Map<String, List<String>> fieldErrors,
  ) : this(422, 'validation_failed', message, fieldErrors: fieldErrors);

  /// HTTP status code.
  final int statusCode;

  /// Machine readable error code.
  final String code;

  /// Human readable message.
  final String message;

  /// Messages per request field, for validation errors.
  final Map<String, List<String>>? fieldErrors;

  /// Additional response headers.
  final Map<String, String> headers;

  /// The response sent to the client.
  DemoResponse toResponse() {
    final errors = fieldErrors;
    return DemoResponse.json(
      statusCode,
      <String, Object?>{
        'status': 'error',
        'error': <String, Object?>{'code': code, 'message': message},
        if (errors != null) 'errors': errors,
      },
      headers: headers,
    );
  }

  @override
  String toString() => 'DemoHttpException($statusCode $code: $message)';
}

/// One request handled by the demo backend (see `DemoBackend.requestLog`).
class DemoRequestRecord {
  /// Creates a record.
  const DemoRequestRecord({
    required this.method,
    required this.path,
    required this.statusCode,
    required this.at,
    this.errorCode,
  });

  /// HTTP method.
  final String method;

  /// Request path.
  final String path;

  /// Response status code (`0` for a simulated network failure).
  final int statusCode;

  /// Error code of an error response, if any.
  final String? errorCode;

  /// When the request was handled (backend clock).
  final DateTime at;

  @override
  String toString() => '$method $path → $statusCode'
      '${errorCode == null ? '' : ' ($errorCode)'}';
}
