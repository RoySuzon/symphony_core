import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/inspector/inspector.dart';
import 'package:symphony_core/src/features/networking/domain/api_request_options.dart';

typedef _Handler = FutureOr<ResponseBody> Function(RequestOptions options);

/// Answers requests with [handler] after draining the request body.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final _Handler handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) await requestStream.drain<void>();
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

void main() {
  late ApiInspector inspector;
  late Dio dio;

  Dio createDio(_Handler handler, {List<Interceptor> after = const []}) {
    final client = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..httpClientAdapter = _FakeAdapter(handler)
      ..interceptors.add(ApiInspectorInterceptor(inspector))
      ..interceptors.addAll(after);
    addTearDown(client.close);
    return client;
  }

  setUp(() {
    inspector = ApiInspector();
  });

  tearDown(() => inspector.dispose());

  test('records a successful call with its response', () async {
    dio = createDio(
      (_) => ResponseBody.fromString(
        '{"id": 1, "access_token": "t-1"}',
        200,
        statusMessage: 'OK',
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          'set-cookie': <String>['sid=abc'],
        },
      ),
    );

    final response = await dio.get<Object?>(
      '/users/1',
      queryParameters: <String, Object?>{'token': 'secret', 'page': 2},
    );

    final call = inspector.calls.single;
    expect(call.method, 'GET');
    expect(call.isPending, isFalse);
    expect(call.isSuccessful, isTrue);
    expect(call.statusCode, 200);
    expect(call.statusMessage, 'OK');
    expect(call.path, '/users/1');
    expect(call.uri.queryParameters, <String, String>{
      'token': '***',
      'page': '2',
    });
    expect(call.uri.toString(), isNot(contains('secret')));
    expect(call.responseHeaders['set-cookie'], '***');
    expect(call.responseBody, contains('"id": 1'));
    expect(call.responseBody, contains('"access_token": "***"'));
    expect(call.responseBody, isNot(contains('t-1')));
    expect(ApiInspectorInterceptor.callIdOf(response.requestOptions), call.id);
  });

  test('masks headers added by interceptors running afterwards', () async {
    dio = createDio(
      (_) => _json(<String, Object?>{'ok': true}),
      after: <Interceptor>[
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.headers['Authorization'] = 'Bearer super-secret-token';
            handler.next(options);
          },
        ),
      ],
    );

    await dio.get<Object?>('/me',
        options: Options(headers: <String, Object?>{
          'X-Request-Id': 'r-1',
        }));

    final call = inspector.calls.single;
    expect(call.requestHeaders['Authorization'], '***');
    expect(call.requestHeaders['X-Request-Id'], 'r-1');
    expect(call.requestHeaders.values, isNot(contains(contains('super'))));
  });

  test('masks passwords in JSON request bodies', () async {
    dio = createDio((_) => _json(<String, Object?>{'ok': true}));

    await dio.post<Object?>(
      '/auth/login',
      data: <String, Object?>{
        'email': 'ada@example.com',
        'password': 'hunter2'
      },
    );

    final call = inspector.calls.single;
    expect(call.method, 'POST');
    expect(call.requestBody, contains('"email": "ada@example.com"'));
    expect(call.requestBody, contains('"password": "***"'));
    expect(call.requestBody, isNot(contains('hunter2')));
    expect(call.requestContentType, startsWith(Headers.jsonContentType));
  });

  test('parses and masks url-encoded request bodies', () async {
    dio = createDio((_) => _json(<String, Object?>{'ok': true}));

    await dio.post<Object?>(
      '/oauth/token',
      data: 'grant_type=password&username=ada&password=hunter%202',
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    final body = inspector.calls.single.requestBody!;
    expect(body, contains('"grant_type": "password"'));
    expect(body, contains('"password": "***"'));
    expect(body, isNot(contains('hunter')));
  });

  test('records 4xx and 5xx responses as failures', () async {
    dio = createDio(
      (options) => options.path.contains('missing')
          ? _json(<String, Object?>{'error': 'not found'}, status: 404)
          : _json(<String, Object?>{'error': 'boom'}, status: 500),
    );

    await expectLater(
      dio.get<Object?>('/missing'),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      dio.get<Object?>('/explode'),
      throwsA(isA<DioException>()),
    );

    final server = inspector.calls.first;
    final client = inspector.calls.last;
    expect(client.statusCode, 404);
    expect(client.isError, isTrue);
    expect(client.error, contains('[badResponse]'));
    expect(client.responseBody, contains('"error": "not found"'));
    expect(ApiCallStatusFilter.clientError.matches(client), isTrue);
    expect(server.statusCode, 500);
    expect(ApiCallStatusFilter.serverError.matches(server), isTrue);
    expect(inspector.errorCount, 2);
  });

  test('records connection errors without a response', () async {
    dio = createDio(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'The connection errored: Connection refused',
        error: 'SocketException: Connection refused',
      ),
    );

    await expectLater(
      dio.get<Object?>('/offline'),
      throwsA(isA<DioException>()),
    );

    final call = inspector.calls.single;
    expect(call.isPending, isFalse);
    expect(call.statusCode, isNull);
    expect(call.error, startsWith('[connectionError] The connection errored'));
    expect(call.error, contains('SocketException'));
    expect(ApiCallStatusFilter.failed.matches(call), isTrue);
  });

  test('summarizes FormData without file contents', () async {
    dio = createDio((_) => _json(<String, Object?>{'ok': true}));

    await dio.post<Object?>(
      '/upload',
      data: FormData.fromMap(<String, Object?>{
        'name': 'Ada',
        'password': 'p@ss-secret',
        'avatar': MultipartFile.fromBytes(
          <int>[1, 2, 3],
          filename: 'avatar.png',
        ),
      }),
    );

    final call = inspector.calls.single;
    final form = call.requestFormData!;
    expect(
      form.fields.map((field) => '${field.key}=${field.value}'),
      <String>['name=Ada', 'password=***'],
    );
    expect(form.files.single.field, 'avatar');
    expect(form.files.single.filename, 'avatar.png');
    expect(form.files.single.length, 3);
    expect(call.requestBody, contains('"avatar": "avatar.png (3 bytes'));
    expect(call.requestBody, isNot(contains('p@ss-secret')));
    // The final multipart header (with its boundary) is read at completion.
    expect(call.requestContentType, contains('boundary='));
  });

  test('summarizes binary and streamed bodies', () async {
    dio = createDio(
      (options) => ResponseBody.fromBytes(
        <int>[9, 8, 7, 6, 5],
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/octet-stream'],
        },
      ),
    );

    await dio.put<List<int>>(
      '/blob',
      data: Uint8List.fromList(<int>[1, 2, 3, 4]),
      options: Options(
        contentType: 'application/octet-stream',
        responseType: ResponseType.bytes,
      ),
    );
    await dio.put<Object?>(
      '/stream',
      data: Stream<List<int>>.value(<int>[1, 2]),
      options: Options(
        contentType: 'application/octet-stream',
        headers: <String, Object?>{Headers.contentLengthHeader: 2},
        responseType: ResponseType.stream,
      ),
    );

    final stream = inspector.calls.first;
    final binary = inspector.calls.last;
    expect(binary.requestBody, '[binary 4 bytes]');
    expect(binary.responseBody, '[binary 5 bytes]');
    expect(stream.requestBody, '[stream]');
    expect(stream.responseBody, '[stream]');
  });

  test('skips requests with inspect: false', () async {
    dio = createDio((_) => _json(<String, Object?>{'ok': true}));

    final response = await dio.get<Object?>(
      '/private',
      options: Options(
        extra: const ApiRequestOptions(inspect: false).toExtra(),
      ),
    );

    expect(response.statusCode, 200);
    expect(inspector.calls, isEmpty);
    expect(ApiInspectorInterceptor.callIdOf(response.requestOptions), isNull);
  });

  test('records nothing while the inspector is disabled', () async {
    inspector.enabled = false;
    dio = createDio((_) => _json(<String, Object?>{'ok': true}));

    await dio.get<Object?>('/a');

    expect(inspector.calls, isEmpty);
  });

  test('closes an attempt that is retried before it completed', () async {
    var attempts = 0;
    late Dio retrying;
    retrying = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..httpClientAdapter = _FakeAdapter(
        (_) => ++attempts == 1
            ? _json(<String, Object?>{'error': 'busy'}, status: 503)
            : _json(<String, Object?>{'ok': true}),
      )
      // A retry interceptor placed BEFORE the inspector resolves the error,
      // so the inspector never sees the first failure.
      ..interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) async {
            if (error.requestOptions.extra['retried'] == true) {
              handler.next(error);
              return;
            }
            error.requestOptions.extra['retried'] = true;
            try {
              handler
                  .resolve(await retrying.fetch<Object?>(error.requestOptions));
            } on DioException catch (retryError) {
              handler.next(retryError);
            }
          },
        ),
      )
      ..interceptors.add(ApiInspectorInterceptor(inspector));
    addTearDown(retrying.close);

    final response = await retrying.get<Object?>('/busy');

    expect(response.statusCode, 200);
    expect(inspector.calls, hasLength(2));
    final retry = inspector.calls.first;
    final firstAttempt = inspector.calls.last;
    expect(retry.statusCode, 200);
    expect(firstAttempt.isPending, isFalse);
    expect(
      firstAttempt.error,
      ApiInspectorInterceptor.defaultRetriedCallMessage,
    );
  });

  test('never throws, even when the inspector is disposed', () async {
    dio = createDio((_) => _json(<String, Object?>{'ok': true}));
    inspector.dispose();

    final response = await dio.get<Object?>('/after-dispose');

    expect(response.statusCode, 200);
    expect(inspector.calls, isEmpty);
  });

  test('works with unmodifiable extras', () async {
    dio = createDio((_) => _json(<String, Object?>{'ok': true}));

    final response = await dio.fetch<Object?>(
      RequestOptions(
        path: '/const-extra',
        baseUrl: 'https://api.example.com',
        extra: const <String, Object?>{'feature': 'x'},
      ),
    );

    expect(response.statusCode, 200);
    final call = inspector.calls.single;
    expect(call.isPending, isFalse);
    expect(call.statusCode, 200);
  });

  test('describeError combines type, message and cause', () {
    final options = RequestOptions(path: '/x');
    expect(
      ApiInspectorInterceptor.describeError(
        DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
          message: 'Timed out',
        ),
      ),
      '[receiveTimeout] Timed out',
    );
    expect(
      ApiInspectorInterceptor.describeError(
        DioException(requestOptions: options, error: StateError('bad')),
      ),
      '[unknown] Bad state: bad',
    );
  });
}
