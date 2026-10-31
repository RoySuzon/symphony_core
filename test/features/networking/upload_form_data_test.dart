import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/networking/networking.dart';

void main() {
  group('UploadFile.toMultipartFile', () {
    test('converts in-memory files with their content type', () async {
      const file = UploadFile.fromBytes(
        <int>[1, 2, 3],
        filename: 'notes.txt',
        contentType: 'Text/Plain; charset="utf-8"',
      );

      final multipart = await file.toMultipartFile();

      expect(multipart.filename, 'notes.txt');
      expect(multipart.length, 3);
      expect(multipart.contentType?.mimeType, 'text/plain');
      expect(multipart.contentType?.parameters['charset'], 'utf-8');
    });

    test('rejects invalid MIME types', () {
      const file = UploadFile.fromBytes(
        <int>[1],
        filename: 'a.bin',
        contentType: 'image',
      );

      expect(file.toMultipartFile, throwsArgumentError);
    });
  });

  group('buildUploadFormData', () {
    test('encodes every supported field type', () async {
      final formData = await buildUploadFormData(
        files: const <UploadFile>[
          UploadFile.fromBytes(<int>[1], filename: 'a.bin', field: 'docs'),
          UploadFile.fromBytes(<int>[2], filename: 'b.bin', field: 'docs'),
        ],
        fields: <String, Object?>{
          'name': 'Jane',
          'age': 42,
          'active': true,
          'ids': <int>[1, 2],
          'filters': <String, Object?>{'status': 'open'},
          'since': DateTime.utc(2026, 1, 2, 3, 4, 5),
          'missing': null,
          'avatar': const UploadFile.fromBytes(<int>[3], filename: 'me.png'),
          'raw': MultipartFile.fromBytes(<int>[4, 5], filename: 'raw.bin'),
        },
      );

      expect(
        formData.fields.map((field) => '${field.key}=${field.value}'),
        <String>[
          'name=Jane',
          'age=42',
          'active=true',
          'ids=1',
          'ids=2',
          'filters={"status":"open"}',
          'since=2026-01-02T03:04:05.000Z',
        ],
      );
      expect(
        formData.files.map((file) => '${file.key}:${file.value.filename}'),
        <String>['avatar:me.png', 'raw:raw.bin', 'docs:a.bin', 'docs:b.bin'],
      );
    });
  });
}
