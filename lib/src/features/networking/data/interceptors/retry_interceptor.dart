import 'dart:async';

import 'package:dio/dio.dart';

import '../../../../core/config/symphony_config.dart';
import '../../../../core/logging/symphony_logger.dart';
import '../../domain/api_request_options.dart';
import 'interceptor_support.dart';

/// Waits for [delay] before a request is retried. Inject a custom
/// implementation (for example one that records the delays) in tests.
typedef RetryDelayCallback = Future<void> Function(Duration delay);

/// Automatically retries idempotent requests that failed for a transient
/// reason.
///
/// A request is retried when:
///
/// * its method is in [retryableMethods] (GET, HEAD, OPTIONS, PUT and DELETE
///   by default — POST and PATCH are never retried automatically);
/// * it failed with a connect, send or receive timeout, a connection error
///   (including socket / TLS errors reported as unknown errors), or a status
///   code in `SymphonyConfig.retryStatusCodes`;
/// * it was not cancelled and its `ApiRequestOptions.retry` flag is not
///   `false`;
/// * fewer than `ApiRequestOptions.maxRetries` (or
///   `SymphonyConfig.maxRetries`) retries were already made;
/// * its body can be replayed (`Stream` bodies cannot).
///
/// Attempt `n` waits `SymphonyConfig.retryDelay * n`. When
/// [respectRetryAfter] is true and the response carries a `Retry-After`
/// header expressed in seconds, the longer of both delays is used; if the
/// server asks to wait longer than [maxRetryAfter] the error is propagated
/// immediately instead.
///
/// Each retry goes through the whole interceptor chain again (inspector,
/// logging, headers, token injection), with
/// `SymphonyRequestExtras.retryAttempt` incremented.
class RetryInterceptor extends Interceptor {
  /// Creates the interceptor.
  ///
  /// [dio] sends the retried requests (pass the same instance this
  /// interceptor is installed on). [delay] waits between attempts and
  /// defaults to [Future.delayed].
  RetryInterceptor({
    required this.dio,
    required this.config,
    RetryDelayCallback? delay,
    SymphonyLogger? logger,
    this.retryableMethods = defaultRetryableMethods,
    this.respectRetryAfter = true,
    this.maxRetryAfter = const Duration(seconds: 30),
  })  : _delay = delay ?? _defaultDelay,
        _logger = logger ?? SymphonyLogger.disabled();

  /// Idempotent HTTP methods retried by default.
  static const Set<String> defaultRetryableMethods = <String>{
    'GET',
    'HEAD',
    'OPTIONS',
    'PUT',
    'DELETE',
  };

  /// Dio instance used to send the retried requests.
  final Dio dio;

  /// Configuration providing `maxRetries`, `retryDelay` and
  /// `retryStatusCodes`.
  final SymphonyConfig config;

  /// Upper-case HTTP methods that may be retried.
  final Set<String> retryableMethods;

  /// Whether a `Retry-After` header (in seconds) extends the delay.
  final bool respectRetryAfter;

  /// Longest `Retry-After` delay honoured; longer requests are not retried.
  final Duration maxRetryAfter;

  final RetryDelayCallback _delay;
  final SymphonyLogger _logger;

  static Future<void> _defaultDelay(Duration delay) =>
      Future<void>.delayed(delay);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attempt =
        readIntExtra(options.extra, SymphonyRequestExtras.retryAttempt) ?? 0;
    final maxRetries = _maxRetries(options);
    if (attempt >= maxRetries || !shouldRetry(err)) {
      handler.next(err);
      return;
    }
    final nextAttempt = attempt + 1;
    final wait = _delayFor(err, nextAttempt);
    if (wait == null) {
      handler.next(err);
      return;
    }

    _logger.info(
      'Retrying ${options.method.toUpperCase()} '
      '${loggableUri(config.redactor, options.uri)} in ${wait.inMilliseconds} ms '
      '(attempt $nextAttempt of $maxRetries).',
    );
    try {
      await _delay(wait);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Retry delay failed (${error.runtimeType}).',
        stackTrace: stackTrace,
      );
    }
    if (options.cancelToken?.isCancelled ?? false) {
      handler.next(err);
      return;
    }

    final retryOptions = options.copyWith(
      extra: <String, dynamic>{
        ...options.extra,
        SymphonyRequestExtras.retryAttempt: nextAttempt,
      },
      data: replayableBody(options.data),
    );
    Response<dynamic>? response;
    DioException? failure;
    try {
      response = await dio.fetch<dynamic>(retryOptions);
    } on DioException catch (error) {
      failure = error;
    } on Object catch (error, stackTrace) {
      failure = DioException(
        requestOptions: retryOptions,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (response != null) {
      handler.resolve(response);
    } else {
      // The retried request already went through the whole chain (including
      // its own retries): do not process its error a second time.
      handler.reject(failure ?? err);
    }
  }

  /// Whether [err] is eligible for a retry, regardless of the number of
  /// attempts already made.
  bool shouldRetry(DioException err) {
    final options = err.requestOptions;
    if (!readBoolExtra(
      options.extra,
      SymphonyRequestExtras.retry,
      defaultValue: true,
    )) {
      return false;
    }
    if (err.type == DioExceptionType.cancel ||
        (options.cancelToken?.isCancelled ?? false)) {
      return false;
    }
    if (!retryableMethods.contains(options.method.toUpperCase())) {
      return false;
    }
    if (!isReplayableBody(options.data)) return false;

    final type = err.type;
    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.connectionError) {
      return true;
    }
    if (type == DioExceptionType.badResponse) {
      final status = err.response?.statusCode;
      return status != null && config.retryStatusCodes.contains(status);
    }
    if (type == DioExceptionType.unknown) {
      return looksLikeConnectionError(err.error);
    }
    return false;
  }

  int _maxRetries(RequestOptions options) {
    final value =
        readIntExtra(options.extra, SymphonyRequestExtras.maxRetries) ??
            config.maxRetries;
    return value < 0 ? 0 : value;
  }

  /// The delay before attempt [attempt], or `null` when the server asked to
  /// wait longer than [maxRetryAfter].
  Duration? _delayFor(DioException err, int attempt) {
    final base = config.retryDelay * attempt;
    if (!respectRetryAfter) return base;
    final retryAfter = _retryAfter(err.response);
    if (retryAfter == null) return base;
    if (retryAfter > maxRetryAfter) return null;
    return retryAfter > base ? retryAfter : base;
  }

  static Duration? _retryAfter(Response<dynamic>? response) {
    final values = response?.headers['retry-after'];
    if (values == null || values.isEmpty) return null;
    final seconds = int.tryParse(values.first.trim());
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
  }
}
