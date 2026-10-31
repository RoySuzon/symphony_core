import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/config/symphony_config.dart';
import 'package:symphony_core/src/core/di/core_providers.dart';
import 'package:symphony_core/src/features/inspector/inspector.dart';

class _Clock {
  DateTime now = DateTime(2024, 3, 1, 10, 30);

  DateTime call() => now;
}

/// Fills [inspector] with a successful GET, a failed POST (500), a 404 and a
/// call without response.
void _seed(ApiInspector inspector, _Clock clock) {
  final users =
      inspector.startCall(
        method: 'GET',
        uri: Uri.parse('https://api.example.com/users?page=1'),
        headers: const <String, dynamic>{'accept': 'application/json'},
      )!;
  clock.now = clock.now.add(const Duration(milliseconds: 42));
  inspector.completeCall(
    users,
    statusCode: 200,
    statusMessage: 'OK',
    headers: const <String, dynamic>{'content-type': 'application/json'},
    body: const <String, Object?>{'name': 'Ada Lovelace'},
  );

  final login =
      inspector.startCall(
        method: 'POST',
        uri: Uri.parse('https://api.example.com/auth/login'),
        headers: const <String, dynamic>{'Authorization': 'Bearer secret'},
        body: const <String, Object?>{'password': 'hunter2'},
      )!;
  inspector.failCall(login, error: 'Internal failure', statusCode: 500);

  final order =
      inspector.startCall(
        method: 'DELETE',
        uri: Uri.parse('https://api.example.com/orders/7'),
      )!;
  inspector.failCall(order, error: 'Not found', statusCode: 404);

  final offline =
      inspector.startCall(
        method: 'GET',
        uri: Uri.parse('https://cdn.example.com/feed'),
      )!;
  inspector.failCall(offline, error: '[connectionError] Connection refused');
}

void main() {
  late ApiInspector inspector;
  late _Clock clock;

  setUp(() {
    clock = _Clock();
    inspector = ApiInspector(clock: clock.call);
    _seed(inspector, clock);
  });

  tearDown(() => inspector.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ApiInspectorScreen(inspector: inspector)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the captured calls with their status', (tester) async {
    await pumpScreen(tester);

    expect(find.text('API Inspector'), findsOneWidget);
    expect(find.byType(ApiCallTile), findsNWidgets(4));
    expect(find.text('/users'), findsOneWidget);
    expect(find.text('/auth/login'), findsOneWidget);
    expect(find.text('/orders/7'), findsOneWidget);
    expect(find.text('/feed'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('404'), findsOneWidget);
    expect(find.text('Failed'), findsWidgets);
    expect(find.text('10:30:00  ·  42 ms'), findsOneWidget);
    // Newest first.
    final feedTop = tester.getTopLeft(find.text('/feed')).dy;
    final usersTop = tester.getTopLeft(find.text('/users')).dy;
    expect(feedTop, lessThan(usersTop));
  });

  testWidgets('shows a spinner for pending calls', (tester) async {
    inspector.startCall(
      method: 'GET',
      uri: Uri.parse('https://api.example.com/slow'),
    );
    await tester.pumpWidget(
      MaterialApp(home: ApiInspectorScreen(inspector: inspector)),
    );
    await tester.pump();

    expect(find.text('/slow'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byKey(ApiInspectorScreen.filterChipKey(ApiCallStatusFilter.pending)),
      findsOneWidget,
    );
    expect(find.text('Pending 1'), findsOneWidget);
  });

  testWidgets('updates when new calls are recorded', (tester) async {
    await pumpScreen(tester);

    final id =
        inspector.startCall(
          method: 'PUT',
          uri: Uri.parse('https://api.example.com/profile'),
        )!;
    inspector.completeCall(id, statusCode: 204);
    await tester.pumpAndSettle();

    expect(find.text('/profile'), findsOneWidget);
    expect(find.byType(ApiCallTile), findsNWidgets(5));
  });

  testWidgets('searches and filters by status', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(
      find.byKey(ApiInspectorScreen.searchFieldKey),
      'login',
    );
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallTile), findsOneWidget);
    expect(find.text('/auth/login'), findsOneWidget);

    await tester.enterText(find.byKey(ApiInspectorScreen.searchFieldKey), '');
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallTile), findsNWidgets(4));

    await tester.tap(
      find.byKey(
        ApiInspectorScreen.filterChipKey(ApiCallStatusFilter.clientError),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallTile), findsOneWidget);
    expect(find.text('/orders/7'), findsOneWidget);

    await tester.tap(
      find.byKey(ApiInspectorScreen.filterChipKey(ApiCallStatusFilter.failed)),
    );
    await tester.pumpAndSettle();
    expect(find.text('/feed'), findsOneWidget);
    expect(find.byType(ApiCallTile), findsOneWidget);

    await tester.enterText(
      find.byKey(ApiInspectorScreen.searchFieldKey),
      'users',
    );
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallTile), findsNothing);
    expect(find.text('No matching calls'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallTile), findsNWidgets(4));
  });

  testWidgets('chips show the count of each category', (tester) async {
    await pumpScreen(tester);

    expect(find.text('All 4'), findsOneWidget);
    expect(find.text('Success 1'), findsOneWidget);
    expect(find.text('4xx 1'), findsOneWidget);
    expect(find.text('5xx 1'), findsOneWidget);
    expect(find.text('Failed 1'), findsOneWidget);
    expect(find.text('Pending 0'), findsOneWidget);
  });

  testWidgets('tapping a call opens its details with tabs', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('/users'));
    await tester.pumpAndSettle();

    expect(find.byType(ApiCallDetailScreen), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
    expect(find.text('Response'), findsOneWidget);
    expect(find.text('https://api.example.com/users?page=1'), findsOneWidget);
    expect(find.text('200 OK'), findsOneWidget);

    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();
    expect(find.text('accept: application/json'), findsOneWidget);
    expect(find.text('page: 1'), findsOneWidget);

    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();
    expect(find.text('{\n  "name": "Ada Lovelace"\n}'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallDetailScreen), findsNothing);
  });

  testWidgets('details show redacted data and the error', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('/auth/login'));
    await tester.pumpAndSettle();
    expect(find.text('Error'), findsOneWidget);
    expect(find.text('Internal failure'), findsOneWidget);

    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();
    expect(find.text('Authorization: ***'), findsOneWidget);
    expect(find.textContaining('hunter2'), findsNothing);
    expect(find.text('{\n  "password": "***"\n}'), findsOneWidget);
  });

  testWidgets('copies the call as cURL', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpScreen(tester);

    await tester.tap(find.text('/auth/login'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ApiCallDetailScreen.copyCurlButtonKey));
    await tester.pump();

    expect(copied, startsWith('curl -X POST'));
    expect(copied, contains("-H 'Authorization: ***'"));
    expect(copied, contains("'https://api.example.com/auth/login'"));
    expect(copied, isNot(contains('hunter2')));
    expect(find.text('Copied to clipboard'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('clear all asks for confirmation and empties the list', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(ApiInspectorScreen.clearAllButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Clear all calls?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(inspector.calls, hasLength(4));

    await tester.tap(find.byKey(ApiInspectorScreen.clearAllButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(inspector.calls, isEmpty);
    expect(find.byType(ApiCallTile), findsNothing);
    expect(find.text('No API calls yet'), findsOneWidget);
  });

  testWidgets('pauses and resumes the recording', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(ApiInspectorScreen.recordingButtonKey));
    await tester.pumpAndSettle();
    expect(inspector.enabled, isFalse);
    expect(
      find.text('Recording is paused: new calls are not captured.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(inspector.enabled, isTrue);
    expect(
      find.text('Recording is paused: new calls are not captured.'),
      findsNothing,
    );
  });

  testWidgets('fits a small phone at a large text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpScreen(tester);
    expect(find.byType(ApiCallTile), findsWidgets);

    await tester.tap(find.text('/auth/login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallDetailScreen), findsOneWidget);
  });

  testWidgets('uses overridable strings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ApiInspectorScreen(
          inspector: ApiInspector(),
          title: 'Réseau',
          strings: const ApiInspectorStrings(
            emptyTitle: 'Aucun appel',
            filterAll: 'Tous',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Réseau'), findsOneWidget);
    expect(find.text('Aucun appel'), findsOneWidget);
    expect(find.text('Tous 0'), findsOneWidget);
  });

  testWidgets('reads the shared inspector from the ProviderScope', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          symphonyConfigProvider.overrideWithValue(
            const SymphonyConfig(
              baseUrl: 'https://api.example.com',
              enableInspector: true,
            ),
          ),
        ],
        child: const MaterialApp(home: ApiInspectorScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No API calls yet'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ApiInspectorScreen)),
    );
    final shared = container.read(apiInspectorProvider);
    final id =
        shared.startCall(
          method: 'GET',
          uri: Uri.parse('https://api.example.com/shared'),
        )!;
    shared.completeCall(id, statusCode: 200);
    await tester.pumpAndSettle();

    expect(find.text('/shared'), findsOneWidget);
  });

  testWidgets('explains when no inspector is available', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ApiInspectorScreen()));
    await tester.pumpAndSettle();

    expect(find.text('API inspector unavailable'), findsOneWidget);
  });

  testWidgets('showApiInspector pushes the screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed:
                        () => showApiInspector(context, inspector: inspector),
                    child: const Text('Open'),
                  ),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(ApiInspectorScreen), findsOneWidget);
    expect(find.byType(ApiCallTile), findsNWidgets(4));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ApiInspectorScreen), findsNothing);
  });
}
