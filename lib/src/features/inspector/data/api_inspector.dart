import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/logging/log_redactor.dart';
import '../../networking/data/interceptors/interceptor_support.dart';
import '../domain/api_call_form_data.dart';
import '../domain/api_call_record.dart';

/// In-memory store of captured HTTP calls, observed by the inspector UI.
///
/// Calls go through a small lifecycle, normally driven by
/// `ApiInspectorInterceptor`:
///
/// 1. [startCall] records the request and returns its id,
/// 2. [completeCall] (a response was received) or [failCall] (an error
///    occurred) finishes it.
///
/// Everything is redacted **before** it is stored: headers with
/// [LogRedactor.redactHeaders], the URI with [LogRedactor.redactUri] (plus
/// masked user info), bodies with [LogRedactor.stringify] (truncated to
/// [maxBodyLength]) and free text (non-JSON bodies, error messages) by
/// masking URLs, `key=value` / `"key": "value"` pairs of sensitive keys and
/// `Bearer`/`Basic` credentials. Records are kept newest first and trimmed
/// to [maxEntries].
///
/// Listeners are notified after every change. Calls made after [dispose]
/// are ignored, so in-flight requests never throw.
///
/// ```dart
/// final inspector = ApiInspector(maxEntries: 100);
/// final id = inspector.startCall(method: 'GET', uri: Uri.parse('https://api.example.com/me'));
/// if (id != null) inspector.completeCall(id, statusCode: 200, body: {'name': 'Ada'});
/// ```
class ApiInspector extends ChangeNotifier {
  /// Creates an inspector keeping at most [maxEntries] calls.
  ///
  /// When [enabled] is false nothing is recorded until [enabled] is set to
  /// true. [clock] (defaults to [DateTime.now]) timestamps the calls; inject
  /// one in tests for deterministic durations.
  ApiInspector({
    this.maxEntries = 200,
    this.redactor = const LogRedactor(),
    this.maxBodyLength = 4000,
    this.captureRequestBodies = true,
    this.captureResponseBodies = true,
    bool enabled = true,
    DateTime Function()? clock,
  }) : assert(maxEntries > 0, 'maxEntries must be > 0'),
       _enabled = enabled,
       _clock = clock ?? DateTime.now,
       _text = _TextRedactor(redactor);

  /// Maximum number of calls kept (oldest are dropped first).
  final int maxEntries;

  /// Redactor applied to headers, query parameters and bodies.
  final LogRedactor redactor;

  /// Bodies longer than this are truncated.
  final int maxBodyLength;

  /// Whether request bodies are captured.
  final bool captureRequestBodies;

  /// Whether response bodies are captured.
  final bool captureResponseBodies;

  final DateTime Function() _clock;
  final _TextRedactor _text;
  final List<ApiCallRecord> _calls = <ApiCallRecord>[];
  List<ApiCallRecord>? _snapshot;
  int _nextId = 1;
  bool _enabled;
  bool _disposed = false;

  /// Whether new calls are recorded.
  ///
  /// Turning it off stops [startCall] from recording (it returns `null`);
  /// calls already in flight still complete. Listeners are notified when the
  /// value changes.
  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value || _disposed) return;
    _enabled = value;
    _notify();
  }

  /// Captured calls, newest first.
  ///
  /// The returned list is an unmodifiable snapshot: it does not change when
  /// new calls are recorded.
  List<ApiCallRecord> get calls =>
      _snapshot ??= List<ApiCallRecord>.unmodifiable(_calls);

  /// Number of calls still waiting for a response.
  int get pendingCount => _calls.where((call) => call.isPending).length;

  /// Number of failed calls (see [ApiCallRecord.isError]).
  int get errorCount => _calls.where((call) => call.isError).length;

  /// The call with the given [id], or `null` when it is unknown or was
  /// dropped (trimmed or cleared).
  ApiCallRecord? byId(int id) {
    for (final call in _calls) {
      if (call.id == id) return call;
    }
    return null;
  }

  /// Records a new request and returns its id, or `null` when the inspector
  /// is disabled or disposed.
  ///
  /// [body] may be a `Map`, a `List`, a `String` (JSON strings are decoded
  /// and pretty-printed), a number, a `List<int>` (rendered
  /// `[binary N bytes]`), a `Stream` (rendered `[stream]`) or an
  /// [ApiCallFormData]. It is ignored when [captureRequestBodies] is false.
  int? startCall({
    required String method,
    required Uri uri,
    Map<String, dynamic> headers = const <String, dynamic>{},
    Object? body,
  }) {
    if (!_enabled || _disposed) return null;
    final id = _nextId++;
    final trimmedMethod = method.trim();
    final formData =
        captureRequestBodies && body is ApiCallFormData
            ? _storedFormData(body)
            : null;
    _calls.insert(
      0,
      ApiCallRecord(
        id: id,
        method: trimmedMethod.isEmpty ? 'GET' : trimmedMethod.toUpperCase(),
        uri: _redactUri(uri),
        startedAt: _clock(),
        requestHeaders: _redactHeaders(headers),
        requestBody:
            captureRequestBodies
                ? _renderBody(formData?.toSummary() ?? body)
                : null,
        requestFormData: formData,
      ),
    );
    while (_calls.length > maxEntries) {
      _calls.removeLast();
    }
    _changed();
    return id;
  }

  /// Completes call [id] with a response.
  ///
  /// [requestHeaders] and [uri], when given, replace the values captured by
  /// [startCall] (headers or query parameters added by later interceptors,
  /// such as `Authorization`, then appear — redacted). [headers] and [body]
  /// are the response headers and body; [body] is ignored when
  /// [captureResponseBodies] is false.
  ///
  /// Unknown ids and calls that are no longer pending are ignored.
  void completeCall(
    int id, {
    int? statusCode,
    String? statusMessage,
    Map<String, dynamic>? requestHeaders,
    Map<String, dynamic> headers = const <String, dynamic>{},
    Object? body,
    Uri? uri,
  }) {
    _finish(
      id,
      (call) => ApiCallRecord(
        id: call.id,
        method: call.method,
        uri: uri == null ? call.uri : _redactUri(uri),
        startedAt: call.startedAt,
        requestHeaders:
            requestHeaders == null
                ? call.requestHeaders
                : _redactHeaders(requestHeaders),
        requestBody: call.requestBody,
        requestFormData: call.requestFormData,
        endedAt: _clock(),
        statusCode: statusCode,
        statusMessage: statusMessage,
        responseHeaders: _redactHeaders(headers),
        responseBody: captureResponseBodies ? _renderBody(body) : null,
      ),
    );
  }

  /// Marks call [id] as failed with the [error] description.
  ///
  /// [statusCode], [statusMessage], [headers] and [body] describe the
  /// response when the server answered (e.g. a 4xx/5xx rejected by the
  /// client). [requestHeaders] and [uri] behave as in [completeCall]. The
  /// error text is redacted (URLs, credentials and sensitive `key=value`
  /// pairs are masked).
  ///
  /// Unknown ids and calls that are no longer pending are ignored.
  void failCall(
    int id, {
    required String error,
    int? statusCode,
    String? statusMessage,
    Map<String, dynamic>? requestHeaders,
    Map<String, dynamic>? headers,
    Object? body,
    Uri? uri,
  }) {
    _finish(
      id,
      (call) => ApiCallRecord(
        id: call.id,
        method: call.method,
        uri: uri == null ? call.uri : _redactUri(uri),
        startedAt: call.startedAt,
        requestHeaders:
            requestHeaders == null
                ? call.requestHeaders
                : _redactHeaders(requestHeaders),
        requestBody: call.requestBody,
        requestFormData: call.requestFormData,
        endedAt: _clock(),
        statusCode: statusCode,
        statusMessage: statusMessage,
        responseHeaders:
            headers == null
                ? const <String, String>{}
                : _redactHeaders(headers),
        responseBody: captureResponseBodies ? _renderBody(body) : null,
        error: _text.redact(error, maxLength: maxBodyLength),
      ),
    );
  }

  /// Removes every captured call.
  ///
  /// Ids are never reused, so calls still in flight are simply ignored when
  /// they complete.
  void clear() {
    if (_calls.isEmpty) return;
    _calls.clear();
    _changed();
  }

  @override
  void addListener(VoidCallback listener) {
    // Late subscribers of a disposed inspector are ignored instead of
    // failing an assertion.
    if (_disposed) return;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_disposed) return;
    super.removeListener(listener);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  void _finish(int id, ApiCallRecord Function(ApiCallRecord call) update) {
    if (_disposed) return;
    final index = _calls.indexWhere((call) => call.id == id);
    if (index < 0 || !_calls[index].isPending) return;
    _calls[index] = update(_calls[index]);
    _changed();
  }

  void _changed() {
    _snapshot = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Map<String, String> _redactHeaders(Map<String, dynamic> headers) =>
      Map<String, String>.unmodifiable(redactor.redactHeaders(headers));

  Uri _redactUri(Uri uri) => _text.redactUri(uri);

  /// [body] redacted, with every field value truncated to [maxBodyLength] so
  /// that a record never holds an unbounded multipart field.
  ApiCallFormData _storedFormData(ApiCallFormData body) {
    final redacted = body.redact(redactor);
    return ApiCallFormData(
      fields: List<MapEntry<String, String>>.unmodifiable(
        <MapEntry<String, String>>[
          for (final field in redacted.fields)
            MapEntry<String, String>(field.key, _truncate(field.value)),
        ],
      ),
      files: redacted.files,
    );
  }

  String _truncate(String text) {
    final max = maxBodyLength;
    if (max < 0 || text.length <= max) return text;
    return '${text.substring(0, max)}… [truncated ${text.length - max} chars]';
  }

  String? _renderBody(Object? body) {
    final String text;
    try {
      text = _render(body);
    } on Object {
      return '[${body.runtimeType}]';
    }
    return text.isEmpty ? null : text;
  }

  String _render(Object? body) {
    if (body == null) return '';
    if (body is ApiCallFormData) {
      return redactor.stringify(
        body.redact(redactor).toSummary(),
        maxLength: maxBodyLength,
      );
    }
    if (body is List<int>) {
      return ApiCallRecord.binaryBodyPlaceholder(body.length);
    }
    if (body is Stream<Object?>) return ApiCallRecord.streamBodyPlaceholder;
    if (body is String) {
      final decoded = _decodeJson(body);
      if (decoded != null) {
        return redactor.stringify(decoded, maxLength: maxBodyLength);
      }
      return _text.redact(body, maxLength: maxBodyLength);
    }
    // Maps, lists and objects exposing `toJson()` (also when nested) are
    // rendered like Dio's JSON transformer would send them, so the redactor
    // sees every field; anything else is reduced to its type name so that a
    // custom `toString()` can never leak a secret.
    return redactor.stringify(toLoggableJson(body), maxLength: maxBodyLength);
  }

  static Object? _decodeJson(String body) {
    final trimmed = body.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}

/// Redacts free text (non-JSON bodies, error messages) and URIs.
class _TextRedactor {
  _TextRedactor(this.redactor);

  final LogRedactor redactor;

  static final RegExp _url = RegExp(
    r'''\b[A-Za-z][A-Za-z0-9+.\-]*://[^\s'"<>`]+''',
  );
  // Credentials are long opaque strings; the minimum length keeps ordinary
  // prose such as "Basic auth" readable.
  static final RegExp _credentials = RegExp(
    r'\b(Bearer|Basic|Digest)(\s+)[A-Za-z0-9\-._~+/]{12,}=*',
    caseSensitive: false,
  );
  static final RegExp _pair = RegExp(
    r'''(["']?)([A-Za-z_][\w\-.]*)\1(\s*[:=]\s*)("(?:[^"\\]|\\.)*"|'[^']*'|[^\s,;&"'<>{}\[\]()]+)''',
  );

  String redact(String text, {int? maxLength}) {
    var source = text;
    var truncated = 0;
    if (maxLength != null && maxLength >= 0 && source.length > maxLength) {
      // Every pattern is local, so redacting the kept prefix is safe: a
      // secret cut in half is still masked.
      truncated = source.length - maxLength;
      source = source.substring(0, maxLength);
    }
    var result = source.replaceAllMapped(_url, (match) {
      final raw = match[0]!;
      final uri = Uri.tryParse(raw);
      return uri == null ? raw : redactUri(uri).toString();
    });
    result = result.replaceAllMapped(
      _credentials,
      (match) => '${match[1]}${match[2]}${redactor.mask}',
    );
    result = result.replaceAllMapped(_pair, (match) {
      final key = match[2]!;
      if (!redactor.isSensitive(key)) return match[0]!;
      final value = match[4]!;
      final quote =
          value.startsWith('"')
              ? '"'
              : value.startsWith("'")
              ? "'"
              : '';
      final keyQuote = match[1]!;
      return '$keyQuote$key$keyQuote${match[3]}$quote${redactor.mask}$quote';
    });
    return truncated > 0 ? '$result… [truncated $truncated chars]' : result;
  }

  /// Masks sensitive query parameters (keeping the mask readable instead of
  /// percent-encoded) and any user info.
  Uri redactUri(Uri uri) {
    var result = uri;
    if (result.userInfo.isNotEmpty) {
      result = result.replace(userInfo: redactor.mask);
    }
    if (!result.hasQuery) return result;
    try {
      final redacted = redactor.redactUri(result);
      if (identical(redacted, result)) return result;
      final encodedMask = Uri.encodeQueryComponent(redactor.mask);
      if (encodedMask == redactor.mask) return redacted;
      return redacted.replace(
        query: redacted.query.replaceAll(encodedMask, redactor.mask),
      );
    } on FormatException {
      // The query cannot be decoded, hence cannot be checked: hide it.
      return result.replace(query: redactor.mask);
    } on ArgumentError {
      return result.replace(query: redactor.mask);
    }
  }
}
