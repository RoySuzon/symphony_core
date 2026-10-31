import 'package:flutter/foundation.dart';
import 'package:symphony_core/symphony_core.dart';

/// Revenue of one week.
@immutable
class WeeklyRevenue {
  /// Creates a data point.
  const WeeklyRevenue({required this.weekStart, required this.amountInCents});

  /// First day of the week.
  final DateTime weekStart;

  /// Revenue, in cents.
  final int amountInCents;
}

/// A best-selling product.
@immutable
class TopProduct {
  /// Creates an entry.
  const TopProduct({
    required this.sku,
    required this.name,
    required this.quantity,
    required this.revenueInCents,
  });

  /// Product reference.
  final String sku;

  /// Product name.
  final String name;

  /// Units sold.
  final int quantity;

  /// Revenue, in cents.
  final int revenueInCents;
}

/// Sales indicators computed by the backend.
@immutable
class SalesReport {
  /// Creates a report.
  const SalesReport({
    required this.currency,
    required this.generatedAt,
    required this.revenueInCents,
    required this.orderCount,
    required this.averageOrderValueInCents,
    required this.pendingOrders,
    required this.weeklyRevenue,
    required this.ordersByStatus,
    required this.topProducts,
  });

  /// Currency of every amount.
  final String currency;

  /// When the report was computed.
  final DateTime generatedAt;

  /// Revenue of non-cancelled orders, in cents.
  final int revenueInCents;

  /// Number of orders.
  final int orderCount;

  /// Average order value, in cents.
  final int averageOrderValueInCents;

  /// Orders waiting for confirmation.
  final int pendingOrders;

  /// Revenue of the last weeks, oldest first.
  final List<WeeklyRevenue> weeklyRevenue;

  /// Number of orders per status name.
  final Map<String, int> ordersByStatus;

  /// Best sellers, by revenue.
  final List<TopProduct> topProducts;

  /// Highest weekly revenue (chart scale).
  int get bestWeekInCents => weeklyRevenue.fold(
        0,
        (best, week) => week.amountInCents > best ? week.amountInCents : best,
      );
}

/// A CSV export.
@immutable
class ReportExport {
  /// Creates an export.
  const ReportExport({required this.filename, required this.content});

  /// Suggested file name.
  final String filename;

  /// CSV content.
  final String content;

  /// Number of data rows (header excluded).
  int get rowCount =>
      content.split('\n').where((line) => line.trim().isNotEmpty).length - 1;
}

/// Source of the sales reports.
abstract interface class ReportsRepository {
  /// The current sales indicators.
  Future<Result<SalesReport>> fetchSummary();

  /// The orders as CSV (permission `reports.export`).
  Future<Result<ReportExport>> exportOrders();
}
