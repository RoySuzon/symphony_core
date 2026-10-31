import 'package:flutter/foundation.dart';

/// Base type of every expected error produced by `symphony_core`.
///
/// Failures are plain values that can be returned inside a `Result` or thrown
/// (they implement [Exception]). The data layer converts low level errors
/// (Dio, platform, parsing) into failures so the presentation layer never
/// depends on infrastructure exceptions.
///
/// Applications can declare their own failures by extending this class.
@immutable
abstract class Failure implements Exception {
  /// Creates a failure.
  const Failure(
    this.message, {
    this.code,
    this.statusCode,
    this.cause,
    this.stackTrace,
  });

  /// Human readable description, safe to show to end users.
  final String message;

  /// Optional machine readable error code (for example from the backend).
  final String? code;

  /// HTTP status code, when the failure comes from an HTTP response.
  final int? statusCode;

  /// The underlying error, if any. Never shown to users.
  final Object? cause;

  /// Stack trace of [cause], if any.
  final StackTrace? stackTrace;

  @override
  bool operator ==(Object other) =>
      other is Failure &&
      other.runtimeType == runtimeType &&
      other.message == message &&
      other.code == code &&
      other.statusCode == statusCode;

  @override
  int get hashCode => Object.hash(runtimeType, message, code, statusCode);

  @override
  String toString() {
    final details = <String>[
      if (code != null) 'code: $code',
      if (statusCode != null) 'status: $statusCode',
    ];
    final suffix = details.isEmpty ? '' : ' (${details.join(', ')})';
    return '$runtimeType: $message$suffix';
  }
}

/// The device could not reach the server (offline, DNS, TLS, refused...).
class NetworkFailure extends Failure {
  /// Creates a network failure.
  const NetworkFailure([
    super.message = 'Unable to connect. Please check your internet connection.',
  ]) : super();

  /// Creates a network failure with details.
  const NetworkFailure.withDetails(
    super.message, {
    super.code,
    super.cause,
    super.stackTrace,
  });
}

/// A connect, send or receive timeout elapsed.
class TimeoutFailure extends Failure {
  /// Creates a timeout failure.
  const TimeoutFailure([
    super.message = 'The request timed out. Please try again.',
  ]) : super();

  /// Creates a timeout failure with details.
  const TimeoutFailure.withDetails(
    super.message, {
    super.code,
    super.cause,
    super.stackTrace,
  });
}

/// The server answered with an error status (usually 5xx) or an unexpected
/// response.
class ServerFailure extends Failure {
  /// Creates a server failure.
  const ServerFailure(
    super.message, {
    super.code,
    super.statusCode,
    super.cause,
    super.stackTrace,
    this.data,
  });

  /// Decoded response body, if any.
  final Object? data;
}

/// The request was not authenticated (HTTP 401) or the session expired.
class UnauthorizedFailure extends Failure {
  /// Creates an unauthorized failure.
  const UnauthorizedFailure([
    super.message = 'Your session has expired. Please sign in again.',
  ]) : super(statusCode: 401);

  /// Creates an unauthorized failure with details.
  const UnauthorizedFailure.withDetails(
    super.message, {
    super.code,
    super.statusCode = 401,
    super.cause,
    super.stackTrace,
  });
}

/// The authenticated user is not allowed to perform the action (HTTP 403).
class ForbiddenFailure extends Failure {
  /// Creates a forbidden failure.
  const ForbiddenFailure([
    super.message = 'You do not have permission to perform this action.',
  ]) : super(statusCode: 403);

  /// Creates a forbidden failure with details.
  const ForbiddenFailure.withDetails(
    super.message, {
    super.code,
    super.statusCode = 403,
    super.cause,
    super.stackTrace,
  });
}

/// The requested resource does not exist (HTTP 404).
class NotFoundFailure extends Failure {
  /// Creates a not found failure.
  const NotFoundFailure([
    super.message = 'The requested resource was not found.',
  ]) : super(statusCode: 404);

  /// Creates a not found failure with details.
  const NotFoundFailure.withDetails(
    super.message, {
    super.code,
    super.statusCode = 404,
    super.cause,
    super.stackTrace,
  });
}

/// Input was rejected (HTTP 400 / 422 or local validation).
class ValidationFailure extends Failure {
  /// Creates a validation failure.
  const ValidationFailure(
    super.message, {
    super.code,
    super.statusCode,
    super.cause,
    super.stackTrace,
    this.fieldErrors = const <String, List<String>>{},
  });

  /// Errors per field name, e.g. `{'email': ['is invalid']}`.
  final Map<String, List<String>> fieldErrors;

  /// First error message for [field], if any.
  String? errorFor(String field) {
    final errors = fieldErrors[field];
    return errors == null || errors.isEmpty ? null : errors.first;
  }
}

/// Authentication specific failure (wrong credentials, locked account...).
class AuthFailure extends Failure {
  /// Creates an authentication failure.
  const AuthFailure(
    super.message, {
    super.code,
    super.statusCode,
    super.cause,
    super.stackTrace,
  });
}

/// The operation was cancelled by the caller.
class CancelledFailure extends Failure {
  /// Creates a cancelled failure.
  const CancelledFailure([super.message = 'The request was cancelled.'])
      : super();
}

/// A response could not be parsed into the expected model.
class ParsingFailure extends Failure {
  /// Creates a parsing failure.
  const ParsingFailure(
    super.message, {
    super.code,
    super.cause,
    super.stackTrace,
  });
}

/// Reading or writing local storage failed.
class StorageFailure extends Failure {
  /// Creates a storage failure.
  const StorageFailure(
    super.message, {
    super.code,
    super.cause,
    super.stackTrace,
  });
}

/// The requested feature is not supported by the configured adapter.
class UnsupportedFailure extends Failure {
  /// Creates an unsupported failure.
  const UnsupportedFailure([
    super.message = 'This feature is not supported.',
  ]) : super();
}

/// Any error that does not fit another category.
class UnexpectedFailure extends Failure {
  /// Creates an unexpected failure.
  const UnexpectedFailure([
    super.message = 'Something went wrong. Please try again.',
    Object? cause,
    StackTrace? stackTrace,
  ]) : super(cause: cause, stackTrace: stackTrace);

  /// Wraps an arbitrary [error] into a failure.
  factory UnexpectedFailure.fromError(Object error, [StackTrace? stackTrace]) {
    if (error is UnexpectedFailure) return error;
    return UnexpectedFailure(
      'Something went wrong. Please try again.',
      error,
      stackTrace,
    );
  }
}
