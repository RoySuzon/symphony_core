import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/inspector/inspector.dart';

/// A model serialised through `toJson` (as Dio's JSON transformer does).
class _Credentials {
  const _Credentials(this.user, this.password);

  final String user;
  final String password;

  Map<String, Object?> toJson() => <String, Object?>{
    'user': user,
    'password': password,
  };
}

void main() {
  final uri = Uri.parse('https://api.example.com/items');

  test('masks secrets of models nested in map and list bodies', () {
    final inspector = ApiInspector();
    addTearDown(inspector.dispose);

    final id =
        inspector.startCall(
          method: 'POST',
          uri: uri,
          body: <String, Object?>{
            'login': const _Credentials('jane', 'nested-map-secret'),
            'others': <Object?>[
              const _Credentials('john', 'nested-list-secret'),
            ],
          },
        )!;
    inspector.completeCall(
      id,
      statusCode: 200,
      body: <Object?>[const _Credentials('ann', 'response-list-secret')],
    );

    final call = inspector.calls.single;
    expect(call.requestBody, contains('jane'));
    expect(call.requestBody, contains('john'));
    expect(call.responseBody, contains('ann'));
    for (final text in <String?>[call.requestBody, call.responseBody]) {
      expect(text, isNot(contains('secret')));
    }
  });

  test('keeps multipart field values within maxBodyLength', () {
    final inspector = ApiInspector(maxBodyLength: 40);
    addTearDown(inspector.dispose);
    final huge = List<String>.filled(100000, 'x').join();

    inspector.startCall(
      method: 'POST',
      uri: uri,
      body: ApiCallFormData(
        fields: <MapEntry<String, String>>[
          MapEntry<String, String>('blob', huge),
          const MapEntry<String, String>('name', 'avatar'),
        ],
      ),
    );

    final form = inspector.calls.single.requestFormData!;
    expect(form.fields, hasLength(2));
    expect(form.fields.first.value.length, lessThan(100));
    expect(form.fields.first.value, contains('[truncated'));
    expect(form.fields.last.value, 'avatar');
    expect(inspector.calls.single.requestBody!.length, lessThan(200));
  });
}
