import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/config/symphony_config.dart';
import '../../../../core/logging/log_level.dart';
import '../../../../core/logging/log_redactor.dart';
import '../../../../core/logging/symphony_logger.dart';
import '../../domain/api_request_options.dart';
import 'interceptor_support.dart';

/// Writes HTTP traffic to a [SymphonyLogger] without leaking secrets.
///
/// Every value passes through [redactor] first: sensitive headers
/// (`Authorization`, cookies, API keys...), query parameters and JSON /
/// form fields (passwords, tokens...) are masked. Multipart bodies are
/// summarised by field and file names only, binary bodies by their size, and
/// long bodies are truncated to [maxBodyLength] characters. Underlying error
/// objects are logged by type only, because their messages may contain
/// response bodies or credentials.
///
/// Output (one log entry per event):
///
/// ```text
/// --> POST https://api.example.com/login?api_key=***
/// headers:
///   content-type: application/json
/// body: {"email": "jane@example.com", "password": "***"}
/// <-- 200 POST https://api.example.com/login (123 ms)
/// ```
///
/// Requests whose `ApiRequestOptions.log` is `false` are not logged.
class SecureLoggingInterceptor extends Interceptor {
  /// Creates a logging interceptor writing to [logger].
  SecureLoggingInterceptor({
    required this.logger,
    this.redactor = const LogRedactor(),
    this.logHeaders = true,
    this.logRequestBodies = true,
    this.logResponseBodies = true,
    this.maxBodyLength = 4000,
    this.tag = 'HTTP',
    this.requestLevel = LogLevel.debug,
    this.responseLevel = LogLevel.debug,
    this.errorLevel = LogLevel.warning,
  });

  /// Creates a logging interceptor configured from [config]
  /// (`sensitiveKeys`, `logRequestBodies`, `logResponseBodies` and
  /// `maxLoggedBodyLength`).
  factory SecureLoggingInterceptor.fromConfig(
    SymphonyConfig config, {
    required SymphonyLogger logger,
    String tag = 'HTTP',
  }) =>
      SecureLoggingInterceptor(
        logger: logger,
        redactor: config.redactor,
        logRequestBodies: config.logRequestBodies,
        logResponseBodies: config.logResponseBodies,
        maxBodyLength: config.maxLoggedBodyLength,
        tag: tag,
      );

  /// Destination logger.
  final SymphonyLogger logger;

  /// Masks sensitive values before they are written.
  final LogRedactor redactor;

  /// Whether request and response headers are written.
  final bool logHeaders;

  /// Whether request bodies are written.
  final bool logRequestBodies;

  /// Whether response bodies are written.
  final bool logResponseBodies;

  /// Bodies longer than this many characters are truncated.
  final int maxBodyLength;

  /// Tag of the written log entries.
  final String tag;

  /// Level of outgoing request entries (and of cancelled requests).
  final LogLevel requestLevel;

  /// Level of successful response entries.
  final LogLevel responseLevel;

  /// Level of failed request entries.
  final LogLevel errorLevel;

  static const String _startedAtKey = 'symphony.internal.logStartedAt';
  static final RegExp _urlEncodedPattern =
      RegExp(r'^[\w.~%+\-\[\]]+=[^&\s]*(&[\w.~%+\-\[\]]+=[^&\s]*)*$');

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (_loggingAllowed(options)) {
      try {
        options.extra[_startedAtKey] = DateTime.now().microsecondsSinceEpoch;
      } on UnsupportedError {
        // `extra` was replaced by an unmodifiable map: log without duration.
      }
      if (logger.isEnabledFor(requestLevel)) {
        _write(requestLevel, () => _describeRequest(options));
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final options = response.requestOptions;
    if (_loggingAllowed(options) && logger.isEnabledFor(responseLevel)) {
      _write(responseLevel, () => _describeResponse(response));
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final level =
        err.type == DioExceptionType.cancel ? requestLevel : errorLevel;
    if (_loggingAllowed(err.requestOptions) && logger.isEnabledFor(level)) {
      _write(level, () => _describeError(err));
    }
    handler.next(err);
  }

  bool _loggingAllowed(RequestOptions options) => readBoolExtra(
        options.extra,
        SymphonyRequestExtras.log,
        defaultValue: true,
      );

  void _write(LogLevel level, String Function() message) {
    try {
      logger.log(level, message(), tag: tag);
    } on Object catch (error) {
      // Logging must never break a request.
      logger.log(
        LogLevel.warning,
        'Could not log an HTTP event (${error.runtimeType}).',
        tag: tag,
      );
    }
  }

  String _describeRequest(RequestOptions options) {
    final buffer = StringBuffer('--> ${_requestLine(options)}');
    final note = _attemptNote(options.extra);
    if (note != null) buffer.write(' ($note)');
    if (logHeaders) _writeHeaders(buffer, options.headers);
    if (logRequestBodies) {
      _writeBody(buffer, options.data, options.contentType);
    }
    return buffer.toString();
  }

  String _describeResponse(Response<dynamic> response) {
    final options = response.requestOptions;
    final buffer = StringBuffer(
      '<-- ${response.statusCode ?? '-'} ${_requestLine(options)}'
      '${_elapsed(options)}',
    );
    if (logHeaders) _writeHeaders(buffer, response.headers.map);
    if (logResponseBodies) {
      _writeBody(
        buffer,
        response.data,
        _firstValue(response.headers.map, Headers.contentTypeHeader),
      );
    }
    return buffer.toString();
  }

  String _describeError(DioException err) {
    final options = err.requestOptions;
    final response = err.response;
    final String head;
    if (err.type == DioExceptionType.cancel) {
      head = 'CANCELLED';
    } else {
      head = response?.statusCode?.toString() ?? 'ERROR';
    }
    final buffer = StringBuffer(
      '<-- $head ${_requestLine(options)}${_elapsed(options)} '
      '[${err.type.name}]',
    );
    final cause = err.error;
    if (cause != null) buffer.write('\ncause: ${cause.runtimeType}');
    if (response != null) {
      if (logHeaders) _writeHeaders(buffer, response.headers.map);
      if (logResponseBodies) {
        _writeBody(
          buffer,
          response.data,
          _firstValue(response.headers.map, Headers.contentTypeHeader),
        );
      }
    }
    return buffer.toString();
  }

  String _requestLine(RequestOptions options) {
    String uri;
    try {
      uri = loggableUri(redactor, options.uri).toString();
    } on Object {
      uri = loggableUrl(redactor, options.path);
    }
    return '${options.method.toUpperCase()} $uri';
  }

  static String? _attemptNote(Map<String, dynamic> extra) {
    final notes = <String>[
      if (extra[SymphonyRequestExtras.authRetried] == true)
        'replayed after token refresh',
      if ((readIntExtra(extra, SymphonyRequestExtras.retryAttempt) ?? 0) > 0)
        'retry #${readIntExtra(extra, SymphonyRequestExtras.retryAttempt)}',
    ];
    return notes.isEmpty ? null : notes.join(', ');
  }

  static String _elapsed(RequestOptions options) {
    final startedAt = options.extra[_startedAtKey];
    if (startedAt is! int) return '';
    final micros = DateTime.now().microsecondsSinceEpoch - startedAt;
    return ' (${(micros / 1000).round()} ms)';
  }

  void _writeHeaders(StringBuffer buffer, Map<String, dynamic> headers) {
    if (headers.isEmpty) return;
    buffer.write('\nheaders:');
    redactor.redactHeaders(headers).forEach((name, value) {
      buffer.write('\n  $name: $value');
    });
  }

  void _writeBody(StringBuffer buffer, Object? data, String? contentType) {
    final body = _describeBody(data, contentType);
    if (body == null || body.isEmpty) return;
    buffer
      ..write('\nbody: ')
      ..write(body);
  }

  String? _describeBody(Object? data, String? contentType) {
    if (data == null) return null;
    if (data is FormData) return _truncate(_describeFormData(data));
    if (data is TypedData) return '[binary ${data.lengthInBytes} bytes]';
    if (data is ResponseBody || data is Stream) return '[stream]';
    if (data is String) {
      final trimmed = data.trim();
      final isForm =
          (contentType?.toLowerCase().contains('x-www-form-urlencoded') ??
                  false) ||
              _urlEncodedPattern.hasMatch(trimmed);
      if (isForm && !trimmed.startsWith('{') && !trimmed.startsWith('[')) {
        return _describeUrlEncoded(trimmed);
      }
    }
    return redactor.stringify(data, maxLength: maxBodyLength);
  }

  String _describeUrlEncoded(String body) {
    try {
      return redactor.stringify(
        Uri.splitQueryString(body),
        maxLength: maxBodyLength,
      );
    } on Object {
      // Never fall back to the raw body: it may contain credentials.
      return '[form data, ${body.length} chars]';
    }
  }

  static String _describeFormData(FormData data) {
    final fields = data.fields.map((field) => field.key).join(', ');
    final files = data.files.map((entry) {
      final file = entry.value;
      final type = file.contentType;
      return '${entry.key}: ${file.filename ?? '(unnamed)'} '
          '(${file.length} bytes${type == null ? '' : ', $type'})';
    }).join(', ');
    return 'FormData(fields: [$fields], files: [$files])';
  }

  String _truncate(String text) {
    if (text.length <= maxBodyLength) return text;
    return '${text.substring(0, maxBodyLength)}… '
        '[truncated ${text.length - maxBodyLength} chars]';
  }

  static String? _firstValue(Map<String, List<String>> headers, String name) {
    final value = findHeader(headers, name);
    if (value is List && value.isNotEmpty) return '${value.first}';
    return null;
  }
}
