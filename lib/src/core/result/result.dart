import 'dart:async';

import 'package:flutter/foundation.dart';

import '../error/failure.dart';

/// The outcome of an operation that can fail: either a [ResultSuccess] holding
/// a value or a [ResultFailure] holding a [Failure].
///
/// ```dart
/// final result = await repository.loadProfile();
/// switch (result) {
///   case ResultSuccess(:final value):
///     print(value.name);
///   case ResultFailure(:final failure):
///     print(failure.message);
/// }
/// ```
@immutable
sealed class Result<T> {
  const Result();

  /// Creates a successful result.
  const factory Result.success(T value) = ResultSuccess<T>;

  /// Creates a failed result.
  const factory Result.failure(Failure failure) = ResultFailure<T>;

  /// Whether this is a [ResultSuccess].
  bool get isSuccess => this is ResultSuccess<T>;

  /// Whether this is a [ResultFailure].
  bool get isFailure => this is ResultFailure<T>;

  /// The value when successful, otherwise `null`.
  T? get valueOrNull => switch (this) {
        ResultSuccess<T>(:final value) => value,
        ResultFailure<T>() => null,
      };

  /// The failure when failed, otherwise `null`.
  Failure? get failureOrNull => switch (this) {
        ResultSuccess<T>() => null,
        ResultFailure<T>(:final failure) => failure,
      };

  /// Calls [success] or [failure] depending on the outcome.
  R when<R>({
    required R Function(T value) success,
    required R Function(Failure failure) failure,
  }) {
    final self = this;
    return switch (self) {
      ResultSuccess<T>(:final value) => success(value),
      ResultFailure<T>(failure: final f) => failure(f),
    };
  }

  /// Transforms the value of a successful result.
  Result<R> map<R>(R Function(T value) transform) {
    final self = this;
    return switch (self) {
      ResultSuccess<T>(:final value) => Result<R>.success(transform(value)),
      ResultFailure<T>(:final failure) => Result<R>.failure(failure),
    };
  }

  /// Transforms the failure of a failed result.
  Result<T> mapFailure(Failure Function(Failure failure) transform) {
    final self = this;
    return switch (self) {
      ResultSuccess<T>() => self,
      ResultFailure<T>(:final failure) => Result<T>.failure(transform(failure)),
    };
  }

  /// Chains another operation that can fail.
  Future<Result<R>> flatMap<R>(
    FutureOr<Result<R>> Function(T value) next,
  ) async {
    final self = this;
    return switch (self) {
      ResultSuccess<T>(:final value) => await next(value),
      ResultFailure<T>(:final failure) => Result<R>.failure(failure),
    };
  }

  /// Returns the value or the result of [orElse].
  T getOrElse(T Function(Failure failure) orElse) {
    final self = this;
    return switch (self) {
      ResultSuccess<T>(:final value) => value,
      ResultFailure<T>(:final failure) => orElse(failure),
    };
  }

  /// Returns the value or throws the [Failure].
  T getOrThrow() {
    final self = this;
    return switch (self) {
      ResultSuccess<T>(:final value) => value,
      ResultFailure<T>(:final failure) => throw failure,
    };
  }
}

/// A successful [Result].
final class ResultSuccess<T> extends Result<T> {
  /// Creates a successful result holding [value].
  const ResultSuccess(this.value);

  /// The produced value.
  final T value;

  @override
  bool operator ==(Object other) =>
      other is ResultSuccess<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Result.success($value)';
}

/// A failed [Result].
final class ResultFailure<T> extends Result<T> {
  /// Creates a failed result holding [failure].
  const ResultFailure(this.failure);

  /// The failure that occurred.
  final Failure failure;

  @override
  bool operator ==(Object other) =>
      other is ResultFailure<T> && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'Result.failure($failure)';
}

/// Converts arbitrary errors into failures. Used by [guardResult].
typedef FailureMapper = Failure Function(Object error, StackTrace stackTrace);

/// Runs [body] and captures its outcome as a [Result]; the returned future
/// never completes with an error.
///
/// A thrown [Failure] is returned as-is. Any other error is converted with
/// [mapError] or wrapped in an [UnexpectedFailure]. When [mapError] itself
/// throws, a thrown [Failure] is used, and any other error falls back to an
/// [UnexpectedFailure] wrapping the original error.
Future<Result<T>> guardResult<T>(
  FutureOr<T> Function() body, {
  FailureMapper? mapError,
}) async {
  try {
    return Result<T>.success(await body());
  } on Failure catch (failure) {
    return Result<T>.failure(failure);
  } on Object catch (error, stackTrace) {
    return Result<T>.failure(_mapError(error, stackTrace, mapError));
  }
}

Failure _mapError(Object error, StackTrace stackTrace, FailureMapper? mapper) {
  if (mapper != null) {
    try {
      return mapper(error, stackTrace);
    } on Failure catch (failure) {
      return failure;
    } on Object {
      // A broken mapper must not turn a Result-returning call into a
      // throwing one: fall back to the default mapping of the original error.
    }
  }
  return UnexpectedFailure.fromError(error, stackTrace);
}
