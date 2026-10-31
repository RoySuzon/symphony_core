import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/features/inspector/inspector.dart';

void main() {
  final started = DateTime(2024);
  final ended = started.add(const Duration(milliseconds: 40));

  ApiCallRecord call(
    int id, {
    String method = 'GET',
    String url = 'https://api.example.com/users',
    int? statusCode,
    String? statusMessage,
    String? error,
    bool pending = false,
  }) {
    return ApiCallRecord(
      id: id,
      method: method,
      uri: Uri.parse(url),
      startedAt: started,
      endedAt: pending ? null : ended,
      statusCode: statusCode,
      statusMessage: statusMessage,
      error: error,
    );
  }

  final ok = call(1, statusCode: 200, statusMessage: 'OK');
  final redirect = call(2, statusCode: 304);
  final notFound = call(
    3,
    url: 'https://api.example.com/orders/42',
    statusCode: 404,
    error: '[badResponse] Not found',
  );
  final serverError = call(
    4,
    method: 'POST',
    url: 'https://api.example.com/auth/login',
    statusCode: 503,
    error: '[badResponse] Unavailable',
  );
  final offline = call(
    5,
    method: 'DELETE',
    url: 'https://files.example.com/r%C3%A9sum%C3%A9.txt',
    error: '[connectionError] Connection refused',
  );
  final pending = call(6, method: 'PATCH', pending: true);
  final all = <ApiCallRecord>[
    ok,
    redirect,
    notFound,
    serverError,
    offline,
    pending,
  ];

  group('ApiCallStatusFilter', () {
    test('classifies every call in exactly one non-"all" category', () {
      for (final record in all) {
        final categories = ApiCallStatusFilter.values
            .where((status) => status != ApiCallStatusFilter.all)
            .where((status) => status.matches(record));
        expect(categories, hasLength(1), reason: '$record');
      }
    });

    test('matches the expected calls', () {
      List<int> ids(ApiCallStatusFilter status) => <int>[
        for (final record in all)
          if (status.matches(record)) record.id,
      ];
      expect(ids(ApiCallStatusFilter.all), <int>[1, 2, 3, 4, 5, 6]);
      expect(ids(ApiCallStatusFilter.success), <int>[1, 2]);
      expect(ids(ApiCallStatusFilter.clientError), <int>[3]);
      expect(ids(ApiCallStatusFilter.serverError), <int>[4]);
      expect(ids(ApiCallStatusFilter.failed), <int>[5]);
      expect(ids(ApiCallStatusFilter.pending), <int>[6]);
    });

    test('a rejected 3xx is a failure', () {
      final rejected = call(7, statusCode: 302, error: '[badResponse] Found');
      expect(ApiCallStatusFilter.failed.matches(rejected), isTrue);
      expect(ApiCallStatusFilter.success.matches(rejected), isFalse);
    });
  });

  group('ApiCallFilter', () {
    test('the default filter matches everything', () {
      expect(ApiCallFilter.none.isActive, isFalse);
      expect(ApiCallFilter.none.apply(all), all);
    });

    test('searches method, url, status and error case-insensitively', () {
      List<int> search(String query) => <int>[
        for (final record in ApiCallFilter(query: query).apply(all)) record.id,
      ];
      expect(search('post'), <int>[4]);
      expect(search('ORDERS'), <int>[3]);
      expect(search('503'), <int>[4]);
      expect(search('refused'), <int>[5]);
      expect(search('ok'), <int>[1]);
      expect(search('files.example.com'), <int>[5]);
    });

    test('matches percent-decoded URLs', () {
      expect(const ApiCallFilter(query: 'résumé').apply(all), <ApiCallRecord>[
        offline,
      ]);
    });

    test('requires every term to match', () {
      expect(
        const ApiCallFilter(query: 'post login').apply(all),
        <ApiCallRecord>[serverError],
      );
      expect(const ApiCallFilter(query: 'post orders').apply(all), isEmpty);
      expect(const ApiCallFilter(query: '   ').isActive, isFalse);
    });

    test('combines the query with the status', () {
      const filter = ApiCallFilter(
        query: 'example.com',
        status: ApiCallStatusFilter.clientError,
      );
      expect(filter.isActive, isTrue);
      expect(filter.apply(all), <ApiCallRecord>[notFound]);
      expect(filter.matches(notFound), isTrue);
      expect(filter.matches(ok), isFalse);
      expect(filter.matchesQuery(ok), isTrue);
    });

    test('countByStatus counts each category', () {
      final counts = ApiCallFilter.countByStatus(all);
      expect(counts[ApiCallStatusFilter.all], 6);
      expect(counts[ApiCallStatusFilter.success], 2);
      expect(counts[ApiCallStatusFilter.clientError], 1);
      expect(counts[ApiCallStatusFilter.serverError], 1);
      expect(counts[ApiCallStatusFilter.failed], 1);
      expect(counts[ApiCallStatusFilter.pending], 1);
      expect(
        ApiCallFilter.countByStatus(const <ApiCallRecord>[]).values,
        everyElement(0),
      );
    });

    test('copyWith and equality', () {
      const filter = ApiCallFilter(query: 'a');
      final copy = filter.copyWith(status: ApiCallStatusFilter.pending);
      expect(copy.query, 'a');
      expect(copy.status, ApiCallStatusFilter.pending);
      expect(
        copy,
        const ApiCallFilter(query: 'a', status: ApiCallStatusFilter.pending),
      );
      expect(
        copy.hashCode,
        const ApiCallFilter(
          query: 'a',
          status: ApiCallStatusFilter.pending,
        ).hashCode,
      );
      expect(copy == filter, isFalse);
    });
  });
}
