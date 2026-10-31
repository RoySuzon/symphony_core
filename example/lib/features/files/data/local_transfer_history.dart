import 'package:symphony_core/symphony_core.dart';

import '../domain/file_entities.dart';

/// [TransferHistory] stored in the package's pluggable [LocalDatabase]
/// (`localDatabaseProvider`, in memory by default — override it with
/// `KeyValueLocalDatabase` or your own engine adapter to persist it).
class LocalTransferHistory implements TransferHistory {
  /// Creates the history on [database].
  LocalTransferHistory(LocalDatabase database)
      : _store = database.store<TransferRecord>(
          'transfer_history',
          StorageCodec<TransferRecord>.json(
            fromJson: TransferRecord.fromJson,
            toJson: (record) => record.toJson(),
          ),
        );

  final LocalStore<TransferRecord> _store;

  @override
  Future<void> add(TransferRecord record) => _store.put(record.id, record);

  @override
  Stream<List<TransferRecord>> watch() => _store.watchAll().map(
        (records) => List<TransferRecord>.of(records)
          ..sort((a, b) => b.at.compareTo(a.at)),
      );

  @override
  Future<void> clear() => _store.clear();
}
