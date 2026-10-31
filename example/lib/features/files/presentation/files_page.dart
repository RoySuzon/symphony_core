import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/async_result_view.dart';
import '../domain/file_entities.dart';
import 'files_providers.dart';

/// Multipart uploads and downloads with progress.
///
/// * Upload: in-memory sample files (`UploadFile.fromBytes`) sent with
///   `ApiClient.upload` — one `multipart/form-data` request whose send
///   progress is displayed (the demo backend throttles the bandwidth).
/// * Download: `ApiClient.downloadBytes` with receive progress.
/// * History: completed transfers stored in the package's `LocalDatabase`
///   and displayed live through a `StreamProvider`.
class FilesPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const FilesPage({super.key});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  static const List<int> _sizes = <int>[64 * 1024, 256 * 1024, 1024 * 1024];

  final TextEditingController _note = TextEditingController();
  int _count = 3;
  int _size = 256 * 1024;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  FileTransferController get _transfers =>
      ref.read(fileTransferControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final transfer = ref.watch(fileTransferControllerProvider);
    final busy = transfer is TransferRunning;
    return AppPage(
      title: 'Files',
      scrollable: true,
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(remoteFilesProvider),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionCard(
            title: 'Upload',
            subtitle:
                'Generated in memory with UploadFile.fromBytes and sent '
                'as one multipart/form-data request.',
            icon: Icons.cloud_upload_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Number of files'),
                const SizedBox(height: SymphonySpacing.sm),
                SegmentedButton<int>(
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment<int>(value: 1, label: Text('1')),
                    ButtonSegment<int>(value: 3, label: Text('3')),
                    ButtonSegment<int>(value: 5, label: Text('5')),
                  ],
                  selected: <int>{_count},
                  onSelectionChanged:
                      busy
                          ? null
                          : (selection) =>
                              setState(() => _count = selection.first),
                ),
                const SizedBox(height: SymphonySpacing.lg),
                const Text('Size of each file'),
                const SizedBox(height: SymphonySpacing.sm),
                SegmentedButton<int>(
                  segments: <ButtonSegment<int>>[
                    for (final size in _sizes)
                      ButtonSegment<int>(
                        value: size,
                        label: Text(Formatters.bytes(size)),
                      ),
                  ],
                  selected: <int>{_size},
                  onSelectionChanged:
                      busy
                          ? null
                          : (selection) =>
                              setState(() => _size = selection.first),
                ),
                const SizedBox(height: SymphonySpacing.lg),
                SymphonyTextField(
                  controller: _note,
                  label: 'Note (optional form field)',
                  prefixIcon: Icons.notes,
                  enabled: !busy,
                ),
                const SizedBox(height: SymphonySpacing.lg),
                SymphonyButton(
                  label: 'Upload ${Formatters.bytes(_count * _size)}',
                  icon: Icons.upload_rounded,
                  isLoading:
                      transfer is TransferRunning &&
                      transfer.direction == TransferDirection.upload,
                  onPressed:
                      busy
                          ? null
                          : () => _transfers.uploadSamples(
                            count: _count,
                            sizeInBytes: _size,
                            note: _note.text,
                          ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SymphonySpacing.lg),
          _TransferPanel(state: transfer),
          const SizedBox(height: SymphonySpacing.lg),
          SectionCard(
            title: 'Files on the server',
            subtitle: 'Downloaded with ApiClient.downloadBytes.',
            icon: Icons.folder_outlined,
            child: SizedBox(
              height: 320,
              child: AsyncResultView<List<RemoteFile>>(
                value: ref.watch(remoteFilesProvider),
                onRetry: () => ref.invalidate(remoteFilesProvider),
                isEmpty: (files) => files.isEmpty,
                emptyBuilder:
                    (context) => const SymphonyEmptyState(
                      title: 'No files yet',
                      message: 'Upload a file to see it here.',
                      icon: Icons.folder_off_outlined,
                      compact: true,
                    ),
                builder:
                    (context, files) => ListView.separated(
                      itemCount: files.length,
                      separatorBuilder:
                          (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final file = files[index];
                        return ListTile(
                          leading: Icon(_iconFor(file)),
                          title: Text(file.name),
                          subtitle: Text(
                            '${Formatters.bytes(file.sizeInBytes)} · '
                            '${file.uploadedBy} · '
                            '${Formatters.dateTime(file.uploadedAt)}',
                          ),
                          trailing: SymphonyIconButton(
                            icon: Icons.download_rounded,
                            tooltip: 'Download ${file.name}',
                            onPressed:
                                busy ? null : () => _transfers.download(file),
                          ),
                        );
                      },
                    ),
              ),
            ),
          ),
          const SizedBox(height: SymphonySpacing.lg),
          const _TransferHistoryCard(),
        ],
      ),
    );
  }

  static IconData _iconFor(RemoteFile file) {
    if (file.contentType == 'application/pdf') {
      return Icons.picture_as_pdf_outlined;
    }
    if (file.contentType.contains('json')) return Icons.data_object;
    if (file.contentType.contains('csv')) return Icons.table_view_outlined;
    return Icons.description_outlined;
  }
}

class _TransferPanel extends StatelessWidget {
  const _TransferPanel({required this.state});

  final FileTransferState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = state;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (current) {
        TransferIdle() => const SizedBox.shrink(),
        TransferRunning() => Card(
          key: const ValueKey<String>('transfer-running'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(SymphonySpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${current.direction == TransferDirection.upload ? 'Uploading' : 'Downloading'} '
                  '${current.label}…',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: SymphonySpacing.md),
                LinearProgressIndicator(value: current.progress),
                const SizedBox(height: SymphonySpacing.sm),
                Text(
                  current.total > 0
                      ? '${Formatters.bytes(current.transferred)} of '
                          '${Formatters.bytes(current.total)} · '
                          '${Formatters.percent(current.progress ?? 0)}'
                      : Formatters.bytes(current.transferred),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        TransferSucceeded() => Card(
          key: const ValueKey<String>('transfer-done'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(SymphonySpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.check_circle,
                      color: SymphonyColors.of(context).success,
                    ),
                    const SizedBox(width: SymphonySpacing.md),
                    Expanded(child: Text(current.message)),
                  ],
                ),
                if (current.preview != null) ...<Widget>[
                  const SizedBox(height: SymphonySpacing.md),
                  Container(
                    padding: const EdgeInsets.all(SymphonySpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withAlpha(14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      current.preview!,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: inspectorMonospaceStyle(context, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        TransferFailed() => SymphonyErrorView(
          key: const ValueKey<String>('transfer-failed'),
          failure: current.failure,
          compact: true,
        ),
      },
    );
  }
}

class _TransferHistoryCard extends ConsumerWidget {
  const _TransferHistoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(transferRecordsProvider);
    return SectionCard(
      title: 'Transfer history',
      subtitle: 'Stored in the package LocalDatabase (localDatabaseProvider).',
      icon: Icons.history,
      trailing: TextButton(
        onPressed: () => ref.read(transferHistoryProvider).clear(),
        child: const Text('Clear'),
      ),
      child: records.when(
        loading: () => const SymphonyLoadingIndicator(size: 24),
        error:
            (error, stackTrace) => SymphonyErrorView(
              failure: UnexpectedFailure.fromError(error, stackTrace),
              compact: true,
            ),
        data:
            (items) =>
                items.isEmpty
                    ? const Text('Completed uploads and downloads appear here.')
                    : Column(
                      children: <Widget>[
                        for (final record in items.take(8))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(
                              record.direction == TransferDirection.upload
                                  ? Icons.north_east
                                  : Icons.south_west,
                            ),
                            title: Text(record.fileName),
                            subtitle: Text(
                              Formatters.bytes(record.sizeInBytes),
                            ),
                            trailing: Text(Formatters.time(record.at)),
                          ),
                      ],
                    ),
      ),
    );
  }
}
