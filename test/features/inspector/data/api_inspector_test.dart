import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/logging/log_redactor.dart';
import 'package:symphony_core/src/features/inspector/inspector.dart';

class _Clock {
  DateTime now = DateTime(2024, 1, 1, 12);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

class _Serializable {
  const _Serializable(this.token, this.name);

  final String token;
  final String name;

  Map<String, Object?> toJson() => <String, Object?>{
        'token': token,
        'name': name,
      };

  @override
  String toString() => '_Serializable($token)';
}

class _Opaque {
  @override
  String toString() => 'secret-from-toString';
}

void main() {
  final uri = Uri.parse('https://api.example.com/v1/items');

  group('ApiInspector lifecycle', () {
    test('records calls newest first with timings', () {
      final clock = _Clock();
      final inspector = ApiInspector(clock: clock.call);
      addTearDown(inspector.dispose);

      final first = inspector.startCall(method: 'get', uri: uri)!;
      clock.advance(const Duration(milliseconds: 120));
      final second = inspector.startCall(method: 'POST', uri: uri)!;
      expect(second, greaterThan(first));
      expect(inspector.calls.map((call) => call.id), <int>[second, first]);
      expect(inspector.calls.last.method, 'GET');
      expect(inspector.pendingCount, 2);

      clock.advance(const Duration(milliseconds: 80));
      inspector.completeCall(
        first,
        statusCode: 200,
        statusMessage: 'OK',
        headers: const <String, dynamic>{
          'content-type': <String>['application/json'],
        },
        body: const <String, Object?>{'id': 7},
      );
      final completed = inspector.byId(first)!;
      expect(completed.isPending, isFalse);
      expect(completed.statusCode, 200);
      expect(completed.statusMessage, 'OK');
      expect(completed.duration, const Duration(milliseconds: 200));
      expect(completed.responseHeaders['content-type'], 'application/json');
      expect(completed.responseBody, '{\n  "id": 7\n}');
      expect(inspector.pendingCount, 1);
      expect(inspector.errorCount, 0);
    });

    test('failCall records the error and the optional response', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);
      final id = inspector.startCall(method: 'GET', uri: uri)!;
      inspector.failCall(
        id,
        error: 'Server unavailable',
        statusCode: 503,
        statusMessage: 'Service Unavailable',
        headers: const <String, dynamic>{'retry-after': '30'},
        body: '{"message": "maintenance"}',
      );
      final call = inspector.byId(id)!;
      expect(call.isPending, isFalse);
      expect(call.isError, isTrue);
      expect(call.error, 'Server unavailable');
      expect(call.statusCode, 503);
      expect(call.responseHeaders, <String, String>{'retry-after': '30'});
      expect(call.responseBody, '{\n  "message": "maintenance"\n}');
      expect(inspector.errorCount, 1);
    });

    test('ignores unknown ids and calls that already completed', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);
      final id = inspector.startCall(method: 'GET', uri: uri)!;
      inspector.completeCall(id, statusCode: 200);
      var notifications = 0;
      inspector.addListener(() => notifications++);

      inspector.failCall(id, error: 'late error');
      inspector.completeCall(id, statusCode: 500);
      inspector.completeCall(9999, statusCode: 200);

      expect(inspector.byId(id)!.statusCode, 200);
      expect(inspector.byId(id)!.error, isNull);
      expect(inspector.byId(9999), isNull);
      expect(notifications, 0);
    });

    test('completion can replace request headers and URI', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);
      final id = inspector.startCall(
        method: 'GET',
        uri: uri,
        headers: const <String, dynamic>{'accept': 'application/json'},
      )!;
      inspector.completeCall(
        id,
        statusCode: 200,
        requestHeaders: const <String, dynamic>{
          'accept': 'application/json',
          'Authorization': 'Bearer abc.def.ghi',
        },
        uri: Uri.parse('https://api.example.com/v1/items?api_key=k-123'),
      );
      final call = inspector.byId(id)!;
      expect(call.requestHeaders['Authorization'], '***');
      expect(
          call.uri.toString(), 'https://api.example.com/v1/items?api_key=***');
    });
  });

  group('ApiInspector storage', () {
    test('trims to maxEntries, dropping the oldest calls', () {
      final inspector = ApiInspector(maxEntries: 3);
      addTearDown(inspector.dispose);
      final ids = <int>[
        for (var i = 0; i < 5; i++)
          inspector.startCall(method: 'GET', uri: uri)!,
      ];
      expect(inspector.calls.map((call) => call.id), ids.reversed.take(3));
      // The dropped call completes without effect.
      inspector.completeCall(ids.first, statusCode: 200);
      expect(inspector.byId(ids.first), isNull);
      expect(inspector.calls, hasLength(3));
    });

    test('clear removes everything and never reuses ids', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);
      final before = inspector.startCall(method: 'GET', uri: uri)!;
      inspector.clear();
      expect(inspector.calls, isEmpty);
      inspector.completeCall(before, statusCode: 200);
      expect(inspector.calls, isEmpty);
      final after = inspector.startCall(method: 'GET', uri: uri)!;
      expect(after, greaterThan(before));
    });

    test('calls is an unmodifiable snapshot', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);
      inspector.startCall(method: 'GET', uri: uri);
      final snapshot = inspector.calls;
      expect(identical(snapshot, inspector.calls), isTrue);
      expect(() => snapshot.add(snapshot.first), throwsUnsupportedError);
      inspector.startCall(method: 'GET', uri: uri);
      expect(snapshot, hasLength(1));
      expect(inspector.calls, hasLength(2));
      expect(
        () => inspector.calls.first.requestHeaders['x'] = 'y',
        throwsUnsupportedError,
      );
    });

    test('disabled inspectors record nothing but finish calls in flight', () {
      final inspector = ApiInspector(enabled: false);
      addTearDown(inspector.dispose);
      expect(inspector.startCall(method: 'GET', uri: uri), isNull);
      expect(inspector.calls, isEmpty);

      inspector.enabled = true;
      final id = inspector.startCall(method: 'GET', uri: uri)!;
      inspector.enabled = false;
      inspector.completeCall(id, statusCode: 200);
      expect(inspector.byId(id)!.isPending, isFalse);
      expect(inspector.startCall(method: 'GET', uri: uri), isNull);
      expect(inspector.calls, hasLength(1));
    });

    test('notifies listeners after each change', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);
      var notifications = 0;
      inspector.addListener(() => notifications++);

      final id = inspector.startCall(method: 'GET', uri: uri)!;
      expect(notifications, 1);
      inspector.completeCall(id, statusCode: 200);
      expect(notifications, 2);
      inspector.enabled = false;
      expect(notifications, 3);
      inspector.enabled = false;
      expect(notifications, 3);
      inspector.clear();
      expect(notifications, 4);
      inspector.clear();
      expect(notifications, 4);
    });

    test('is safe to use after dispose', () {
      final inspector = ApiInspector();
      final id = inspector.startCall(method: 'GET', uri: uri)!;
      inspector.dispose();

      expect(inspector.startCall(method: 'GET', uri: uri), isNull);
      expect(
          () => inspector.completeCall(id, statusCode: 200), returnsNormally);
      expect(() => inspector.failCall(id, error: 'x'), returnsNormally);
      expect(() => inspector.clear(), returnsNormally);
      expect(() => inspector.enabled = false, returnsNormally);
      expect(() => inspector.addListener(() {}), returnsNormally);
      expect(inspector.dispose, returnsNormally);
    });
  });

  group('ApiInspector redaction', () {
    test('masks sensitive headers, query parameters and user info', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);
      final id = inspector.startCall(
        method: 'GET',
        uri: Uri.parse(
          'https://ada:pa55@api.example.com/me?access_token=abc&page=2',
        ),
        headers: const <String, dynamic>{
          'Authorization': 'Bearer abc',
          'X-Api-Key': 'k-1',
          'Cookie': 'sid=1',
          'Accept': 'application/json',
        },
      )!;
      final call = inspector.byId(id)!;
      expect(
        call.uri.toString(),
        'https://***@api.example.com/me?access_token=***&page=2',
      );
      expect(call.requestHeaders, <String, String>{
        'Authorization': '***',
        'X-Api-Key': '***',
        'Cookie': '***',
        'Accept': 'application/json',
      });
    });

    test('masks sensitive JSON fields in map and string bodies', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);
      final id = inspector.startCall(
        method: 'POST',
        uri: uri,
        body: const <String, Object?>{
          'email': 'ada@example.com',
          'password': 'hunter2',
          'profile': <String, Object?>{'refresh_token': 'r-1', 'age': 36},
        },
      )!;
      inspector.completeCall(
        id,
        statusCode: 200,
        body: '{"access_token":"t-1","user":{"id":1}}',
      );
      final call = inspector.byId(id)!;
      expect(call.requestBody, contains('"password": "***"'));
      expect(call.requestBody, contains('"refresh_token": "***"'));
      expect(call.requestBody, contains('"email": "ada@example.com"'));
      expect(call.requestBody, isNot(contains('hunter2')));
      expect(call.responseBody, contains('"access_token": "***"'));
      expect(call.responseBody, isNot(contains('t-1')));
    });

    test('masks credentials, URLs and key=value pairs in free text', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);
      final id = inspector.startCall(
        method: 'POST',
        uri: uri,
        body: 'user=ada&password=hunter2&remember=true',
      )!;
      inspector.failCall(
        id,
        error: 'HttpException: closed, uri = '
            'https://api.example.com/x?token=abc123 '
            'header Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload '
            "{'secret': 's3cr3t', 'code': 42}",
      );
      final call = inspector.byId(id)!;
      expect(call.requestBody, 'user=ada&password=***&remember=true');
      final error = call.error!;
      expect(error, contains('https://api.example.com/x?token=***'));
      expect(error, isNot(contains('abc123')));
      expect(error, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(error, contains("'secret': '***'"));
      expect(error, contains("'code': 42"));
    });

    test('masks secrets in truncated JSON', () {
      final inspector = ApiInspector(maxBodyLength: 40);
      addTearDown(inspector.dispose);
      final id = inspector.startCall(method: 'GET', uri: uri)!;
      // Invalid JSON (cut by the server or a proxy) is redacted as text.
      inspector.completeCall(
        id,
        statusCode: 200,
        body: '{"items": [1, 2], "token": "abcdef", "next": "${'x' * 80}',
      );
      final body = inspector.byId(id)!.responseBody!;
      expect(body, contains('"token": "***"'));
      expect(body, isNot(contains('abcdef')));
      expect(body, contains('[truncated'));
    });

    test('truncates long bodies', () {
      final inspector = ApiInspector(maxBodyLength: 10);
      addTearDown(inspector.dispose);
      final id = inspector.startCall(
        method: 'POST',
        uri: uri,
        body: 'a' * 25,
      )!;
      expect(
        inspector.byId(id)!.requestBody,
        '${'a' * 10}… [truncated 15 chars]',
      );
    });

    test('honours captureRequestBodies and captureResponseBodies', () {
      final inspector = ApiInspector(
        captureRequestBodies: false,
        captureResponseBodies: false,
      );
      addTearDown(inspector.dispose);
      final id = inspector.startCall(
        method: 'POST',
        uri: uri,
        body: const <String, Object?>{'a': 1},
      )!;
      inspector.completeCall(id, statusCode: 200, body: 'ok');
      final call = inspector.byId(id)!;
      expect(call.requestBody, isNull);
      expect(call.responseBody, isNull);
    });

    test('uses custom sensitive keys and masks', () {
      final inspector = ApiInspector(
        redactor: const LogRedactor(
          sensitiveKeys: <String>{'pin'},
          mask: '[hidden]',
        ),
      );
      addTearDown(inspector.dispose);
      final id = inspector.startCall(
        method: 'POST',
        uri: Uri.parse('https://api.example.com/pay?pin=1234'),
        body: const <String, Object?>{'pin': '1234', 'amount': 10},
      )!;
      final call = inspector.byId(id)!;
      expect(call.uri.queryParameters['pin'], '[hidden]');
      expect(call.uri.toString(), isNot(contains('1234')));
      expect(call.requestBody, contains('"pin": "[hidden]"'));
      expect(call.requestBody, contains('"amount": 10'));
    });
  });

  group('ApiInspector body rendering', () {
    test('summarizes binary, stream and multipart bodies', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);

      final binary = inspector.startCall(
        method: 'PUT',
        uri: uri,
        body: Uint8List.fromList(<int>[1, 2, 3, 4]),
      )!;
      final stream = inspector.startCall(
        method: 'PUT',
        uri: uri,
        body: Stream<List<int>>.value(const <int>[1, 2]),
      )!;
      final form = inspector.startCall(
        method: 'POST',
        uri: uri,
        body: const ApiCallFormData(
          fields: <MapEntry<String, String>>[
            MapEntry<String, String>('name', 'Ada'),
            MapEntry<String, String>('password', 'hunter2'),
          ],
          files: <ApiCallFormFile>[
            ApiCallFormFile(field: 'avatar', filename: 'a.png', length: 3),
          ],
        ),
      )!;

      expect(inspector.byId(binary)!.requestBody, '[binary 4 bytes]');
      expect(inspector.byId(stream)!.requestBody, '[stream]');
      final multipart = inspector.byId(form)!;
      expect(multipart.requestBody, contains('"password": "***"'));
      expect(multipart.requestBody, contains('"avatar": "a.png (3 bytes)"'));
      expect(multipart.requestBody, isNot(contains('hunter2')));
      expect(
        multipart.requestFormData!.fields.last,
        isA<MapEntry<String, String>>()
            .having((field) => field.value, 'value', '***'),
      );
    });

    test('renders objects through toJson and hides opaque objects', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);
      final serializable = inspector.startCall(
        method: 'POST',
        uri: uri,
        body: const _Serializable('t-1', 'Ada'),
      )!;
      final opaque = inspector.startCall(
        method: 'POST',
        uri: uri,
        body: _Opaque(),
      )!;
      final rendered = inspector.byId(serializable)!.requestBody!;
      expect(rendered, contains('"token": "***"'));
      expect(rendered, contains('"name": "Ada"'));
      expect(inspector.byId(opaque)!.requestBody, '[_Opaque]');
    });

    test('stores no body for null or empty content', () {
      final inspector = ApiInspector();
      addTearDown(inspector.dispose);
      final id = inspector.startCall(method: 'GET', uri: uri, body: '')!;
      inspector.completeCall(id, statusCode: 204);
      expect(inspector.byId(id)!.requestBody, isNull);
      expect(inspector.byId(id)!.responseBody, isNull);
    });
  });
}
