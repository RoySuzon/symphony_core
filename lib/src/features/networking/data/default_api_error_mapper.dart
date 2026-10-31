import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';
import '../domain/api_error_mapper.dart';
import 'interceptors/interceptor_support.dart';

/// The [ApiErrorMapper] used by `ApiClient` unless another one is provided.
///
/// Dio errors are mapped as follows:
///
/// | Error                                   | Failure                  |
/// |-----------------------------------------|--------------------------|
/// | cancelled request                       | [CancelledFailure]       |
/// | connect / send / receive timeout        | [TimeoutFailure]         |
/// | connection error, bad certificate       | [NetworkFailure]         |
/// | HTTP 400 / 422                          | [ValidationFailure]      |
/// | HTTP 401                                | [UnauthorizedFailure]    |
/// | HTTP 403                                | [ForbiddenFailure]       |
/// | HTTP 404                                | [NotFoundFailure]        |
/// | any other HTTP status                   | [ServerFailure]          |
/// | unknown error caused by a socket / TLS  | [NetworkFailure]         |
/// | unknown error caused by bad JSON        | [ParsingFailure]         |
/// | any other unknown error                 | [UnexpectedFailure]      |
///
/// Other errors: a [Failure] is returned unchanged, [FormatException] and
/// [TypeError] become a [ParsingFailure] and anything else an
/// [UnexpectedFailure]. The original error is kept as `Failure.cause`.
///
/// For HTTP errors the user-facing message is read from the response body
/// (see [messageKeys], including nested objects such as
/// `{"error": {"message": "..."}}`) and falls back to the configurable
/// default messages, which applications can localize. Machine readable codes
/// are read from [codeKeys] and field errors from [fieldErrorsKey], which may
/// be shaped as `{"errors": {"email": ["is invalid"]}}` or
/// `{"errors": [{"field": "email", "message": "is invalid"}]}`.
///
/// Extend this class to support project specific payloads, and provide it
/// through `apiErrorMapperProvider` (or `ApiClient(errorMapper: ...)`).
class DefaultApiErrorMapper extends ApiErrorMapper {
  /// Creates the mapper. Every message can be overridden (for example with
  /// localized strings).
  const DefaultApiErrorMapper({
    this.messageKeys = defaultMessageKeys,
    this.fieldErrorsKey = 'errors',
    this.codeKeys = defaultCodeKeys,
    this.useServerMessages = true,
    this.networkMessage =
        'Unable to connect. Please check your internet connection.',
    this.badCertificateMessage =
        'A secure connection to the server could not be established.',
    this.timeoutMessage = 'The request timed out. Please try again.',
    this.cancelledMessage = 'The request was cancelled.',
    this.validationMessage = 'Some of the information provided is invalid.',
    this.unauthorizedMessage =
        'Your session has expired. Please sign in again.',
    this.forbiddenMessage =
        'You do not have permission to perform this action.',
    this.notFoundMessage = 'The requested resource was not found.',
    this.clientErrorMessage = 'The request could not be completed.',
    this.serverErrorMessage =
        'The server encountered an error. Please try again later.',
    this.parsingMessage = 'The server response could not be processed.',
    this.unexpectedMessage = 'Something went wrong. Please try again.',
  });

  /// Body keys searched, in order, for a user-facing error message.
  static const List<String> defaultMessageKeys = <String>[
    'message',
    'error_description',
    'error',
    'detail',
    'title',
    'msg',
  ];

  /// Body keys searched, in order, for a machine readable error code.
  static const List<String> defaultCodeKeys = <String>[
    'code',
    'error_code',
    'errorCode',
  ];

  static const List<String> _fieldNameKeys = <String>[
    'field',
    'name',
    'param',
    'path',
    'property',
    'attribute',
    'key',
  ];

  static const int _maxDepth = 4;
  static const int _maxPlainTextMessageLength = 200;

  /// Body keys searched for a user-facing message (nested objects included).
  final List<String> messageKeys;

  /// Body key holding field errors (also searched inside an `error` object).
  final String fieldErrorsKey;

  /// Body keys searched for a machine readable error code.
  final List<String> codeKeys;

  /// Whether messages found in response bodies are used. When `false`, the
  /// default messages below are always used.
  final bool useServerMessages;

  /// Message of [NetworkFailure]s caused by connectivity problems.
  final String networkMessage;

  /// Message of [NetworkFailure]s caused by an invalid TLS certificate.
  final String badCertificateMessage;

  /// Message of [TimeoutFailure]s.
  final String timeoutMessage;

  /// Message of [CancelledFailure]s.
  final String cancelledMessage;

  /// Default message of [ValidationFailure]s (HTTP 400 / 422).
  final String validationMessage;

  /// Default message of [UnauthorizedFailure]s (HTTP 401).
  final String unauthorizedMessage;

  /// Default message of [ForbiddenFailure]s (HTTP 403).
  final String forbiddenMessage;

  /// Default message of [NotFoundFailure]s (HTTP 404).
  final String notFoundMessage;

  /// Default message of [ServerFailure]s for other 4xx statuses.
  final String clientErrorMessage;

  /// Default message of [ServerFailure]s for 5xx and unexpected statuses.
  final String serverErrorMessage;

  /// Message of [ParsingFailure]s.
  final String parsingMessage;

  /// Message of [UnexpectedFailure]s.
  final String unexpectedMessage;

  @override
  Failure map(Object error, StackTrace stackTrace) {
    try {
      return _map(error, stackTrace);
    } on Object {
      return UnexpectedFailure(unexpectedMessage, error, stackTrace);
    }
  }

  Failure _map(Object error, StackTrace stackTrace) {
    if (error is Failure) return error;
    if (error is DioException) return mapDioException(error, stackTrace);
    if (error is FormatException || error is TypeError) {
      return ParsingFailure(
        parsingMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return UnexpectedFailure(unexpectedMessage, error, stackTrace);
  }

  /// Maps a [DioException]. Override to customise Dio specific mapping.
  Failure mapDioException(DioException error, StackTrace stackTrace) {
    final inner = error.error;
    if (inner is Failure) return inner;

    final type = error.type;
    if (type == DioExceptionType.cancel) {
      return CancelledFailure(cancelledMessage);
    }
    // Matches connect, send and receive timeouts (and the transform timeout
    // of recent Dio versions) without an exhaustive switch over the enum.
    if (type.name.endsWith('Timeout')) {
      return TimeoutFailure.withDetails(
        timeoutMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (type == DioExceptionType.connectionError) {
      return NetworkFailure.withDetails(
        networkMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (type == DioExceptionType.badCertificate) {
      return NetworkFailure.withDetails(
        badCertificateMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (type == DioExceptionType.badResponse) {
      return mapResponseError(error, stackTrace);
    }
    // DioExceptionType.unknown (and types added by future Dio versions).
    if (inner is FormatException || inner is TypeError) {
      return ParsingFailure(
        parsingMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (looksLikeConnectionError(inner) ||
        looksLikeConnectionError(error.message)) {
      return NetworkFailure.withDetails(
        networkMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return UnexpectedFailure(unexpectedMessage, error, stackTrace);
  }

  /// Maps an HTTP error response (`DioExceptionType.badResponse`).
  Failure mapResponseError(DioException error, StackTrace stackTrace) {
    final status = error.response?.statusCode;
    final body = decodeBody(error.response?.data);
    final message = useServerMessages ? extractMessage(body) : null;
    final code = extractCode(body);
    switch (status) {
      case 400:
      case 422:
        return ValidationFailure(
          message ?? validationMessage,
          code: code,
          statusCode: status,
          cause: error,
          stackTrace: stackTrace,
          fieldErrors: extractFieldErrors(body),
        );
      case 401:
        return UnauthorizedFailure.withDetails(
          message ?? unauthorizedMessage,
          code: code,
          cause: error,
          stackTrace: stackTrace,
        );
      case 403:
        return ForbiddenFailure.withDetails(
          message ?? forbiddenMessage,
          code: code,
          cause: error,
          stackTrace: stackTrace,
        );
      case 404:
        return NotFoundFailure.withDetails(
          message ?? notFoundMessage,
          code: code,
          cause: error,
          stackTrace: stackTrace,
        );
      default:
        final isClientError = status != null && status >= 400 && status < 500;
        return ServerFailure(
          message ?? (isClientError ? clientErrorMessage : serverErrorMessage),
          code: code,
          statusCode: status,
          cause: error,
          stackTrace: stackTrace,
          data: body,
        );
    }
  }

  /// Normalises a response body: JSON text (or UTF-8 encoded JSON bytes) is
  /// decoded; streams are discarded; any other value is returned unchanged.
  Object? decodeBody(Object? data) {
    if (data == null || data is ResponseBody || data is Stream) return null;
    if (data is List<int>) {
      if (data.isEmpty || data.length > 512 * 1024) return null;
      final text = utf8.decode(data, allowMalformed: true);
      return _looksLikeJson(text) ? _tryJson(text) ?? text : text;
    }
    if (data is String && _looksLikeJson(data)) return _tryJson(data) ?? data;
    return data;
  }

  /// The user-facing message found in [body], or `null`.
  ///
  /// Searches [messageKeys] in order (strings, lists of strings and nested
  /// objects). A short single-line plain text body is used as is; HTML is
  /// ignored.
  String? extractMessage(Object? body) {
    if (body is String) return _plainTextMessage(body);
    return _messageIn(body, 0);
  }

  /// The machine readable error code found in [body], or `null`.
  String? extractCode(Object? body) => _codeIn(body, 0);

  /// The field errors found in [body] under [fieldErrorsKey].
  Map<String, List<String>> extractFieldErrors(Object? body) {
    if (body is! Map) return const <String, List<String>>{};
    var errors = _lookup(body, fieldErrorsKey);
    if (errors == null) {
      final nested = _lookup(body, 'error');
      if (nested is Map) errors = _lookup(nested, fieldErrorsKey);
    }
    final result = <String, List<String>>{};
    void add(String field, String message) {
      final name = field.trim();
      final text = message.trim();
      if (name.isEmpty || text.isEmpty) return;
      (result[name] ??= <String>[]).add(text);
    }

    if (errors is Map) {
      _collectFieldMap(errors, '', add, 0);
    } else if (errors is List) {
      for (final item in errors) {
        if (item is! Map) continue;
        final field = _fieldName(item);
        final message = _messageIn(item, 1);
        if (field != null && message != null) add(field, message);
      }
    }
    return Map<String, List<String>>.unmodifiable(<String, List<String>>{
      for (final entry in result.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
  }

  void _collectFieldMap(
    Map<dynamic, dynamic> errors,
    String prefix,
    void Function(String field, String message) add,
    int depth,
  ) {
    if (depth > _maxDepth) return;
    errors.forEach((key, value) {
      final field = prefix.isEmpty ? '$key' : '$prefix.$key';
      if (value is String) {
        add(field, value);
      } else if (value is List) {
        for (final item in value) {
          final message = item is String ? item : _messageIn(item, depth + 1);
          if (message != null) add(field, message);
        }
      } else if (value is Map) {
        final message = _directMessage(value);
        if (message != null) {
          add(field, message);
        } else {
          _collectFieldMap(value, field, add, depth + 1);
        }
      }
    });
  }

  String? _fieldName(Map<dynamic, dynamic> item) {
    for (final key in _fieldNameKeys) {
      final value = _lookup(item, key);
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is List && value.isNotEmpty) {
        return value.map((segment) => '$segment').join('.');
      }
    }
    // JSON:API: {"source": {"pointer": "/data/attributes/email"}}.
    final source = _lookup(item, 'source');
    if (source is Map) {
      final pointer =
          _lookup(source, 'pointer') ?? _lookup(source, 'parameter');
      if (pointer is String && pointer.trim().isNotEmpty) {
        final segments = pointer
            .split('/')
            .where((segment) => segment.isNotEmpty);
        if (segments.isNotEmpty) return segments.last;
      }
    }
    return null;
  }

  /// A message stored directly (not nested) under one of [messageKeys].
  String? _directMessage(Map<dynamic, dynamic> map) {
    for (final key in messageKeys) {
      final value = _lookup(map, key);
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String? _messageIn(Object? value, int depth) {
    if (depth > _maxDepth) return null;
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? null : text;
    }
    if (value is List) {
      for (final item in value) {
        final message = _messageIn(item, depth + 1);
        if (message != null) return message;
      }
      return null;
    }
    if (value is Map) {
      for (final key in messageKeys) {
        final message = _messageIn(_lookup(value, key), depth + 1);
        if (message != null) return message;
      }
    }
    return null;
  }

  String? _codeIn(Object? body, int depth) {
    if (body is! Map || depth > _maxDepth) return null;
    for (final key in codeKeys) {
      final value = _lookup(body, key);
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return '$value';
    }
    final nested = _lookup(body, 'error');
    if (nested is Map) return _codeIn(nested, depth + 1);
    // OAuth 2: {"error": "invalid_grant", "error_description": "..."}.
    if (nested is String &&
        nested.trim().isNotEmpty &&
        _lookup(body, 'error_description') != null) {
      return nested.trim();
    }
    return null;
  }

  static String? _plainTextMessage(String body) {
    final text = body.trim();
    if (text.isEmpty ||
        text.length > _maxPlainTextMessageLength ||
        text.contains('\n') ||
        // HTML / XML pages and malformed JSON are never shown to users.
        text.startsWith('<') ||
        _looksLikeJson(text)) {
      return null;
    }
    return text;
  }

  static Object? _lookup(Map<dynamic, dynamic> map, String key) {
    if (map.containsKey(key)) return map[key];
    final lower = key.toLowerCase();
    for (final entry in map.entries) {
      if ('${entry.key}'.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  static bool _looksLikeJson(String text) {
    final trimmed = text.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  static Object? _tryJson(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
