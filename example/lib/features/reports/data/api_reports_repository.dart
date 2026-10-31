import 'dart:convert';

import 'package:symphony_core/symphony_core.dart';

import '../../../core/network/api_envelope.dart';
import '../domain/sales_report.dart';

/// [ReportsRepository] backed by the package's [ApiClient].
class ApiReportsRepository implements ReportsRepository {
  /// Creates the repository.
  const ApiReportsRepository(this._client);

  final ApiClient _client;

  @override
  Future<Result<SalesReport>> fetchSummary() => guardResult(
        () async {
          final response = await _client.get<SalesReport>(
            '/reports/summary',
            decoder: decodeSalesReport,
          );
          return response.data;
        },
        mapError: _client.mapError,
      );

  @override
  Future<Result<ReportExport>> exportOrders() => guardResult(
        () async {
          final response = await _client.downloadBytes('/reports/export');
          return ReportExport(
            filename: _filename(response.header('content-disposition')) ??
                'orders-report.csv',
            content: utf8.decode(response.data, allowMalformed: true),
          );
        },
        mapError: _client.mapError,
      );

  static String? _filename(String? disposition) {
    if (disposition == null) return null;
    final match = RegExp('filename="([^"]+)"').firstMatch(disposition);
    return match?.group(1);
  }
}

/// Decodes `GET /reports/summary`.
SalesReport decodeSalesReport(Object? body) {
  final json = ApiEnvelope.result(body);
  final kpis = ApiEnvelope.requireMap(json, 'kpis');
  final byStatus =
      JsonReader.asMap(json['status_breakdown']) ?? const <String, Object?>{};
  return SalesReport(
    currency: JsonReader.asString(json['currency']) ?? 'USD',
    generatedAt: ApiEnvelope.requireDate(json, 'generated_at'),
    revenueInCents: JsonReader.asInt(kpis['revenue']) ?? 0,
    orderCount: JsonReader.asInt(kpis['orders']) ?? 0,
    averageOrderValueInCents:
        JsonReader.asInt(kpis['average_order_value']) ?? 0,
    pendingOrders: JsonReader.asInt(kpis['pending_orders']) ?? 0,
    weeklyRevenue: <WeeklyRevenue>[
      for (final week
          in JsonReader.asList(json['weekly_revenue']) ?? const <Object?>[])
        WeeklyRevenue(
          weekStart: ApiEnvelope.requireDate(
            JsonReader.asMap(week) ?? const <String, Object?>{},
            'week_start',
          ),
          amountInCents:
              JsonReader.asInt(JsonReader.asMap(week)?['amount']) ?? 0,
        ),
    ],
    ordersByStatus: <String, int>{
      for (final entry in byStatus.entries)
        entry.key: JsonReader.asInt(entry.value) ?? 0,
    },
    topProducts: <TopProduct>[
      for (final item
          in JsonReader.asList(json['top_products']) ?? const <Object?>[])
        _topProduct(JsonReader.asMap(item) ?? const <String, Object?>{}),
    ],
  );
}

TopProduct _topProduct(Map<String, Object?> json) => TopProduct(
      sku: ApiEnvelope.requireString(json, 'sku'),
      name: JsonReader.asString(json['name']) ?? '',
      quantity: JsonReader.asInt(json['quantity']) ?? 0,
      revenueInCents: JsonReader.asInt(json['revenue']) ?? 0,
    );
