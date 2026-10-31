import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

void main() {
  const success = Result<int>.success(2);
  const failure = Result<int>.failure(NetworkFailure());

  group('Result', () {
    test('exposes the outcome', () {
      expect(success.isSuccess, isTrue);
      expect(success.isFailure, isFalse);
      expect(success.valueOrNull, 2);
      expect(success.failureOrNull, isNull);

      expect(failure.isSuccess, isFalse);
      expect(failure.isFailure, isTrue);
      expect(failure.valueOrNull, isNull);
      expect(failure.failureOrNull, const NetworkFailure());
    });

    test('supports exhaustive pattern matching', () {
      String describe(Result<int> result) => switch (result) {
        ResultSuccess<int>(:final value) => 'value $value',
        ResultFailure<int>(:final failure) => 'failure ${failure.message}',
      };

      expect(describe(success), 'value 2');
      expect(
        describe(const Result<int>.failure(AuthFailure('no'))),
        'failure no',
      );
    });

    test('when calls the matching branch', () {
      expect(
        success.when(success: (v) => 'ok $v', failure: (f) => 'ko'),
        'ok 2',
      );
      expect(
        failure.when(success: (v) => 'ok', failure: (f) => f.runtimeType),
        NetworkFailure,
      );
    });

    test('map transforms values and keeps failures', () {
      expect(success.map((v) => '$v!'), const Result<String>.success('2!'));
      final mapped = failure.map((v) => '$v!');
      expect(mapped, isA<ResultFailure<String>>());
      expect(mapped.failureOrNull, const NetworkFailure());
    });

    test('mapFailure transforms failures and keeps values', () {
      Failure toAuth(Failure f) => AuthFailure(f.message);

      expect(identical(success.mapFailure(toAuth), success), isTrue);
      expect(
        failure.mapFailure(toAuth).failureOrNull,
        AuthFailure(const NetworkFailure().message),
      );
    });

    test('flatMap chains successes and short-circuits failures', () async {
      var calls = 0;
      Future<Result<String>> next(int value) async {
        calls++;
        return Result<String>.success('n$value');
      }

      expect(await success.flatMap(next), const Result<String>.success('n2'));
      expect(calls, 1);

      final chained = await failure.flatMap(next);
      expect(chained.failureOrNull, const NetworkFailure());
      expect(calls, 1);

      final synchronous = await success.flatMap(
        (v) => const Result<String>.failure(ParsingFailure('bad')),
      );
      expect(synchronous.failureOrNull, const ParsingFailure('bad'));
    });

    test('getOrElse and getOrThrow', () {
      expect(success.getOrElse((_) => 0), 2);
      expect(failure.getOrElse((f) => -1), -1);
      expect(success.getOrThrow(), 2);
      expect(failure.getOrThrow, throwsA(const NetworkFailure()));
    });

    test('equality, hashCode and toString', () {
      expect(const Result<int>.success(2), success);
      expect(const Result<int>.success(2).hashCode, success.hashCode);
      expect(const Result<int>.success(3), isNot(success));
      expect(const Result<int>.failure(NetworkFailure()), failure);
      expect(
        const Result<int>.failure(NetworkFailure()).hashCode,
        failure.hashCode,
      );
      expect(success, isNot(failure));
      expect(success.toString(), 'Result.success(2)');
      expect(failure.toString(), startsWith('Result.failure(NetworkFailure'));
    });
  });

  group('guardResult', () {
    test('wraps the returned value', () async {
      expect(await guardResult(() => 42), const Result<int>.success(42));
      expect(
        await guardResult(() async => 'async'),
        const Result<String>.success('async'),
      );
    });

    test('returns thrown failures as they are', () async {
      final result = await guardResult<int>(
        () => throw const ForbiddenFailure(),
      );

      expect(result.failureOrNull, const ForbiddenFailure());
    });

    test('wraps other errors in an UnexpectedFailure', () async {
      final error = StateError('bug');

      final result = await guardResult<int>(() async => throw error);

      final failure = result.failureOrNull;
      expect(failure, isA<UnexpectedFailure>());
      expect(failure!.cause, same(error));
      expect(failure.stackTrace, isNotNull);
    });

    test('uses mapError for non-failure errors', () async {
      Object? seenError;
      StackTrace? seenStackTrace;

      final result = await guardResult<int>(
        () => throw const FormatException('bad json'),
        mapError: (error, stackTrace) {
          seenError = error;
          seenStackTrace = stackTrace;
          return ParsingFailure('Invalid payload', cause: error);
        },
      );

      expect(result.failureOrNull, const ParsingFailure('Invalid payload'));
      expect(seenError, isA<FormatException>());
      expect(seenStackTrace, isNotNull);
    });

    test('does not call mapError for failures', () async {
      var called = false;

      final result = await guardResult<int>(
        () => throw const TimeoutFailure(),
        mapError: (_, _) {
          called = true;
          return const UnexpectedFailure();
        },
      );

      expect(result.failureOrNull, const TimeoutFailure());
      expect(called, isFalse);
    });

    test('still returns a failure when mapError itself throws', () async {
      const original = FormatException('bad json');

      final result = await guardResult<int>(
        () => throw original,
        mapError: (error, stackTrace) => throw StateError('mapper bug'),
      );

      final failure = result.failureOrNull;
      expect(failure, isA<UnexpectedFailure>());
      expect(failure!.cause, same(original), reason: 'the original error');
      expect(failure.stackTrace, isNotNull);
    });

    test('uses a Failure thrown by mapError', () async {
      final result = await guardResult<int>(
        () => throw StateError('low level'),
        mapError: (error, stackTrace) => throw const NetworkFailure(),
      );

      expect(result.failureOrNull, const NetworkFailure());
    });
  });
}
