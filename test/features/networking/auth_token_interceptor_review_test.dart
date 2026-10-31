import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/error/failure.dart';
import 'package:symphony_core/src/features/networking/networking.dart';

import 'support/networking_fakes.dart';

/// A delegate behaving like the auth module's session delegate: a failed
/// refresh keeps the session (only [onSessionExpired] clears it), and the
/// expiry can be held open with [expiryGate] (for example while a remote
/// sign-out is in progress).
class _SessionLikeDelegate extends AuthTokenDelegate {
  _SessionLikeDelegate(this.token);

  String? token;
  Completer<void>? expiryGate;
  int refreshCalls = 0;
  int expiredCalls = 0;

  @override
  Future<String?> getAccessToken() async => token;

  @override
  Future<String?> refreshAccessToken() async {
    refreshCalls++;
    return null;
  }

  @override
  Future<void> onSessionExpired() async {
    expiredCalls++;
    final gate = expiryGate;
    if (gate != null) await gate.future;
    token = null;
  }
}

void main() {
  late FakeHttpClientAdapter adapter;

  setUp(() {
    adapter = FakeHttpClientAdapter();
  });

  ApiClient buildClient(AuthTokenDelegate delegate) {
    final client = ApiClient(
      config: testConfig(),
      httpClientAdapter: adapter,
      tokenDelegate: () => delegate,
    );
    addTearDown(client.close);
    return client;
  }

  test('a request rejected after the user signed out neither refreshes nor '
      'resurrects the session', () async {
    final delegate = FakeTokenDelegate(
      token: 'old',
      refreshedToken: 'resurrected',
    );
    adapter.responder = (options, _) {
      // The user signs out while the request is in flight; the server then
      // rejects the token it was sent with.
      delegate.token = null;
      return jsonBody(<String, Object?>{}, statusCode: 401);
    };
    final client = buildClient(delegate);

    final failure = await _failureOf(client.get<void>('/a'));

    expect(failure, isA<UnauthorizedFailure>());
    expect(delegate.refreshCalls, 0);
    expect(delegate.expiredCalls, 0);
    expect(delegate.token, isNull);
    expect(adapter.requests, hasLength(1));
  });

  test(
    'a request rejected while the session is being expired never refreshes',
    () async {
      final delegate = _SessionLikeDelegate('old')
        ..expiryGate = Completer<void>();
      adapter.responder =
          (_, _) => jsonBody(<String, Object?>{}, statusCode: 401);
      final client = buildClient(delegate);

      final first = _failureOf(client.get<void>('/first'));
      while (delegate.expiredCalls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      // The session still holds the rejected token until the expiry completes.
      final second = _failureOf(client.get<void>('/second'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      delegate.expiryGate!.complete();
      final failures = await Future.wait(<Future<Failure>>[first, second]);

      expect(failures, everyElement(isA<UnauthorizedFailure>()));
      expect(delegate.refreshCalls, 1);
      expect(delegate.expiredCalls, 1);
    },
  );

  test('a request cancelled during the refresh fails at once and is never '
      'replayed, while the refresh still serves the others', () async {
    final delegate = FakeTokenDelegate(token: 'old', refreshedToken: 'new')
      ..refreshGate = Completer<void>();
    adapter.responder =
        (options, _) =>
            options.headers['Authorization'] == 'Bearer new'
                ? jsonBody(<String, Object?>{'path': options.path})
                : jsonBody(<String, Object?>{}, statusCode: 401);
    final client = buildClient(delegate);
    final cancelToken = CancelToken();

    final cancelled = _failureOf(
      client.post<void>('/orders', cancelToken: cancelToken),
    );
    final other = client.get<Map<String, dynamic>>('/other');
    while (delegate.refreshCalls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    cancelToken.cancel();
    final failure = await cancelled.timeout(const Duration(seconds: 5));
    delegate.refreshGate!.complete();
    final response = await other;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(failure, isA<CancelledFailure>());
    expect(response.data, <String, dynamic>{'path': '/other'});
    expect(delegate.refreshCalls, 1);
    expect(delegate.expiredCalls, 0);
    expect(
      adapter.requests.where((request) => request.path == '/orders'),
      hasLength(1),
    );
  });

  test('requests scheduled by the refresh flow can refresh later', () async {
    late ApiClient client;
    Future<Failure?>? followUp;
    final delegate = FakeTokenDelegate(token: 't1');
    delegate.onRefresh = () async {
      if (delegate.refreshCalls == 1) {
        // Work started by the refresh (a listener, a timer, a provider
        // rebuild...) that sends a request once the refresh is over.
        followUp = Future<void>.delayed(
          const Duration(milliseconds: 20),
        ).then((_) => _failureOrNull(client.get<void>('/later')));
        return 't2';
      }
      return 't3';
    };
    var valid = 'Bearer t2';
    adapter.responder =
        (options, _) =>
            options.headers['Authorization'] == valid
                ? jsonBody(<String, Object?>{'ok': true})
                : jsonBody(<String, Object?>{}, statusCode: 401);
    client = buildClient(delegate);

    await client.get<void>('/first');
    expect(delegate.refreshCalls, 1);
    // The server revokes t2 before the follow-up request is sent.
    valid = 'Bearer t3';
    final failure = await followUp!.timeout(const Duration(seconds: 5));

    expect(failure, isNull);
    expect(delegate.refreshCalls, 2);
    expect(adapter.requests.last.headers['Authorization'], 'Bearer t3');
  });
}

/// Awaits [future] and returns the [Failure] it throws.
Future<Failure> _failureOf(Future<Object?> future) async {
  try {
    await future;
  } on Failure catch (failure) {
    return failure;
  }
  fail('Expected the call to throw a Failure.');
}

/// Awaits [future] and returns the [Failure] it throws, or `null`.
Future<Failure?> _failureOrNull(Future<Object?> future) async {
  try {
    await future;
    return null;
  } on Failure catch (failure) {
    return failure;
  }
}
