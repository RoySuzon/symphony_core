import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/async_result_view.dart';
import '../domain/sales_report.dart';
import 'reports_providers.dart';

/// Sales report (permission `reports.view`), with a CSV export reserved to
/// the `reports.export` permission.
class ReportsPage extends ConsumerWidget {
  /// Creates the page.
  const ReportsPage({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(reportsRepositoryProvider);
    final result = await SymphonyDialogs.runWithLoading(
      context,
      repository.exportOrders,
      message: 'Preparing the export…',
    );
    if (context.mounted) await _showExport(context, result);
  }

  Future<void> _showExport(
    BuildContext context,
    Result<ReportExport> result,
  ) async {
    switch (result) {
      case ResultSuccess<ReportExport>(:final value):
        final preview = value.content.split('\n').take(4).join('\n');
        await SymphonyDialogs.alert(
          context,
          title: value.filename,
          icon: Icons.table_view_outlined,
          message: '${value.rowCount} orders exported.\n\n$preview\n…',
        );
      case ResultFailure<ReportExport>(:final failure):
        SymphonySnackbar.showFailure(context, failure);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: 'Reports',
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(salesReportProvider),
        ),
      ],
      body: AsyncResultView<SalesReport>(
        value: ref.watch(salesReportProvider),
        loadingMessage: 'Computing the report…',
        onRetry: () => ref.invalidate(salesReportProvider),
        builder: (context, report) => ListView(
          children: <Widget>[
            _KpiGrid(report: report),
            const SizedBox(height: SymphonySpacing.lg),
            SectionCard(
              title: 'Weekly revenue',
              subtitle: 'Last ${report.weeklyRevenue.length} weeks',
              icon: Icons.bar_chart_rounded,
              child: _RevenueChart(report: report),
            ),
            const SizedBox(height: SymphonySpacing.lg),
            ResponsiveBuilder(
              builder: (context, sizeClass, constraints) {
                final status = SectionCard(
                  title: 'Orders by status',
                  icon: Icons.donut_large_rounded,
                  child: _StatusBreakdown(report: report),
                );
                final products = SectionCard(
                  title: 'Best sellers',
                  icon: Icons.emoji_events_outlined,
                  child: _TopProducts(report: report),
                );
                if (sizeClass.isAtLeast(ScreenSizeClass.expanded)) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: status),
                      const SizedBox(width: SymphonySpacing.lg),
                      Expanded(child: products),
                    ],
                  );
                }
                return Column(
                  children: <Widget>[
                    status,
                    const SizedBox(height: SymphonySpacing.lg),
                    products,
                  ],
                );
              },
            ),
            const SizedBox(height: SymphonySpacing.lg),
            AccessGate(
              requirement: const AccessRequirement(
                permissions: <String>{'reports.export'},
              ),
              fallback: const Text(
                'Exports require the reports.export permission.',
                textAlign: TextAlign.center,
              ),
              child: SymphonyButton(
                label: 'Export orders (CSV)',
                icon: Icons.download_outlined,
                variant: SymphonyButtonVariant.secondary,
                onPressed: () => _export(context, ref),
              ),
            ),
            const SizedBox(height: SymphonySpacing.sm),
            Text(
              'Generated ${Formatters.dateTime(report.generatedAt)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _KpiTile(
        label: 'Revenue',
        value: Formatters.money(report.revenueInCents, report.currency),
        icon: Icons.payments_outlined,
      ),
      _KpiTile(
        label: 'Orders',
        value: '${report.orderCount}',
        icon: Icons.receipt_long_outlined,
      ),
      _KpiTile(
        label: 'Average order',
        value: Formatters.money(
          report.averageOrderValueInCents,
          report.currency,
        ),
        icon: Icons.trending_up_rounded,
      ),
      _KpiTile(
        label: 'Pending',
        value: '${report.pendingOrders}',
        icon: Icons.hourglass_top_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = SymphonySpacing.md;
        final columns = responsiveColumns(
          constraints.maxWidth,
          minTileWidth: 180,
          spacing: spacing,
          maxColumns: 4,
        );
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(SymphonySpacing.lg),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: SymphonySpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: theme.textTheme.labelMedium),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: theme.textTheme.titleLarge),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = report.bestWeekInCents;
    const chartHeight = 160.0;
    return SizedBox(
      height: chartHeight + 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final week in report.weeklyRevenue)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    FittedBox(
                      child: Text(
                        Formatters.money(week.amountInCents, report.currency),
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(height: SymphonySpacing.xs),
                    Container(
                      height: best == 0
                          ? 4
                          : 4 + (chartHeight - 4) * week.amountInCents / best,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(height: SymphonySpacing.xs),
                    Text(
                      Formatters.date(week.weekStart).split(',').first,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    final total = report.orderCount == 0 ? 1 : report.orderCount;
    final entries = report.ordersByStatus.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      children: <Widget>[
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SymphonySpacing.xs),
            child: Row(
              children: <Widget>[
                SizedBox(width: 96, child: Text(entry.key.capitalize())),
                Expanded(
                  // LinearProgressIndicator.borderRadius does not exist on
                  // Flutter 3.10: clip instead.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: entry.value / total,
                      minHeight: 8,
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text('${entry.value}', textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.report});

  final SalesReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (final product in report.topProducts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(product.name),
            subtitle: Text('${product.sku} · ${product.quantity} sold'),
            trailing: Text(
              Formatters.money(product.revenueInCents, report.currency),
            ),
          ),
      ],
    );
  }
}
