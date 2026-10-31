import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:symphony_core/symphony_core.dart';

/// A file stored on the server.
@immutable
class RemoteFile {
  /// Creates a file description.
  const RemoteFile({
    required this.id,
    required this.name,
    required this.sizeInBytes,
    required this.contentType,
    required this.uploadedAt,
    required this.uploadedBy,
  });

  /// File id.
  final String id;

  /// File name.
  final String name;

  /// Size in bytes.
  final int sizeInBytes;

  /// MIME type.
  final String contentType;

  /// Upload date.
  final DateTime uploadedAt;

  /// Who uploaded it.
  final String uploadedBy;

  /// Whether the content can be previewed as text.
  bool get isText =>
      contentType.startsWith('text/') || contentType == 'application/json';
}

/// Direction of a transfer.
enum TransferDirection {
  /// Device → server.
  upload,

  /// Server → device.
  download,
}

/// A completed transfer, kept in the local transfer history.
@immutable
class TransferRecord {
  /// Creates a record.
  const TransferRecord({
    required this.id,
    required this.direction,
    required this.fileName,
    required this.sizeInBytes,
    required this.at,
  });

  /// Restores a record serialized with [toJson].
  factory TransferRecord.fromJson(Map<String, Object?> json) {
    return TransferRecord(
      id: JsonReader.asString(json['id']) ?? '',
      direction:
          JsonReader.asString(json['direction']) == 'upload'
              ? TransferDirection.upload
              : TransferDirection.download,
      fileName: JsonReader.asString(json['fileName']) ?? '',
      sizeInBytes: JsonReader.asInt(json['sizeInBytes']) ?? 0,
      at: JsonReader.asDateTime(json['at']) ?? DateTime(1970),
    );
  }

  /// Record id.
  final String id;

  /// Upload or download.
  final TransferDirection direction;

  /// Transferred file (or a summary such as `3 files`).
  final String fileName;

  /// Transferred bytes.
  final int sizeInBytes;

  /// Completion date.
  final DateTime at;

  /// Serializes the record (stored through `LocalDatabase`).
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'direction': direction.name,
    'fileName': fileName,
    'sizeInBytes': sizeInBytes,
    'at': at.toIso8601String(),
  };
}

/// Generates the in-memory sample files uploaded by the files screen.
///
/// Pure logic: deterministic text content of the requested size, wrapped in
/// [UploadFile.fromBytes] (which also works on the web, unlike file paths).
abstract final class SampleFiles {
  /// [count] text files of [sizeInBytes] bytes each.
  static List<UploadFile> generate({
    required int count,
    required int sizeInBytes,
  }) {
    return <UploadFile>[
      for (var index = 0; index < count; index++)
        UploadFile.fromBytes(
          _content(index, sizeInBytes),
          filename: 'sample-${index + 1}.txt',
          contentType: 'text/plain',
          field: 'files',
        ),
    ];
  }

  static Uint8List _content(int index, int size) {
    final buffer = StringBuffer();
    var line = 0;
    while (buffer.length < size) {
      line++;
      buffer.writeln(
        'File ${index + 1} · line ${line.toString().padLeft(5, '0')} · '
        'uploaded with ApiClient.upload from symphony_core',
      );
    }
    final bytes = utf8.encode(buffer.toString());
    return Uint8List.fromList(bytes.sublist(0, size));
  }
}

/// Reports the progress of a transfer.
typedef TransferProgressCallback = void Function(int transferred, int total);

/// Server side file operations.
abstract interface class FilesRepository {
  /// Files stored on the server, newest first.
  Future<Result<List<RemoteFile>>> fetchFiles();

  /// Uploads [files] in one `multipart/form-data` request.
  Future<Result<List<RemoteFile>>> upload(
    List<UploadFile> files, {
    String? note,
    TransferProgressCallback? onProgress,
  });

  /// Downloads the content of [file] into memory.
  Future<Result<Uint8List>> download(
    RemoteFile file, {
    TransferProgressCallback? onProgress,
  });
}

/// Local history of the completed transfers.
abstract interface class TransferHistory {
  /// Adds [record].
  Future<void> add(TransferRecord record);

  /// The records, newest first, updated live.
  Stream<List<TransferRecord>> watch();

  /// Removes every record.
  Future<void> clear();
}
