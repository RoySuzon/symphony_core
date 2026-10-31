// Internal helpers shared by the networking interceptors, `ApiClient` and the
// API inspector.
//
// This library is intentionally NOT exported by the networking barrel: its
// members are implementation details and may change at any time.
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../core/logging/log_redactor.dart';

const int _maxLoggableDepth = 32;

/// Converts [value] into plain JSON values (maps with string keys, lists,
/// strings, numbers, booleans and `null`) so that a [LogRedactor] can see,
/// and mask, every field.
///
/// Objects nested anywhere are converted through their `toJson()`, the way
/// Dio's JSON transformer sends them; values JSON cannot represent become
/// `'[TypeName]'`, so a custom `toString()` can never reach a log or the
/// inspector. Plain JSON (such as a decoded response body) is returned as
/// is, without being copied. Never throws.
Object? toLoggableJson(Object? value) =>
    _isPlainJson(value, 0) ? value : _loggable(value, 0);

bool _isPlainJson(Object? value, int depth) {
  if (value == null || value is String || value is num || value is bool) {
    return true;
  }
  if (depth >= _maxLoggableDepth) return false;
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String || !_isPlainJson(entry.value, depth + 1)) {
        return false;
      }
    }
    return true;
  }
  if (value is List) {
    for (final item in value) {
      if (!_isPlainJson(item, depth + 1)) return false;
    }
    return true;
  }
  return false;
}

Object? _loggable(Object? value, int depth) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (depth >= _maxLoggableDepth) return '[${value.runtimeType}]';
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        '${entry.key}': _loggable(entry.value, depth + 1),
    };
  }
  if (value is Iterable) {
    return <Object?>[for (final item in value) _loggable(item, depth + 1)];
  }
  final Object? json;
  try {
    json = jsonDecode(jsonEncode(value));
  } on Object {
    return '[${value.runtimeType}]';
  }
  return _loggable(json, depth + 1);
}

/// Returns [headers] with the value of every header named in [names]
/// (case-insensitive) replaced by [mask]; [headers] itself when none is
/// present.
Map<String, dynamic> maskHeaders(
  Map<String, dynamic> headers,
  Iterable<String> names,
  String mask,
) {
  final lowerNames = <String>{
    for (final name in names)
      if (name.trim().isNotEmpty) name.trim().toLowerCase(),
  };
  if (lowerNames.isEmpty ||
      !headers.keys.any((key) => lowerNames.contains(key.toLowerCase()))) {
    return headers;
  }
  return <String, dynamic>{
    for (final entry in headers.entries)
      entry.key:
          lowerNames.contains(entry.key.toLowerCase()) ? mask : entry.value,
  };
}

/// Returns [uri] safe for logs: sensitive query parameters are masked by
/// [redactor] and `user:password@` credentials are replaced by its mask.
Uri loggableUri(LogRedactor redactor, Uri uri) {
  final redacted = redactor.redactUri(uri);
  if (redacted.userInfo.isEmpty) return redacted;
  return redacted.replace(userInfo: redactor.mask);
}

/// [url] made safe for logs (see [loggableUri]); unparsable values are
/// replaced entirely by the redactor's mask.
String loggableUrl(LogRedactor redactor, String url) {
  final uri = Uri.tryParse(url);
  return uri == null ? redactor.mask : loggableUri(redactor, uri).toString();
}

/// `RequestOptions.extra` key holding the lower-cased names of the headers
/// passed explicitly for a single request (`ApiRequestOptions.headers`).
///
/// Header providers never override these headers.
const String requestHeaderNamesExtraKey =
    'symphony.internal.requestHeaderNames';

/// `RequestOptions.extra` key holding the per-request connect timeout
/// (`ApiRequestOptions.connectTimeout`).
const String connectTimeoutExtraKey = 'symphony.internal.connectTimeout';

/// Reads a `bool` stored in [extra] under [key], or [defaultValue] when the
/// value is missing or has another type.
bool readBoolExtra(
  Map<String, dynamic> extra,
  String key, {
  required bool defaultValue,
}) {
  final value = extra[key];
  return value is bool ? value : defaultValue;
}

/// Reads an `int` stored in [extra] under [key], or `null`.
int? readIntExtra(Map<String, dynamic> extra, String key) {
  final value = extra[key];
  return value is int ? value : null;
}

/// The lower-cased names of the per-request headers recorded by `ApiClient`.
Set<String> requestHeaderNames(Map<String, dynamic> extra) {
  final value = extra[requestHeaderNamesExtraKey];
  if (value is! Iterable) return const <String>{};
  return <String>{
    for (final name in value)
      if (name is String) name.toLowerCase(),
  };
}

/// Returns the value of header [name] in [headers] (case-insensitive), or
/// `null` when the header is absent.
Object? findHeader(Map<String, dynamic> headers, String name) {
  final lower = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}

/// Removes every header named [name] (case-insensitive) from [headers].
void removeHeader(Map<String, dynamic> headers, String name) {
  final lower = name.toLowerCase();
  headers.removeWhere((key, _) => key.toLowerCase() == lower);
}

/// Whether a request body can be sent a second time.
///
/// Streams can only be listened to once and are therefore never replayed.
bool isReplayableBody(Object? data) => data is! Stream;

/// Returns a body that can be sent again for a replayed request.
///
/// [FormData] can only be finalized once, so a clone is returned for it.
Object? replayableBody(Object? data) => data is FormData ? data.clone() : data;

const List<String> _connectionErrorMarkers = <String>[
  'socketexception',
  'handshakeexception',
  'tlsexception',
  'certificateexception',
  'httpexception',
  'clientexception',
  'connection refused',
  'connection reset',
  'connection closed',
  'connection aborted',
  'connection failed',
  'connection errored',
  'failed host lookup',
  'network is unreachable',
  'no route to host',
  'host is down',
  'software caused connection abort',
  'broken pipe',
  'xmlhttprequest',
];

/// Heuristically detects low level connectivity errors (socket, TLS
/// handshake, DNS...) without depending on `dart:io`, so the check also works
/// on the web.
bool looksLikeConnectionError(Object? error) {
  if (error == null || error is FormatException || error is TypeError) {
    return false;
  }
  String text;
  try {
    text = '${error.runtimeType} $error'.toLowerCase();
  } on Object {
    text = '${error.runtimeType}'.toLowerCase();
  }
  for (final marker in _connectionErrorMarkers) {
    if (text.contains(marker)) return true;
  }
  return false;
}
