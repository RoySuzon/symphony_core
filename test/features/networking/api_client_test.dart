import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show BaseOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/config/symphony_config.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/core/logging/symphony_logger.dart';
import 'package:symphony_core/src/features/inspector/data/api_inspector.dart';
import 'package:symphony_core/src/features/inspector/data/api_inspector_interceptor.dart';
import 'package:symphony_core/src/features/networking/networking.dart';

import 'support/networking_fakes.dart';

class _User {
  const _User(this.id, this.name);

  factory _User.fromJson(Object? json) {
    final map = json! as Map<String, dynamic>;
    return _User(map['id'] as int, map['name'] as String);
  }

  final int id;
  final String name;
}

class _RecordingInterceptor extends Interceptor {
  _RecordingInterceptor(this.name, this.calls);

  final String name;
  final List<String> calls;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls.add(name);
    options.headers['X-Interceptor-$name'] = 'seen';
    handler.next(options);
  }
}

void main() {
  late FakeHttpClientAdapter adapter;

  setUp(() {
    adapter = FakeHttpClientAdapter();
  });

  ApiClient buildClient({
    SymphonyConfig? config,
    AuthTokenDelegate? delegate,
    List<Interceptor> interceptors = const <Interceptor>[],
    List<HeaderProvider> headerProviders = const <HeaderProvider>[],
    SymphonyLogger? logger,
    ApiInspector? inspector,
  }) {
    final client = ApiClient(
      config: config ?? testConfig(),
      httpClientAdapter: adapter,
      tokenDelegate: delegate == null ? null : () => delegate,
      interceptors: interceptors,
      headerProviders: headerProviders,
      logger: logger,
      inspector: inspector,
    );
    addTearDown(client.close);
    return client;
  }

  group('base URL', () {
    test('uses the configured base URL', () async {
      final client = buildClient();

      await client.get<void>('/users');

      expect(client.baseUrl, testBaseUrl);
      expect(adapter.requests.single.uri.toString(), '$testBaseUrl/users');
    });

    test('can be changed at runtime and notifies listeners', () async {
      final client = buildClient();
      final values = <String>[];
      client.baseUrlListenable.addListener(
        () => values.add(client.baseUrlListenable.value),
      );

      client.updateBaseUrl('https://staging.example.com/v2');
      await client.get<void>('/users');
      client.resetBaseUrl();
      await client.get<void>('/users');

      expect(values, <String>['https://staging.example.com/v2', testBaseUrl]);
      expect(
        adapter.requests.map((request) => request.uri.toString()),
        <String>[
          'https://staging.example.com/v2/users',
          '$testBaseUrl/users',
        ],
      );
    });

    test('rejects relative base URLs', () {
      final client = buildClient();

      expect(() => client.updateBaseUrl('api/v1'), throwsArgumentError);
      expect(
        () => ApiClient(config: testConfig(baseUrl: 'not a url')),
        throwsArgumentError,
      );
      expect(client.baseUrl, testBaseUrl);
    });
  });

  group('headers', () {
    test('sends default, dynamic and per-request headers by precedence',
        () async {
      final client = buildClient(
        config: testConfig(
          defaultHeaders: <String, String>{
            'X-App': 'symphony',
            'Accept-Language': 'en',
          },
        ),
        headerProviders: <HeaderProvider>[
          () => <String, String>{'Accept-Language': 'fr', 'X-Version': '1'},
          () async => <String, String>{'X-Async': 'yes'},
        ],
      );
      client.setHeader('X-Tenant', 'acme');

      await client.get<void>(
        '/me',
        options: const ApiRequestOptions(
          headers: <String, String>{'x-version': '2'},
        ),
      );

      expect(adapter.headerOf(0, 'X-App'), 'symphony');
      expect(adapter.headerOf(0, 'X-Tenant'), 'acme');
      expect(adapter.headerOf(0, 'Accept-Language'), 'fr');
      expect(adapter.headerOf(0, 'X-Async'), 'yes');
      expect(adapter.headerOf(0, 'X-Version'), '2');
    });

    test('setHeader updates and removes default headers', () async {
      final client = buildClient();

      client.setHeader('X-Debug', '1');
      expect(client.headers['x-debug'], '1');
      await client.get<void>('/a');

      client.setHeader('x-debug', null);
      expect(client.headers.containsKey('X-Debug'), isFalse);
      await client.get<void>('/b');

      expect(adapter.headerOf(0, 'X-Debug'), '1');
      expect(adapter.headerOf(1, 'X-Debug'), isNull);
      expect(() => client.headers['X'] = 'y', throwsUnsupportedError);
    });

    test('header providers can be added and removed at runtime', () async {
      final client = buildClient();
      Map<String, String> provider() => <String, String>{'X-Trace': 't-1'};

      client.addHeaderProvider(provider);
      await client.get<void>('/a');
      expect(client.removeHeaderProvider(provider), isTrue);
      await client.get<void>('/b');

      expect(adapter.headerOf(0, 'X-Trace'), 't-1');
      expect(adapter.headerOf(1, 'X-Trace'), isNull);
      expect(client.headerProviders, isEmpty);
    });

    test('a failing header provider is logged and skipped', () async {
      final sink = CapturingLogSink();
      final client = buildClient(
        logger: capturingLogger(sink),
        headerProviders: <HeaderProvider>[
          () => throw StateError('secret-value'),
          () => <String, String>{'X-Ok': 'yes'},
        ],
      );

      final response = await client.get<Map<String, dynamic>>('/a');

      expect(response.statusCode, 200);
      expect(adapter.headerOf(0, 'X-Ok'), 'yes');
      expect(sink.text, contains('Header provider #0 failed (StateError)'));
      expect(sink.text, isNot(contains('secret-value')));
    });
  });

  group('timeouts', () {
    test('come from the configuration and can be updated', () async {
      final client = buildClient();
      expect(client.dio.options.connectTimeout, const Duration(seconds: 30));

      client.updateTimeouts(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 6),
        sendTimeout: const Duration(seconds: 7),
      );
      await client.get<void>('/a');

      final request = adapter.requests.single;
      expect(request.connectTimeout, const Duration(seconds: 5));
      expect(request.receiveTimeout, const Duration(seconds: 6));
      expect(request.sendTimeout, const Duration(seconds: 7));
    });

    test('can be overridden per request, including the connect timeout',
        () async {
      final client = buildClient();

      await client.post<void>(
        '/a',
        data: <String, Object?>{'x': 1},
        options: const ApiRequestOptions(
          connectTimeout: Duration(seconds: 1),
          receiveTimeout: Duration(seconds: 2),
          sendTimeout: Duration(seconds: 3),
        ),
      );

      final request = adapter.requests.single;
      expect(request.connectTimeout, const Duration(seconds: 1));
      expect(request.receiveTimeout, const Duration(seconds: 2));
      expect(request.sendTimeout, const Duration(seconds: 3));
      expect(client.dio.options.connectTimeout, const Duration(seconds: 30));
    });
  });

  group('requests and responses', () {
    test('send the method, query, JSON body and per-request extras', () async {
      adapter.responder = (options, body) => jsonBody(
            <String, Object?>{'ok': true},
            statusCode: 201,
            headers: <String, List<String>>{
              'X-Request-Id': <String>['42'],
            },
          );
      final client = buildClient();

      final response = await client.patch<Map<String, dynamic>>(
        '/users/1',
        data: <String, Object?>{'name': 'Jane'},
        queryParameters: <String, dynamic>{'expand': 'roles'},
        options: const ApiRequestOptions(
          extra: <String, Object?>{'custom': 'value'},
          inspect: false,
        ),
      );

      final request = adapter.requests.single;
      expect(request.method, 'PATCH');
      expect(request.uri.toString(), '$testBaseUrl/users/1?expand=roles');
      expect(jsonDecode(utf8.decode(adapter.bodies.single)), <String, Object?>{
        'name': 'Jane',
      });
      expect(request.extra['custom'], 'value');
      expect(request.extra[SymphonyRequestExtras.inspect], isFalse);
      expect(request.extra[SymphonyRequestExtras.requiresAuth], isTrue);
      expect(response.data, <String, dynamic>{'ok': true});
      expect(response.statusCode, 201);
      expect(response.isSuccessful, isTrue);
      expect(response.headers['x-request-id'], <String>['42']);
      expect(response.header('X-REQUEST-ID'), '42');
      expect(
          response.requestUri.toString(), '$testBaseUrl/users/1?expand=roles');
    });

    test('every verb uses the expected HTTP method', () async {
      final client = buildClient();

      await client.get<void>('/r');
      await client.post<void>('/r');
      await client.put<void>('/r');
      await client.patch<void>('/r');
      await client.delete<void>('/r');
      await client.request<void>('/r', method: 'head');

      expect(
        adapter.requests.map((request) => request.method),
        <String>['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'],
      );
    });

    test('decodes the body with the decoder', () async {
      adapter.responder =
          (_, __) => jsonBody(<String, Object?>{'id': 7, 'name': 'Jane'});
      final client = buildClient();

      final response = await client.get<_User>('/me', decoder: _User.fromJson);

      expect(response.data.id, 7);
      expect(response.data.name, 'Jane');
    });

    test('a failing decoder throws a ParsingFailure keeping the cause',
        () async {
      adapter.responder = (_, __) => jsonBody(<String, Object?>{'id': 'x'});
      final client = buildClient();

      final failure = await _failureOf(
        client.get<_User>('/me', decoder: _User.fromJson),
      );

      expect(failure, isA<ParsingFailure>());
      expect(failure.cause, isA<TypeError>());
    });

    test('a decoder throwing another error still yields a ParsingFailure',
        () async {
      final client = buildClient();

      final failure = await _failureOf(
        client.get<int>('/me', decoder: (_) => throw StateError('boom')),
      );

      expect(failure, isA<ParsingFailure>());
      expect(failure.cause, isA<StateError>());
    });

    test('a decoder throwing a Failure propagates it unchanged', () async {
      final client = buildClient();
      const expected = ValidationFailure('Invalid payload');

      final failure = await _failureOf(
        client.get<int>('/me', decoder: (_) => throw expected),
      );

      expect(identical(failure, expected), isTrue);
    });

    test('a failed cast throws a ParsingFailure', () async {
      adapter.responder = (_, __) => jsonBody(<String, Object?>{'a': 1});
      final client = buildClient();

      final failure = await _failureOf(client.get<List<dynamic>>('/list'));

      expect(failure, isA<ParsingFailure>());
    });

    test('supports plain text responses', () async {
      adapter.responder = (_, __) => ResponseBody.fromString(
            'pong',
            200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>['text/plain'],
            },
          );
      final client = buildClient();

      final response = await client.request<String>(
        '/ping',
        responseType: ResponseType.plain,
      );

      expect(response.data, 'pong');
    });
  });

  group('errors', () {
    test('HTTP errors are mapped to failures', () async {
      adapter.responder = (options, _) => switch (options.path) {
            '/missing' => jsonBody(
                <String, Object?>{'message': 'No such user'},
                statusCode: 404,
              ),
            '/invalid' => jsonBody(
                <String, Object?>{
                  'message': 'Invalid data',
                  'errors': <String, Object?>{
                    'email': <String>['is invalid'],
                  },
                },
                statusCode: 422,
              ),
            _ => jsonBody(<String, Object?>{}, statusCode: 503),
          };
      final client = buildClient();

      final notFound = await _failureOf(client.get<void>('/missing'));
      final invalid = await _failureOf(client.post<void>('/invalid'));
      final server = await _failureOf(client.get<void>('/down'));

      expect(notFound, isA<NotFoundFailure>());
      expect(notFound.message, 'No such user');
      expect(invalid, isA<ValidationFailure>());
      expect((invalid as ValidationFailure).errorFor('email'), 'is invalid');
      expect(server, isA<ServerFailure>());
      expect(server.statusCode, 503);
      expect(server.cause, isA<DioException>());
    });

    test('connection problems become a NetworkFailure', () async {
      adapter.responder = (options, _) => throw DioException.connectionError(
            requestOptions: options,
            reason: 'offline',
          );
      final client = buildClient();

      expect(await _failureOf(client.get<void>('/a')), isA<NetworkFailure>());
    });

    test('cancelled requests become a CancelledFailure', () async {
      final gate = Completer<ResponseBody>();
      adapter.responder = (_, __) => gate.future;
      final client = buildClient();
      final cancelToken = CancelToken();

      final pending = _failureOf(
        client.get<void>('/slow', cancelToken: cancelToken),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cancelToken.cancel('user left');

      expect(await pending, isA<CancelledFailure>());
      gate.complete(jsonBody(<String, Object?>{}));
    });

    test('a custom error mapper is used', () async {
      adapter.responder =
          (_, __) => jsonBody(<String, Object?>{}, statusCode: 500);
      final client = ApiClient(
        config: testConfig(),
        httpClientAdapter: adapter,
        errorMapper: const _TeapotMapper(),
      );
      addTearDown(client.close);

      final failure = await _failureOf(client.get<void>('/a'));

      expect(failure.message, 'teapot');
      expect(client.mapError(StateError('x'), StackTrace.current).message,
          'teapot');
    });
  });

  group('upload', () {
    test('sends files and fields as multipart form data', () async {
      final client = buildClient();
      final progress = <int>[];

      await client.upload<void>(
        '/documents',
        files: const <UploadFile>[
          UploadFile.fromBytes(
            <int>[1, 2, 3],
            filename: 'report.pdf',
            field: 'document',
            contentType: 'application/pdf',
          ),
        ],
        fields: <String, Object?>{
          'title': 'Q3',
          'tags': <String>['a', 'b'],
          'meta': <String, Object?>{'year': 2026},
          'skipped': null,
        },
        onSendProgress: (sent, total) => progress.add(sent),
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(
        '${request.headers[Headers.contentTypeHeader]}',
        startsWith('multipart/form-data; boundary='),
      );
      final formData = request.data as FormData;
      expect(
        formData.fields.map((field) => '${field.key}=${field.value}'),
        <String>['title=Q3', 'tags=a', 'tags=b', 'meta={"year":2026}'],
      );
      final file = formData.files.single;
      expect(file.key, 'document');
      expect(file.value.filename, 'report.pdf');
      expect(file.value.contentType.toString(), 'application/pdf');
      expect(file.value.length, 3);
      final body = latin1.decode(adapter.bodies.single);
      expect(body, contains('name="document"; filename="report.pdf"'));
      expect(body, contains('content-type: application/pdf'));
      expect(progress, isNotEmpty);
    });

    test('reads path based files', () async {
      final directory = Directory.systemTemp.createTempSync('symphony_upload');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}photo.png')
        ..writeAsBytesSync(<int>[9, 8, 7, 6]);
      final client = buildClient();

      await client.upload<void>(
        '/photos',
        method: 'PUT',
        files: <UploadFile>[
          UploadFile.fromPath(file.path, contentType: 'image/png'),
        ],
      );

      final request = adapter.requests.single;
      expect(request.method, 'PUT');
      final upload = (request.data as FormData).files.single;
      expect(upload.key, 'file');
      expect(upload.value.filename, 'photo.png');
      expect(upload.value.length, 4);
    });

    test('an invalid content type fails without sending the request', () async {
      final client = buildClient();

      final failure = await _failureOf(
        client.upload<void>(
          '/documents',
          files: const <UploadFile>[
            UploadFile.fromBytes(
              <int>[1],
              filename: 'a.bin',
              contentType: 'not-a-mime-type',
            ),
          ],
        ),
      );

      expect(failure, isA<UnexpectedFailure>());
      expect(failure.cause, isA<ArgumentError>());
      expect(adapter.requests, isEmpty);
    });
  });

  group('download', () {
    test('downloadBytes returns the raw bytes', () async {
      adapter.responder =
          (_, __) => ResponseBody.fromBytes(<int>[1, 2, 3, 4], 200);
      final client = buildClient();

      final response = await client.downloadBytes('/files/1');

      expect(response.data, <int>[1, 2, 3, 4]);
      expect(adapter.requests.single.responseType, ResponseType.bytes);
    });

    test('download writes the body to a file', () async {
      adapter.responder =
          (_, __) => ResponseBody.fromBytes(utf8.encode('hello file'), 200);
      final directory = Directory.systemTemp.createTempSync('symphony_dl');
      addTearDown(() => directory.deleteSync(recursive: true));
      final savePath = '${directory.path}${Platform.pathSeparator}out.txt';
      final client = buildClient();

      final response = await client.download('/files/1', savePath);

      expect(response.statusCode, 200);
      expect(File(savePath).readAsStringSync(), 'hello file');
    });

    test('a failed download throws a Failure and removes the file', () async {
      adapter.responder =
          (_, __) => jsonBody(<String, Object?>{}, statusCode: 404);
      final directory = Directory.systemTemp.createTempSync('symphony_dl');
      addTearDown(() => directory.deleteSync(recursive: true));
      final savePath = '${directory.path}${Platform.pathSeparator}out.txt';
      final client = buildClient();

      final failure = await _failureOf(client.download('/files/2', savePath));

      expect(failure, isA<NotFoundFailure>());
      expect(File(savePath).existsSync(), isFalse);
    });
  });

  group('interceptors', () {
    test('are installed in the documented order', () {
      final custom = _RecordingInterceptor('custom', <String>[]);
      final client = buildClient(
        config: testConfig(enableInspector: true, enableLogging: true),
        inspector: ApiInspector(),
        interceptors: <Interceptor>[custom],
      );

      final types = client.dio.interceptors.toList();
      final inspectorIndex = types.indexWhere(
        (interceptor) => interceptor is ApiInspectorInterceptor,
      );
      final loggingIndex = types.indexWhere(
        (interceptor) => interceptor is SecureLoggingInterceptor,
      );
      final customIndex = types.indexOf(custom);
      final headersIndex =
          types.indexWhere((interceptor) => interceptor is HeadersInterceptor);
      final authIndex = types.indexOf(client.authTokenInterceptor);
      final retryIndex = types.indexOf(client.retryInterceptor);

      expect(inspectorIndex, greaterThanOrEqualTo(0));
      expect(loggingIndex, greaterThan(inspectorIndex));
      expect(customIndex, greaterThan(loggingIndex));
      expect(headersIndex, greaterThan(customIndex));
      expect(authIndex, greaterThan(headersIndex));
      expect(retryIndex, greaterThan(authIndex));
      expect(retryIndex, types.length - 1);
    });

    test('the inspector is installed only when enabled and provided', () {
      int inspectors(ApiClient client) =>
          client.dio.interceptors.whereType<ApiInspectorInterceptor>().length;

      expect(inspectors(buildClient(inspector: ApiInspector())), 0);
      expect(
        inspectors(buildClient(config: testConfig(enableInspector: true))),
        0,
      );
      expect(
        inspectors(
          buildClient(
            config: testConfig(enableInspector: true),
            inspector: ApiInspector(),
          ),
        ),
        1,
      );
    });

    test('logging is installed only when enabled', () {
      int loggers(ApiClient client) =>
          client.dio.interceptors.whereType<SecureLoggingInterceptor>().length;

      expect(loggers(buildClient()), 0);
      expect(loggers(buildClient(config: testConfig(enableLogging: true))), 1);
    });

    test('custom interceptors run before token injection and can be removed',
        () async {
      final calls = <String>[];
      final first = _RecordingInterceptor('first', calls);
      final second = _RecordingInterceptor('second', calls);
      final delegate = FakeTokenDelegate(token: 'abc');
      String? authorizationSeenByCustom;
      final probe = InterceptorsWrapper(
        onRequest: (options, handler) {
          authorizationSeenByCustom =
              options.headers['Authorization'] as String?;
          handler.next(options);
        },
      );
      final client = buildClient(
        delegate: delegate,
        interceptors: <Interceptor>[first],
      );

      client
        ..addInterceptor(second)
        ..addInterceptor(second)
        ..addInterceptor(probe);
      await client.get<void>('/a');
      client.removeInterceptor(first);
      await client.get<void>('/b');

      expect(calls, <String>['first', 'second', 'second']);
      expect(client.interceptors, <Interceptor>[second, probe]);
      expect(authorizationSeenByCustom, isNull);
      expect(adapter.headerOf(0, 'X-Interceptor-first'), 'seen');
      expect(adapter.headerOf(0, 'Authorization'), 'Bearer abc');
      final installed = client.dio.interceptors.toList();
      expect(
        installed.indexOf(probe),
        lessThan(installed
            .whereType<HeadersInterceptor>()
            .map(installed.indexOf)
            .single),
      );
    });
  });

  group('close', () {
    test('is idempotent and rejects further calls with a Failure', () async {
      final client =
          ApiClient(config: testConfig(), httpClientAdapter: adapter);

      client
        ..close()
        ..close();
      final failure = await _failureOf(client.get<void>('/a'));

      expect(client.isClosed, isTrue);
      expect(failure, isA<UnexpectedFailure>());
      expect(failure.cause, isA<StateError>());
      expect(adapter.requests, isEmpty);
      expect(() => client.updateBaseUrl('https://other.example.com'),
          returnsNormally);
    });

    test('never closes an injected adapter but closes its own Dio', () {
      final injected =
          ApiClient(config: testConfig(), httpClientAdapter: adapter)
            ..close(force: true);
      final ownedAdapter = FakeHttpClientAdapter();
      final dio = Dio()..httpClientAdapter = ownedAdapter;
      final owned = ApiClient(config: testConfig(), dio: dio)..close();

      expect(injected.isClosed, isTrue);
      expect(adapter.closed, isFalse);
      expect(owned.dio, same(dio));
      expect(ownedAdapter.closed, isTrue);
    });

    test('an injected Dio keeps its options and receives the configuration',
        () async {
      final dio = Dio(BaseOptions(headers: <String, dynamic>{'X-Own': '1'}))
        ..httpClientAdapter = adapter;
      final client = ApiClient(
        config: testConfig(
          defaultHeaders: const <String, String>{'X-Config': '2'},
        ),
        dio: dio,
      );
      addTearDown(client.close);

      await client.get<void>('/a');

      expect(adapter.headerOf(0, 'X-Own'), '1');
      expect(adapter.headerOf(0, 'X-Config'), '2');
      expect(dio.options.baseUrl, testBaseUrl);
    });
  });
}

class _TeapotMapper extends ApiErrorMapper {
  const _TeapotMapper();

  @override
  Failure map(Object error, StackTrace stackTrace) =>
      const ServerFailure('teapot', statusCode: 418);
}

/// Awaits [future] and returns the [Failure] it throws.
Future<Failure> _failureOf(Future<Object?> future) async {
  try {
    await future;
  } on Failure catch (failure) {
    return failure;
  }
  fail('Expected the call to throw a Failure.');
}
