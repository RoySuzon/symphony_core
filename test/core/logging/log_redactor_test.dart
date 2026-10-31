import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';

void main() {
  _toJsonRedactionTests();

  const redactor = LogRedactor();

  group('LogRedactor.isSensitive', () {
    test('matches the default keys case- and separator-insensitively', () {
      for (final key in <String>[
        'Authorization',
        'AUTHORIZATION',
        'password',
        'new_password',
        'passwd',
        'access_token',
        'refreshToken',
        'X-Refresh-Token',
        'client_secret',
        'Set-Cookie',
        'x-api-key',
        'API KEY',
        'api.key',
        'credentials',
        'session_id',
      ]) {
        expect(redactor.isSensitive(key), isTrue, reason: key);
      }
    });

    test('does not mask ordinary keys', () {
      for (final key in <String>[
        'Accept',
        'Content-Type',
        'email',
        'username',
        'id',
        '',
        ' - _ ',
      ]) {
        expect(redactor.isSensitive(key), isFalse, reason: key);
      }
    });

    test('uses custom keys instead of the defaults', () {
      const custom = LogRedactor(sensitiveKeys: <String>{'X-Tenant', 'pin'});

      expect(custom.isSensitive('x_tenant'), isTrue);
      expect(custom.isSensitive('X-TENANT-ID'), isTrue);
      expect(custom.isSensitive('card.pin'), isTrue);
      expect(custom.isSensitive('Authorization'), isFalse);
    });

    test('ignores blank candidates', () {
      const blank = LogRedactor(sensitiveKeys: <String>{'', ' ', '-'});

      expect(blank.isSensitive('anything'), isFalse);
    });
  });

  group('LogRedactor.redactHeaders', () {
    test('masks sensitive headers and stringifies values', () {
      final headers = redactor.redactHeaders(<String, dynamic>{
        'Authorization': 'Bearer secret-token',
        'Cookie': <String>['a=1', 'b=2'],
        'Accept': 'application/json',
        'X-Multi': <String>['one', 'two'],
        'Content-Length': 42,
      });

      expect(headers, <String, String>{
        'Authorization': '***',
        'Cookie': '***',
        'Accept': 'application/json',
        'X-Multi': 'one, two',
        'Content-Length': '42',
      });
    });

    test('uses a custom mask', () {
      const custom = LogRedactor(mask: '[hidden]');

      expect(
        custom.redactHeaders(<String, dynamic>{'authorization': 'x'}),
        <String, String>{'authorization': '[hidden]'},
      );
    });
  });

  group('LogRedactor.redactUri', () {
    test('masks sensitive query parameters and keeps the others', () {
      final uri = Uri.parse(
        'https://api.example.com/v1/items?access_token=abc&page=2'
        '&q=hello%20world&api_key=k1&api_key=k2#top',
      );

      final redacted = redactor.redactUri(uri);

      expect(redacted.queryParameters['access_token'], '***');
      expect(redacted.queryParametersAll['api_key'], <String>['***']);
      expect(redacted.queryParameters['page'], '2');
      expect(redacted.queryParameters['q'], 'hello world');
      expect(redacted.path, '/v1/items');
      expect(redacted.fragment, 'top');
      expect(redacted.toString(), isNot(contains('abc')));
      expect(redacted.toString(), isNot(contains('k1')));
      expect(redacted.toString(), contains('access_token=***'));
    });

    test('keeps every value of repeated non-sensitive parameters', () {
      final uri = Uri.parse('https://a.example.com/?tag=a&token=t&tag=b');

      final redacted = redactor.redactUri(uri);

      expect(redacted.queryParametersAll['tag'], <String>['a', 'b']);
      expect(redacted.queryParameters['token'], '***');
    });

    test('masks the whole query when it cannot be decoded', () {
      final uri = Uri.parse('https://api.example.com/x?token=%E0%A4%A&b=1');

      final redacted = redactor.redactUri(uri);

      expect(redacted.query, '***');
      expect(redacted.path, '/x');
    });

    test('returns the same instance when nothing is sensitive', () {
      final withoutQuery = Uri.parse('https://api.example.com/v1/items');
      final harmless = Uri.parse('https://api.example.com/v1/items?page=1');
      final harmlessFragment = Uri.parse('https://example.com/docs#section-2');

      expect(identical(redactor.redactUri(withoutQuery), withoutQuery), isTrue);
      expect(identical(redactor.redactUri(harmless), harmless), isTrue);
      expect(
        identical(redactor.redactUri(harmlessFragment), harmlessFragment),
        isTrue,
      );
    });

    test('masks user:password@ credentials', () {
      final uri = Uri.parse('https://jane:s3cret@api.example.com/v1?page=2');

      final redacted = redactor.redactUri(uri);

      expect(redacted.toString(), 'https://***@api.example.com/v1?page=2');
      expect(redacted.host, 'api.example.com');
      expect(redacted.port, uri.port);
    });

    test('masks a user name alone (API keys are often passed that way)', () {
      final uri = Uri.parse('https://sk_live_abc123@api.example.com:8443/x');

      expect(
        redactor.redactUri(uri).toString(),
        'https://***@api.example.com:8443/x',
      );
    });

    test('masks user info and sensitive parameters together', () {
      final uri = Uri.parse('https://a:b@h.example.com/p?token=t&q=1');

      expect(
        redactor.redactUri(uri).toString(),
        'https://***@h.example.com/p?token=***&q=1',
      );
    });

    test('masks user info even when the query cannot be decoded', () {
      final uri = Uri.parse('https://jane:s3cret@api.example.com/x?a=%E0%A4%A');

      final redacted = redactor.redactUri(uri);

      expect(redacted.toString(), isNot(contains('s3cret')));
      expect(redacted.userInfo, '***');
      expect(redacted.query, '***');
    });

    test('masks sensitive parameters of a query-like fragment', () {
      // OAuth implicit-grant redirects carry the tokens in the fragment.
      final uri = Uri.parse(
        'https://app.example.com/callback#access_token=abc&state=xyz',
      );

      final redacted = redactor.redactUri(uri);

      expect(redacted.toString(), isNot(contains('abc')));
      expect(redacted.fragment, 'access_token=***&state=xyz');
      expect(redacted.path, '/callback');
    });

    test('is idempotent', () {
      final uri = Uri.parse(
        'https://jane:s3cret@api.example.com/v1?token=t&page=2#id_token=x',
      );

      final once = redactor.redactUri(uri);
      final twice = redactor.redactUri(once);

      expect(twice.toString(), once.toString());
      expect(
        once.toString(),
        'https://***@api.example.com/v1?token=***&page=2#id_token=***',
      );
    });

    test('uses a custom mask for the user info', () {
      const custom = LogRedactor(mask: 'hidden');

      expect(
        custom.redactUri(Uri.parse('https://u:p@h.example.com/')).toString(),
        'https://hidden@h.example.com/',
      );
    });
  });

  group('LogRedactor.redact', () {
    test('masks nested maps and lists', () {
      final redacted = redactor.redact(<String, Object?>{
        'user': <String, Object?>{
          'name': 'Ada',
          'password': 'p@ss',
          'devices': <Object?>[
            <String, Object?>{'id': 1, 'pushToken': 'tok'},
            'plain',
          ],
        },
        'Session': <String, Object?>{'id': 'whole object is masked'},
        'count': 3,
      });

      expect(redacted, <String, Object?>{
        'user': <String, Object?>{
          'name': 'Ada',
          'password': '***',
          'devices': <Object?>[
            <String, Object?>{'id': 1, 'pushToken': '***'},
            'plain',
          ],
        },
        'Session': '***',
        'count': 3,
      });
    });

    test('stringifies non-string map keys', () {
      expect(
        redactor.redact(<Object?, Object?>{1: 'one', 'token': 'x'}),
        <String, Object?>{'1': 'one', 'token': '***'},
      );
    });

    test('redacts JSON strings and re-encodes them', () {
      final body = jsonEncode(<String, Object?>{
        'email': 'ada@example.com',
        'password': 'secret',
      });

      final redacted = redactor.redact(body);

      expect(redacted, isA<String>());
      expect(
        jsonDecode(redacted! as String),
        <String, Object?>{'email': 'ada@example.com', 'password': '***'},
      );
      expect(
        redactor.redact('  [{"token": "t"}]'),
        '[{"token":"***"}]',
      );
    });

    test('returns other values unchanged', () {
      expect(redactor.redact(null), isNull);
      expect(redactor.redact(42), 42);
      expect(redactor.redact('plain text'), 'plain text');
      expect(redactor.redact('{not json'), '{not json');
    });
  });

  group('LogRedactor.stringify', () {
    test('pretty prints redacted maps and lists', () {
      final text = redactor.stringify(<String, Object?>{
        'token': 'abc',
        'id': 7,
      });

      expect(text, '{\n  "token": "***",\n  "id": 7\n}');
    });

    test('handles null, strings and values JSON cannot encode', () {
      expect(redactor.stringify(null), isEmpty);
      expect(redactor.stringify('hello'), 'hello');

      final text = redactor.stringify(<String, Object?>{
        'at': DateTime.utc(2024),
        'secret': 's',
      });
      expect(text, contains('2024-01-01'));
      expect(text, contains('secret: ***'));
    });

    test('truncates long output', () {
      final text = redactor.stringify('abcdefghij', maxLength: 4);

      expect(text, 'abcd… [truncated 6 chars]');
      expect(redactor.stringify('abc', maxLength: 3), 'abc');
      expect(redactor.stringify('abc', maxLength: -1), 'abc');
      expect(redactor.stringify('abc', maxLength: 0), '… [truncated 3 chars]');
    });
  });
}

class _LoginModel {
  _LoginModel(this.email, this.password);
  final String email;
  final String password;
  Map<String, Object?> toJson() =>
      <String, Object?>{'email': email, 'password': password};
}

void _toJsonRedactionTests() {
  test('redact masks sensitive fields of objects exposing toJson()', () {
    const redactor = LogRedactor();
    final redacted = redactor.redact(<String, Object?>{
      'body': _LoginModel('ada@example.com', 'hunter2'),
    });
    expect(redacted, <String, Object?>{
      'body': <String, Object?>{'email': 'ada@example.com', 'password': '***'},
    });
    expect(
      redactor.stringify(_LoginModel('ada@example.com', 'hunter2')),
      isNot(contains('hunter2')),
    );
  });
}
