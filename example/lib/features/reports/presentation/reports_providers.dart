import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../data/api_reports_repository.dart';
import '../domain/sales_report.dart';

/// The reports repository, built on the shared `ApiClient`.
final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ApiReportsRepository(ref.watch(apiClientProvider)),
  name: 'reportsRepositoryProvider',
);

/// The sales report of the signed-in user's organization.
final salesReportProvider = FutureProvider<Result<SalesReport>>((ref) {
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  if (userId == null) {
    return const Result<SalesReport>.failure(UnauthorizedFailure());
  }
  return ref.watch(reportsRepositoryProvider).fetchSummary();
}, name: 'salesReportProvider');
