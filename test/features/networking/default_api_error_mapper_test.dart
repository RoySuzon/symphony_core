import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/networking/networking.dart';

import 'support/networking_fakes.dart';

void main() {
  const mapper = DefaultApiErrorMapper();
  final requestOptions = RequestOptions(path: '/resource');

  DioException dioError(
    DioExceptionType type, {
    Object? error,
    String? message,
  }) => DioException(
    requestOptions: requestOptions,
    type: type,
    error: error,
    message: message,
  );

  DioException httpError(int statusCode, [Object? data]) =>
      DioException.badResponse(
        statusCode: statusCode,
        requestOptions: requestOptions,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: statusCode,
          data: data,
        ),
      );

  Failure map(Object error) => mapper.map(error, StackTrace.current);

  group('transport errors', () {
    test('cancellation', () {
      expect(map(dioError(DioExceptionType.cancel)), isA<CancelledFailure>());
    });

    test('timeouts', () {
      for (final type in <DioExceptionType>[
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final failure = map(dioError(type));
        expect(failure, isA<TimeoutFailure>(), reason: '$type');
        expect(failure.cause, isA<DioException>());
      }
    });

    test('connection errors and bad certificates', () {
      final connection = map(dioError(DioExceptionType.connectionError));
      final certificate = map(dioError(DioExceptionType.badCertificate));

      expect(connection, isA<NetworkFailure>());
      expect(certificate, isA<NetworkFailure>());
      expect(
        certificate.message,
        'A secure connection to the server could not be established.',
      );
    });

    test('unknown errors are classified by their cause', () {
      expect(
        map(
          dioError(
            DioExceptionType.unknown,
            error: const FakeSocketException('Failed host lookup'),
          ),
        ),
        isA<NetworkFailure>(),
      );
      expect(
        map(
          dioError(
            DioExceptionType.unknown,
            message: 'HandshakeException: Connection terminated',
          ),
        ),
        isA<NetworkFailure>(),
      );
      expect(
        map(
          dioError(
            DioExceptionType.unknown,
            error: const FormatException('Unexpected character'),
          ),
        ),
        isA<ParsingFailure>(),
      );
      expect(
        map(dioError(DioExceptionType.unknown, error: StateError('bug'))),
        isA<UnexpectedFailure>(),
      );
    });

    test('a Failure wrapped by Dio is returned unchanged', () {
      const failure = AuthFailure('Account locked');

      expect(
        map(dioError(DioExceptionType.unknown, error: failure)),
        same(failure),
      );
    });
  });

  group('HTTP errors', () {
    test('map each status to the matching failure', () {
      expect(map(httpError(400)), isA<ValidationFailure>());
      expect(map(httpError(422)), isA<ValidationFailure>());
      expect(map(httpError(401)), isA<UnauthorizedFailure>());
      expect(map(httpError(403)), isA<ForbiddenFailure>());
      expect(map(httpError(404)), isA<NotFoundFailure>());
      expect(map(httpError(409)), isA<ServerFailure>());
      expect(map(httpError(500)), isA<ServerFailure>());
      expect(map(httpError(503)), isA<ServerFailure>());
    });

    test('keep the status code, the cause and the body', () {
      final failure = map(httpError(500, <String, Object?>{'trace': 'x'}));

      expect(failure.statusCode, 500);
      expect(failure.cause, isA<DioException>());
      expect((failure as ServerFailure).data, <String, Object?>{'trace': 'x'});
      expect(map(httpError(401)).statusCode, 401);
      expect(map(httpError(422)).statusCode, 422);
    });

    test('use sensible default messages', () {
      expect(map(httpError(400)).message, mapper.validationMessage);
      expect(map(httpError(401)).message, mapper.unauthorizedMessage);
      expect(map(httpError(403)).message, mapper.forbiddenMessage);
      expect(map(httpError(404)).message, mapper.notFoundMessage);
      expect(map(httpError(409)).message, mapper.clientErrorMessage);
      expect(map(httpError(502)).message, mapper.serverErrorMessage);
    });

    test('read the message from the usual body keys', () {
      String messageOf(Object? body) => map(httpError(409, body)).message;

      expect(messageOf(<String, Object?>{'message': 'A'}), 'A');
      expect(messageOf(<String, Object?>{'error_description': 'B'}), 'B');
      expect(messageOf(<String, Object?>{'error': 'C'}), 'C');
      expect(messageOf(<String, Object?>{'detail': 'D', 'title': 'T'}), 'D');
      expect(messageOf(<String, Object?>{'title': 'E'}), 'E');
      expect(messageOf(<String, Object?>{'msg': 'F'}), 'F');
      expect(
        messageOf(<String, Object?>{
          'error': <String, Object?>{'message': 'G', 'code': 'E_G'},
        }),
        'G',
      );
      expect(
        messageOf(<String, Object?>{
          'message': <String>['first problem', 'second problem'],
        }),
        'first problem',
      );
      expect(messageOf(jsonEncode(<String, Object?>{'message': 'H'})), 'H');
      expect(messageOf('Plain text problem'), 'Plain text problem');
      expect(
        messageOf('<html><body>Bad gateway</body></html>'),
        mapper.clientErrorMessage,
      );
      expect(messageOf(utf8.encode('{"message":"I"}')), 'I');
    });

    test('read machine readable codes', () {
      String? codeOf(Object? body) => map(httpError(400, body)).code;

      expect(codeOf(<String, Object?>{'code': 'E1'}), 'E1');
      expect(codeOf(<String, Object?>{'error_code': 42}), '42');
      expect(codeOf(<String, Object?>{'errorCode': 'E3'}), 'E3');
      expect(
        codeOf(<String, Object?>{
          'error': <String, Object?>{'code': 'E4'},
        }),
        'E4',
      );
      expect(
        codeOf(<String, Object?>{
          'error': 'invalid_grant',
          'error_description': 'Bad credentials',
        }),
        'invalid_grant',
      );
      expect(codeOf(<String, Object?>{'message': 'no code'}), isNull);
    });

    test('parse field errors from a map', () {
      final failure =
          map(
                httpError(422, <String, Object?>{
                  'message': 'The given data was invalid.',
                  'errors': <String, Object?>{
                    'email': <String>['is invalid', 'is taken'],
                    'name': 'is required',
                    'address': <String, Object?>{
                      'city': <String>['is required'],
                    },
                    'phone': <Object?>[
                      <String, Object?>{'message': 'is too short'},
                    ],
                  },
                }),
              )
              as ValidationFailure;

      expect(failure.message, 'The given data was invalid.');
      expect(failure.fieldErrors, <String, List<String>>{
        'email': <String>['is invalid', 'is taken'],
        'name': <String>['is required'],
        'address.city': <String>['is required'],
        'phone': <String>['is too short'],
      });
      expect(failure.errorFor('email'), 'is invalid');
    });

    test('parse field errors from a list', () {
      final failure =
          map(
                httpError(400, <String, Object?>{
                  'errors': <Object?>[
                    <String, Object?>{
                      'field': 'email',
                      'message': 'is invalid',
                    },
                    <String, Object?>{
                      'param': 'age',
                      'msg': 'must be positive',
                    },
                    <String, Object?>{
                      'path': <String>['items', '0', 'sku'],
                      'message': 'is unknown',
                    },
                    <String, Object?>{
                      'source': <String, Object?>{
                        'pointer': '/data/attributes/title',
                      },
                      'detail': 'is blank',
                    },
                    'ignored',
                  ],
                }),
              )
              as ValidationFailure;

      expect(failure.message, mapper.validationMessage);
      expect(failure.fieldErrors, <String, List<String>>{
        'email': <String>['is invalid'],
        'age': <String>['must be positive'],
        'items.0.sku': <String>['is unknown'],
        'title': <String>['is blank'],
      });
    });

    test('server messages can be disabled and defaults overridden', () {
      const localized = DefaultApiErrorMapper(
        useServerMessages: false,
        notFoundMessage: 'Introuvable',
      );

      final failure = localized.map(
        httpError(404, <String, Object?>{'message': 'Not here'}),
        StackTrace.current,
      );

      expect(failure.message, 'Introuvable');
    });

    test('custom message, code and field error keys', () {
      const custom = DefaultApiErrorMapper(
        messageKeys: <String>['reason'],
        codeKeys: <String>['kind'],
        fieldErrorsKey: 'violations',
      );

      final failure =
          custom.map(
                httpError(400, <String, Object?>{
                  'reason': 'Rejected',
                  'kind': 'E_RULE',
                  'violations': <String, Object?>{
                    'email': <String>['bad'],
                  },
                }),
                StackTrace.current,
              )
              as ValidationFailure;

      expect(failure.message, 'Rejected');
      expect(failure.code, 'E_RULE');
      expect(failure.fieldErrors, <String, List<String>>{
        'email': <String>['bad'],
      });
    });
  });

  group('other errors', () {
    test('a Failure is returned unchanged', () {
      const failure = StorageFailure('disk full');

      expect(map(failure), same(failure));
    });

    test('FormatException and TypeError become a ParsingFailure', () {
      final typeError = _captureTypeError();

      expect(map(const FormatException('bad json')), isA<ParsingFailure>());
      expect(map(typeError), isA<ParsingFailure>());
      expect(map(typeError).cause, same(typeError));
    });

    test('anything else becomes an UnexpectedFailure', () {
      final error = StateError('boom');

      final failure = map(error);

      expect(failure, isA<UnexpectedFailure>());
      expect(failure.cause, same(error));
    });

    test('never throws, whatever the payload', () {
      final weird = <Object?>[
        <Object?, Object?>{1: 2, null: <Object?>[]},
        <String, Object?>{
          'errors': <String, Object?>{'a': 1, 'b': null},
        },
        <String, Object?>{'message': 42},
        <Object?>[null, 1, <String, Object?>{}],
        '{not json',
        ResponseBody.fromString('streamed', 500),
      ];
      for (final body in weird) {
        expect(() => map(httpError(400, body)), returnsNormally);
        expect(() => map(httpError(500, body)), returnsNormally);
      }
      expect(
        map(httpError(400, '{not json')).message,
        mapper.validationMessage,
      );
    });
  });
}

TypeError _captureTypeError([Object value = 'text']) {
  try {
    expect(value as int, isNull);
  } on TypeError catch (error) {
    return error;
  }
  throw StateError('Expected a TypeError.');
}
