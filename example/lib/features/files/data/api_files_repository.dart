import 'dart:typed_data';

import 'package:symphony_core/symphony_core.dart';

import '../../../core/network/api_envelope.dart';
import '../domain/file_entities.dart';

/// [FilesRepository] backed by the package's [ApiClient]:
/// `ApiClient.upload` for multipart uploads and `ApiClient.downloadBytes`
/// for in-memory downloads (both report progress).
class ApiFilesRepository implements FilesRepository {
  /// Creates the repository.
  const ApiFilesRepository(this._client);

  final ApiClient _client;

  @override
  Future<Result<List<RemoteFile>>> fetchFiles() => guardResult(() async {
    final response = await _client.get<List<RemoteFile>>(
      '/files',
      decoder: (body) => _decodeList(ApiEnvelope.list(body, 'items')),
    );
    return response.data;
  }, mapError: _client.mapError);

  @override
  Future<Result<List<RemoteFile>>> upload(
    List<UploadFile> files, {
    String? note,
    TransferProgressCallback? onProgress,
  }) => guardResult(() async {
    final response = await _client.upload<List<RemoteFile>>(
      '/files',
      files: files,
      fields: <String, Object?>{'note': note},
      onSendProgress: onProgress,
      decoder: (body) => _decodeList(ApiEnvelope.list(body, 'files')),
    );
    return response.data;
  }, mapError: _client.mapError);

  @override
  Future<Result<Uint8List>> download(
    RemoteFile file, {
    TransferProgressCallback? onProgress,
  }) => guardResult(() async {
    final response = await _client.downloadBytes(
      '/files/${Uri.encodeComponent(file.id)}/content',
      onReceiveProgress: onProgress,
    );
    return response.data;
  }, mapError: _client.mapError);

  static List<RemoteFile> _decodeList(List<Object?> items) => <RemoteFile>[
    for (final item in items)
      _decodeFile(
        JsonReader.asMap(item) ??
            (throw const FormatException('A file must be an object.')),
      ),
  ];

  static RemoteFile _decodeFile(Map<String, Object?> json) => RemoteFile(
    id: ApiEnvelope.requireString(json, 'id'),
    name: ApiEnvelope.requireString(json, 'name'),
    sizeInBytes: JsonReader.asInt(json['size']) ?? 0,
    contentType:
        JsonReader.asString(json['content_type']) ?? 'application/octet-stream',
    uploadedAt: ApiEnvelope.requireDate(json, 'uploaded_at'),
    uploadedBy: JsonReader.asString(json['uploaded_by']) ?? 'Unknown',
  );
}
