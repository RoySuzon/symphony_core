// Internal helpers shared by the networking interceptors and `ApiClient`.
//
// This library is intentionally NOT exported by the networking barrel: its
// members are implementation details and may change at any time.
import 'package:dio/dio.dart';

import '../../../../core/logging/log_redactor.dart';

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
