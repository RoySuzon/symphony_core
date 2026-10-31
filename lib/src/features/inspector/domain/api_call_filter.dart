import 'package:flutter/foundation.dart';

import 'api_call_record.dart';

/// Status categories used to filter captured calls.
///
/// Every completed call belongs to exactly one of [success], [clientError],
/// [serverError] or [failed]; in-flight calls belong to [pending]; [all]
/// matches everything.
enum ApiCallStatusFilter {
  /// Every call.
  all,

  /// Completed calls without error (2xx, and 1xx/3xx accepted by the client).
  success,

  /// Calls answered with a 4xx status.
  clientError,

  /// Calls answered with a 5xx status.
  serverError,

  /// Calls that failed without a 4xx/5xx status: no response (connection
  /// error, timeout, cancellation) or a status rejected by the client.
  failed,

  /// Calls still waiting for a response.
  pending;

  /// Whether [record] belongs to this category.
  bool matches(ApiCallRecord record) {
    final code = record.statusCode;
    switch (this) {
      case ApiCallStatusFilter.all:
        return true;
      case ApiCallStatusFilter.pending:
        return record.isPending;
      case ApiCallStatusFilter.success:
        return !record.isPending && !record.isError;
      case ApiCallStatusFilter.clientError:
        return !record.isPending && code != null && code >= 400 && code < 500;
      case ApiCallStatusFilter.serverError:
        return !record.isPending && code != null && code >= 500 && code < 600;
      case ApiCallStatusFilter.failed:
        return !record.isPending &&
            record.isError &&
            (code == null || code < 400 || code >= 600);
    }
  }
}

/// Pure, immutable filter over captured calls: a free-text [query] plus a
/// [status] category.
///
/// The query is split on white space and every term must appear
/// (case-insensitively) in the method, the URL (raw or percent-decoded), the
/// status code/message or the error text of a call.
///
/// ```dart
/// const filter = ApiCallFilter(query: 'post login', status: ApiCallStatusFilter.clientError);
/// final visible = filter.apply(inspector.calls);
/// ```
@immutable
class ApiCallFilter {
  /// Creates a filter. The default instance matches every call.
  const ApiCallFilter({this.query = '', this.status = ApiCallStatusFilter.all});

  /// A filter matching every call.
  static const ApiCallFilter none = ApiCallFilter();

  /// Free-text query.
  final String query;

  /// Status category.
  final ApiCallStatusFilter status;

  /// Lower-case search terms of [query].
  List<String> get terms => _termsOf(query);

  /// Whether this filter excludes anything.
  bool get isActive => status != ApiCallStatusFilter.all || terms.isNotEmpty;

  /// Whether [record] matches both [query] and [status].
  bool matches(ApiCallRecord record) =>
      status.matches(record) && _matchesTerms(record, terms);

  /// Whether [record] matches [query] (ignoring [status]).
  bool matchesQuery(ApiCallRecord record) => _matchesTerms(record, terms);

  /// The records of [records] matching this filter, in their original order.
  List<ApiCallRecord> apply(Iterable<ApiCallRecord> records) {
    final searchTerms = terms;
    return <ApiCallRecord>[
      for (final record in records)
        if (status.matches(record) && _matchesTerms(record, searchTerms))
          record,
    ];
  }

  /// Number of [records] in each [ApiCallStatusFilter] category.
  static Map<ApiCallStatusFilter, int> countByStatus(
    Iterable<ApiCallRecord> records,
  ) {
    final counts = <ApiCallStatusFilter, int>{
      for (final status in ApiCallStatusFilter.values) status: 0,
    };
    for (final record in records) {
      for (final status in ApiCallStatusFilter.values) {
        if (status.matches(record)) counts[status] = counts[status]! + 1;
      }
    }
    return counts;
  }

  /// Returns a copy with the given fields replaced.
  ApiCallFilter copyWith({String? query, ApiCallStatusFilter? status}) {
    return ApiCallFilter(
      query: query ?? this.query,
      status: status ?? this.status,
    );
  }

  static List<String> _termsOf(String query) => query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList(growable: false);

  static bool _matchesTerms(ApiCallRecord record, List<String> terms) {
    if (terms.isEmpty) return true;
    final url = record.uri.toString();
    final haystack =
        <String>[
          record.method,
          url,
          _decode(url),
          record.statusLabel,
          record.statusMessage ?? '',
          record.error ?? '',
        ].join('\n').toLowerCase();
    return terms.every(haystack.contains);
  }

  static String _decode(String url) {
    try {
      return Uri.decodeFull(url);
    } on ArgumentError {
      return url;
    } on FormatException {
      return url;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ApiCallFilter && other.query == query && other.status == status;

  @override
  int get hashCode => Object.hash(query, status);

  @override
  String toString() => 'ApiCallFilter(query: "$query", status: ${status.name})';
}
