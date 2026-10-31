import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

class _QuotaFailure extends Failure {
  const _QuotaFailure(super.message, {super.code});
}

void main() {
  group('Failure', () {
    test('is an Exception and can be extended by applications', () {
      const quota = _QuotaFailure('Quota exceeded', code: 'quota');

      expect(const NetworkFailure(), isA<Exception>());
      expect(quota, isA<Failure>());
      expect(quota.toString(), '_QuotaFailure: Quota exceeded (code: quota)');
    });

    test('equality uses type, message, code and status code', () {
      expect(
        const ServerFailure('Boom', code: 'E1', statusCode: 500),
        const ServerFailure('Boom', code: 'E1', statusCode: 500),
      );
      expect(
        const ServerFailure('Boom', code: 'E1', statusCode: 500).hashCode,
        const ServerFailure('Boom', code: 'E1', statusCode: 500).hashCode,
      );
      expect(
        const ServerFailure('Boom', statusCode: 500),
        isNot(const ServerFailure('Boom', statusCode: 502)),
      );
      expect(
        const ServerFailure('Boom', code: 'E1'),
        isNot(const ServerFailure('Boom', code: 'E2')),
      );
      expect(
        const AuthFailure('Nope'),
        isNot(const ServerFailure('Nope')),
        reason: 'different runtime types are never equal',
      );
    });

    test('equality ignores cause and stack trace', () {
      final first = StorageFailure('Disk', cause: StateError('a'));
      final second = StorageFailure(
        'Disk',
        cause: ArgumentError('b'),
        stackTrace: StackTrace.current,
      );

      expect(first, second);
    });

    test('toString lists code and status when present', () {
      expect(
        const NetworkFailure('Offline').toString(),
        'NetworkFailure: Offline',
      );
      expect(
        const ServerFailure('Boom', code: 'E1', statusCode: 500).toString(),
        'ServerFailure: Boom (code: E1, status: 500)',
      );
      expect(
        const UnauthorizedFailure().toString(),
        'UnauthorizedFailure: Your session has expired. Please sign in again. '
        '(status: 401)',
      );
    });

    test('predefined failures have default messages and status codes', () {
      expect(const NetworkFailure().message, isNotEmpty);
      expect(const TimeoutFailure().message, isNotEmpty);
      expect(const CancelledFailure().message, isNotEmpty);
      expect(const UnsupportedFailure().message, isNotEmpty);
      expect(const UnexpectedFailure().message, isNotEmpty);
      expect(const UnauthorizedFailure().statusCode, 401);
      expect(const ForbiddenFailure().statusCode, 403);
      expect(const NotFoundFailure().statusCode, 404);
      expect(const NetworkFailure().statusCode, isNull);
    });

    test('withDetails constructors keep details', () {
      final cause = StateError('socket');
      final stackTrace = StackTrace.current;
      final network = NetworkFailure.withDetails(
        'DNS failed',
        code: 'dns',
        cause: cause,
        stackTrace: stackTrace,
      );
      const timeout = TimeoutFailure.withDetails('Slow', code: 'receive');
      const unauthorized = UnauthorizedFailure.withDetails('Expired');
      const forbidden = ForbiddenFailure.withDetails('No', statusCode: 451);
      const notFound = NotFoundFailure.withDetails('Gone', code: 'missing');

      expect(network.message, 'DNS failed');
      expect(network.code, 'dns');
      expect(network.cause, same(cause));
      expect(network.stackTrace, same(stackTrace));
      expect(timeout.code, 'receive');
      expect(unauthorized.statusCode, 401);
      expect(forbidden.statusCode, 451);
      expect(notFound.statusCode, 404);
      expect(notFound.code, 'missing');
    });

    test('ServerFailure keeps the response data', () {
      const failure = ServerFailure(
        'Boom',
        statusCode: 500,
        data: <String, Object?>{'detail': 'x'},
      );

      expect(failure.data, <String, Object?>{'detail': 'x'});
    });
  });

  group('ValidationFailure', () {
    const failure = ValidationFailure(
      'Invalid input',
      statusCode: 422,
      fieldErrors: <String, List<String>>{
        'email': <String>['is invalid', 'is taken'],
        'name': <String>[],
      },
    );

    test('errorFor returns the first error of a field', () {
      expect(failure.errorFor('email'), 'is invalid');
    });

    test('errorFor returns null for unknown fields or empty lists', () {
      expect(failure.errorFor('password'), isNull);
      expect(failure.errorFor('name'), isNull);
      expect(const ValidationFailure('x').fieldErrors, isEmpty);
    });
  });

  group('UnexpectedFailure.fromError', () {
    test('wraps any error with its stack trace', () {
      final error = StateError('bug');
      final stackTrace = StackTrace.current;

      final failure = UnexpectedFailure.fromError(error, stackTrace);

      expect(failure.cause, same(error));
      expect(failure.stackTrace, same(stackTrace));
      expect(failure.message, const UnexpectedFailure().message);
    });

    test('returns an UnexpectedFailure unchanged', () {
      const original = UnexpectedFailure('Already wrapped');

      expect(
          identical(UnexpectedFailure.fromError(original), original), isTrue);
    });

    test('wraps other failures instead of passing them through', () {
      const network = NetworkFailure();

      final failure = UnexpectedFailure.fromError(network);

      expect(failure.cause, same(network));
    });
  });
}
