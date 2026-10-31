import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/utils/formatters.dart';
import '../data/api_files_repository.dart';
import '../data/local_transfer_history.dart';
import '../domain/file_entities.dart';

/// The files repository, built on the shared `ApiClient`.
final filesRepositoryProvider = Provider<FilesRepository>(
  (ref) => ApiFilesRepository(ref.watch(apiClientProvider)),
  name: 'filesRepositoryProvider',
);

/// Files stored on the server.
final remoteFilesProvider = FutureProvider<Result<List<RemoteFile>>>((ref) {
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  if (userId == null) {
    return const Result<List<RemoteFile>>.failure(UnauthorizedFailure());
  }
  return ref.watch(filesRepositoryProvider).fetchFiles();
}, name: 'remoteFilesProvider');

/// The local transfer history, kept in the package's `localDatabaseProvider`.
final transferHistoryProvider = Provider<TransferHistory>(
  (ref) => LocalTransferHistory(ref.watch(localDatabaseProvider)),
  name: 'transferHistoryProvider',
);

/// Completed transfers, newest first (live).
final transferRecordsProvider = StreamProvider<List<TransferRecord>>(
  (ref) => ref.watch(transferHistoryProvider).watch(),
  name: 'transferRecordsProvider',
);

/// State of the current (or last) transfer.
sealed class FileTransferState {
  const FileTransferState();
}

/// No transfer yet.
final class TransferIdle extends FileTransferState {
  /// Creates the idle state.
  const TransferIdle();
}

/// A transfer is running.
final class TransferRunning extends FileTransferState {
  /// Creates the state.
  const TransferRunning({
    required this.direction,
    required this.label,
    required this.transferred,
    required this.total,
  });

  /// Upload or download.
  final TransferDirection direction;

  /// What is transferred.
  final String label;

  /// Bytes transferred so far.
  final int transferred;

  /// Expected bytes (`<= 0` when unknown).
  final int total;

  /// Completion between 0 and 1, or `null` when unknown.
  double? get progress => total > 0 ? transferred / total : null;
}

/// The last transfer succeeded.
final class TransferSucceeded extends FileTransferState {
  /// Creates the state.
  const TransferSucceeded({
    required this.direction,
    required this.message,
    this.preview,
  });

  /// Upload or download.
  final TransferDirection direction;

  /// Summary.
  final String message;

  /// Beginning of a downloaded text file.
  final String? preview;
}

/// The last transfer failed.
final class TransferFailed extends FileTransferState {
  /// Creates the state.
  const TransferFailed({required this.direction, required this.failure});

  /// Upload or download.
  final TransferDirection direction;

  /// Why it failed.
  final Failure failure;
}

/// Runs uploads and downloads and exposes their progress.
class FileTransferController extends Notifier<FileTransferState> {
  int _sequence = 0;

  @override
  FileTransferState build() => const TransferIdle();

  /// Whether a transfer is running.
  bool get isBusy => state is TransferRunning;

  /// Uploads [count] generated text files of [sizeInBytes] bytes each in a
  /// single multipart request.
  Future<void> uploadSamples({
    required int count,
    required int sizeInBytes,
    String? note,
  }) async {
    if (isBusy) return;
    final files = SampleFiles.generate(count: count, sizeInBytes: sizeInBytes);
    final label = count == 1 ? files.single.filename! : '$count files';
    _progress(TransferDirection.upload, label, 0, count * sizeInBytes);

    final result = await ref
        .read(filesRepositoryProvider)
        .upload(
          files,
          note: note == null || note.trim().isEmpty ? null : note.trim(),
          onProgress:
              (sent, total) =>
                  _progress(TransferDirection.upload, label, sent, total),
        );
    switch (result) {
      case ResultSuccess<List<RemoteFile>>(:final value):
        final size = value.fold<int>(0, (sum, file) => sum + file.sizeInBytes);
        state = TransferSucceeded(
          direction: TransferDirection.upload,
          message:
              'Uploaded ${value.length} file${value.length == 1 ? '' : 's'}'
              ' (${Formatters.bytes(size)}).',
        );
        await _record(TransferDirection.upload, label, size);
        ref.invalidate(remoteFilesProvider);
      case ResultFailure<List<RemoteFile>>(:final failure):
        state = TransferFailed(
          direction: TransferDirection.upload,
          failure: failure,
        );
    }
  }

  /// Downloads [file] into memory.
  Future<void> download(RemoteFile file) async {
    if (isBusy) return;
    _progress(TransferDirection.download, file.name, 0, file.sizeInBytes);
    final result = await ref
        .read(filesRepositoryProvider)
        .download(
          file,
          onProgress:
              (received, total) => _progress(
                TransferDirection.download,
                file.name,
                received,
                total > 0 ? total : file.sizeInBytes,
              ),
        );
    switch (result) {
      case ResultSuccess(:final value):
        state = TransferSucceeded(
          direction: TransferDirection.download,
          message:
              'Downloaded ${file.name} '
              '(${Formatters.bytes(value.length)}) into memory.',
          preview:
              file.isText
                  ? utf8.decode(
                    value.length > 600 ? value.sublist(0, 600) : value,
                    allowMalformed: true,
                  )
                  : null,
        );
        await _record(TransferDirection.download, file.name, value.length);
      case ResultFailure(:final failure):
        state = TransferFailed(
          direction: TransferDirection.download,
          failure: failure,
        );
    }
  }

  void _progress(
    TransferDirection direction,
    String label,
    int transferred,
    int total,
  ) {
    state = TransferRunning(
      direction: direction,
      label: label,
      transferred: transferred,
      total: total,
    );
  }

  Future<void> _record(TransferDirection direction, String name, int size) {
    _sequence++;
    final now = DateTime.now();
    return ref
        .read(transferHistoryProvider)
        .add(
          TransferRecord(
            id: '${now.microsecondsSinceEpoch}-$_sequence',
            direction: direction,
            fileName: name,
            sizeInBytes: size,
            at: now,
          ),
        );
  }
}

/// The transfer controller.
final fileTransferControllerProvider =
    NotifierProvider<FileTransferController, FileTransferState>(
      FileTransferController.new,
      name: 'fileTransferControllerProvider',
    );
