import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:symphony_core/src/core/config/symphony_config.dart';
import 'package:symphony_core/src/core/logging/log_level.dart';
import 'package:symphony_core/src/core/logging/symphony_logger.dart';
import 'package:symphony_core/src/features/networking/networking.dart';

/// Base URL used by the networking tests.
const String testBaseUrl = 'https://api.example.com';

/// A configuration with instant retries, suitable for tests.
SymphonyConfig testConfig({
  String baseUrl = testBaseUrl,
  int maxRetries = 0,
  bool enableLogging = false,
  bool enableInspector = false,
  String authTokenPrefix = 'Bearer',
  String authHeaderName = 'Authorization',
  Set<int> refreshTokenStatusCodes = const <int>{401},
  Map<String, String> defaultHeaders = const <String, String>{},
  int maxLoggedBodyLength = 4000,
}) => SymphonyConfig(
  baseUrl: baseUrl,
  maxRetries: maxRetries,
  retryDelay: Duration.zero,
  enableLogging: enableLogging,
  enableInspector: enableInspector,
  authTokenPrefix: authTokenPrefix,
  authHeaderName: authHeaderName,
  refreshTokenStatusCodes: refreshTokenStatusCodes,
  defaultHeaders: defaultHeaders,
  maxLoggedBodyLength: maxLoggedBodyLength,
);

/// A JSON response body.
ResponseBody jsonBody(
  Object? data, {
  int statusCode = 200,
  Map<String, List<String>> headers = const <String, List<String>>{},
}) => ResponseBody.fromString(
  jsonEncode(data),
  statusCode,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    ...headers,
  },
);

/// Produces the response for a request received by [FakeHttpClientAdapter].
typedef FakeResponder =
    FutureOr<ResponseBody> Function(RequestOptions options, List<int> body);

/// An in-memory [HttpClientAdapter] recording every request.
class FakeHttpClientAdapter implements HttpClientAdapter {
  /// Creates an adapter answering with [responder] (`{}` / 200 by default).
  FakeHttpClientAdapter([FakeResponder? responder])
    : responder = responder ?? ((_, _) => jsonBody(<String, Object?>{}));

  /// Produces the responses.
  FakeResponder responder;

  /// Every request received, in order.
  final List<RequestOptions> requests = <RequestOptions>[];

  /// The raw body of every request received, in order.
  final List<List<int>> bodies = <List<int>>[];

  /// Whether [close] was called.
  bool closed = false;

  /// Value of header [name] of the request at [index] (case-insensitive).
  Object? headerOf(int index, String name) {
    final lower = name.toLowerCase();
    for (final entry in requests[index].headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        body.addAll(chunk);
      }
    }
    bodies.add(body);
    return responder(options, body);
  }

  @override
  void close({bool force = false}) => closed = true;
}

/// An [AuthTokenDelegate] whose behaviour is controlled by the test.
class FakeTokenDelegate extends AuthTokenDelegate {
  /// Creates a delegate returning [token] and refreshing to [refreshedToken].
  FakeTokenDelegate({
    this.token,
    this.refreshedToken,
    this.onRefresh,
    this.onExpired,
  });

  /// The current access token.
  String? token;

  /// The token produced by [refreshAccessToken] (when [onRefresh] is null).
  String? refreshedToken;

  /// Custom refresh behaviour; its result becomes the new token.
  Future<String?> Function()? onRefresh;

  /// Custom session expiry behaviour.
  Future<void> Function()? onExpired;

  /// When set, [refreshAccessToken] waits for it before completing.
  Completer<void>? refreshGate;

  /// Number of [refreshAccessToken] calls.
  int refreshCalls = 0;

  /// Number of [onSessionExpired] calls.
  int expiredCalls = 0;

  @override
  Future<String?> getAccessToken() async => token;

  @override
  Future<String?> refreshAccessToken() async {
    refreshCalls++;
    final gate = refreshGate;
    if (gate != null) await gate.future;
    final custom = onRefresh;
    final next = custom != null ? await custom() : refreshedToken;
    token = next;
    return next;
  }

  @override
  Future<void> onSessionExpired() async {
    expiredCalls++;
    token = null;
    final custom = onExpired;
    if (custom != null) await custom();
  }
}

/// A [LogSink] keeping every entry in memory.
class CapturingLogSink extends LogSink {
  /// Captured entries.
  final List<LogEntry> entries = <LogEntry>[];

  /// Every entry rendered as text.
  String get text => entries.map((entry) => entry.toString()).join('\n');

  @override
  void write(LogEntry entry) => entries.add(entry);
}

/// A logger writing every level to [sink].
SymphonyLogger capturingLogger(CapturingLogSink sink, {String tag = 'HTTP'}) =>
    SymphonyLogger(
      tag: tag,
      minLevel: LogLevel.verbose,
      sinks: <LogSink>[sink],
    );

/// An exception whose string form mimics `dart:io`'s `SocketException`.
class FakeSocketException implements Exception {
  /// Creates the exception.
  const FakeSocketException([this.message = 'Connection refused']);

  /// Error message.
  final String message;

  @override
  String toString() => 'SocketException: $message';
}
