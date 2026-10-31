import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/auth/auth.dart';

void main() {
  const mapping = AuthResponseMapping();
  final now = DateTime.utc(2026, 1, 1);

  group('read', () {
    test('resolves dotted paths, list indices and the root', () {
      final data = <String, Object?>{
        'a': <String, Object?>{
          'b': <Object?>[
            <String, Object?>{'c': 1},
          ],
        },
      };

      expect(mapping.read(data, <String>['a.b.0.c']), 1);
      expect(mapping.read(data, <String>['missing', 'a.b.0.c']), 1);
      expect(mapping.read(data, <String>['a.b.5.c']), isNull);
      expect(mapping.read(data, <String>['']), data);
      expect(mapping.read('{"x": {"y": true}}', <String>['x.y']), isTrue);
    });
  });

  group('readTokens', () {
    test('returns null without an access token', () {
      expect(mapping.readTokens(<String, Object?>{'token': ''}), isNull);
      expect(mapping.readTokens(<String, Object?>{'token': 12}), isNull);
      expect(mapping.readTokens(null), isNull);
      expect(mapping.readTokens('plain text'), isNull);
    });

    test('skips candidates holding an unusable value', () {
      final tokens = mapping.readTokens(<String, Object?>{
        'token': <String, Object?>{'nested': true},
        'data': <String, Object?>{'token': 'a1'},
      });

      expect(tokens?.accessToken, 'a1');
    });

    test('reads epoch expiries in seconds and milliseconds', () {
      final seconds = mapping.readTokens(<String, Object?>{
        'token': 'a1',
        'expires_at': now.millisecondsSinceEpoch ~/ 1000,
      });
      final milliseconds = mapping.readTokens(<String, Object?>{
        'token': 'a1',
        'expires_at': '${now.millisecondsSinceEpoch}',
      });

      expect(seconds?.expiresAt, now);
      expect(milliseconds?.expiresAt, now);
    });

    test('prefers expires_in over expires_at and uses the given clock', () {
      final tokens = mapping.readTokens(
        <String, Object?>{
          'token': 'a1',
          'expires_in': 90.5,
          'expires_at': '2030-01-01T00:00:00Z',
        },
        now: now,
      );

      expect(
        tokens?.expiresAt,
        now.add(const Duration(seconds: 90, milliseconds: 500)),
      );
    });

    test('ignores JWT expiries when disabled', () {
      const noJwt = AuthResponseMapping(useJwtExpiry: false);

      final tokens = noJwt.readTokens(<String, Object?>{
        'token': 'eyJhbGciOiJub25lIn0.eyJleHAiOjE4OTM0NTYwMDB9.',
      });

      expect(tokens?.expiresAt, isNull);
    });

    test('copies configured extra fields', () {
      const withExtras = AuthResponseMapping(
        tokenExtras: <String>['id_token', 'scope'],
      );

      final tokens = withExtras.readTokens(<String, Object?>{
        'access_token': 'a1',
        'id_token': 'id-1',
      });

      expect(tokens?.extra, <String, Object?>{'id_token': 'id-1'});
    });
  });

  group('readUser', () {
    test('falls back to the e-mail as id and composes the display name', () {
      final user = mapping.readUser(<String, Object?>{
        'email': 'ada@example.com',
        'given_name': 'Ada',
        'family_name': 'Lovelace',
      });

      expect(user?.id, 'ada@example.com');
      expect(user?.displayName, 'Ada Lovelace');
    });

    test('accepts roles and permissions in many shapes', () {
      final fromList = mapping.readUser(<String, Object?>{
        'id': 1,
        'roles': <Object?>[
          'admin',
          <String, Object?>{'slug': 'editor'},
          7,
        ],
        'permissions': 'orders.read, orders.write',
      });
      final fromFlags = mapping.readUser(<String, Object?>{
        'id': 2,
        'role': <String, Object?>{'name': 'viewer'},
        'scope': 'read write',
      });
      final fromCsv = mapping.readUser(<String, Object?>{
        'id': 3,
        'roles': 'Super Admin,Support',
      });

      expect(fromList?.roles, <String>{'admin', 'editor', '7'});
      expect(fromList?.permissions, <String>{'orders.read', 'orders.write'});
      expect(fromFlags?.roles, <String>{'viewer'});
      expect(fromFlags?.permissions, <String>{'read', 'write'});
      expect(fromCsv?.roles, <String>{'Super Admin', 'Support'});
    });

    test('returns null for values that are not objects', () {
      expect(mapping.readUser(null), isNull);
      expect(mapping.readUser(<Object?>[1, 2]), isNull);
    });
  });

  test('readCurrentUser understands envelopes and bare objects', () {
    expect(
      mapping.readCurrentUser(<String, Object?>{
        'data': <String, Object?>{
          'user': <String, Object?>{'id': 'a'},
        },
      })?.id,
      'a',
    );
    expect(
      mapping.readCurrentUser(<String, Object?>{
        'data': <String, Object?>{'id': 'b'},
      })?.id,
      'b',
    );
    expect(mapping.readCurrentUser(<String, Object?>{'id': 'c'})?.id, 'c');
  });

  test('readSession combines tokens and the embedded user', () {
    final session = mapping.readSession(
      <String, Object?>{
        'tokens': <String, Object?>{'access': 'a1', 'refresh': 'r1'},
        'account': <String, Object?>{'id': 'u'},
      },
      now: now,
    );

    expect(session?.tokens.accessToken, 'a1');
    expect(session?.tokens.refreshToken, 'r1');
    expect(session?.user?.id, 'u');
    expect(mapping.readSession(<String, Object?>{}), isNull);
  });
}
