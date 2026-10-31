import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/src/core/config/symphony_config.dart';
import 'package:symphony_core/src/core/di/core_providers.dart';
import 'package:symphony_core/src/features/inspector/inspector.dart';

void _record(ApiInspector inspector, String path, {int status = 200}) {
  final id =
      inspector.startCall(
        method: 'GET',
        uri: Uri.parse('https://api.example.com$path'),
      )!;
  if (status >= 400) {
    inspector.failCall(id, error: 'HTTP $status', statusCode: status);
  } else {
    inspector.completeCall(id, statusCode: status);
  }
}

/// An app whose single button counts taps, wrapped by the overlay through
/// `MaterialApp.builder` (where no Navigator exists above the overlay).
class _App extends StatefulWidget {
  const _App({this.inspector, this.enabled});

  final ApiInspector? inspector;
  final bool? enabled;

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  int taps = 0;
  int backgroundTaps = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder:
          (context, child) => SymphonyInspectorOverlay(
            inspector: widget.inspector,
            enabled: widget.enabled,
            child: child!,
          ),
      home: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => backgroundTaps++),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ElevatedButton(
                  onPressed: () => setState(() => taps++),
                  child: Text('Taps: $taps'),
                ),
                Text('Background: $backgroundTaps'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simulates the system back button (Android) like the engine does.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(
      const MethodCall('popRoute'),
    ),
    (_) {},
  );
}

Finder get _button => find.byKey(SymphonyInspectorOverlay.buttonKey);
Finder get _panel => find.byKey(SymphonyInspectorOverlay.panelKey);

void main() {
  late ApiInspector inspector;

  setUp(() {
    inspector = ApiInspector();
    _record(inspector, '/users');
    _record(inspector, '/orders');
    _record(inspector, '/broken', status: 500);
  });

  tearDown(() => inspector.dispose());

  testWidgets('shows the floating button with call and error counts', (
    tester,
  ) async {
    await tester.pumpWidget(_App(inspector: inspector));

    expect(_button, findsOneWidget);
    expect(
      find.descendant(of: _button, matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _button, matching: find.text('1')),
      findsOneWidget,
    );

    _record(inspector, '/new');
    _record(inspector, '/again', status: 404);
    await tester.pump();

    expect(
      find.descendant(of: _button, matching: find.text('5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _button, matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('works without any ProviderScope when given an inspector', (
    tester,
  ) async {
    await tester.pumpWidget(_App(inspector: inspector));
    expect(tester.takeException(), isNull);
    expect(_button, findsOneWidget);
  });

  testWidgets('the app stays tappable while the panel is closed', (
    tester,
  ) async {
    await tester.pumpWidget(_App(inspector: inspector));

    await tester.tap(find.text('Taps: 0'));
    await tester.pump();
    expect(find.text('Taps: 1'), findsOneWidget);

    // Taps right next to the floating button reach the app underneath.
    final buttonRect = tester.getRect(_button);
    await tester.tapAt(Offset(buttonRect.left - 8, buttonRect.center.dy));
    await tester.pump();
    await tester.tapAt(Offset(buttonRect.center.dx, buttonRect.top - 8));
    await tester.pump();
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();

    expect(find.text('Background: 3'), findsOneWidget);
    expect(_panel, findsNothing);
  });

  testWidgets('opens the inspector panel and closes it', (tester) async {
    await tester.pumpWidget(_App(inspector: inspector));

    await tester.tap(_button);
    await tester.pumpAndSettle();

    expect(_panel, findsOneWidget);
    expect(find.byType(ApiInspectorScreen), findsOneWidget);
    expect(find.byType(ApiCallTile), findsNWidgets(3));
    expect(_button, findsNothing);

    // The panel has its own navigator: details open inside it.
    await tester.tap(find.text('/orders'));
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallDetailScreen), findsNothing);

    await tester.tap(find.byKey(ApiInspectorScreen.closeButtonKey));
    await tester.pumpAndSettle();

    expect(_panel, findsNothing);
    expect(find.byType(ApiInspectorScreen), findsNothing);
    expect(_button, findsOneWidget);
    await tester.tap(find.text('Taps: 0'));
    await tester.pump();
    expect(find.text('Taps: 1'), findsOneWidget);
  });

  testWidgets('the panel covers the app while open', (tester) async {
    await tester.pumpWidget(_App(inspector: inspector));
    await tester.tap(_button);
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.text('Taps: 0')));
    await tester.pump();
    expect(find.text('Taps: 1'), findsNothing);
  });

  testWidgets('the back button pops the panel pages, then closes it', (
    tester,
  ) async {
    await tester.pumpWidget(_App(inspector: inspector));
    await tester.tap(_button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('/users'));
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallDetailScreen), findsOneWidget);

    await _systemBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallDetailScreen), findsNothing);
    expect(_panel, findsOneWidget);

    await _systemBack(tester);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(_button, findsOneWidget);
  });

  testWidgets('the button can be dragged and snaps to the closest side', (
    tester,
  ) async {
    await tester.pumpWidget(_App(inspector: inspector));
    final start = tester.getTopLeft(_button);

    await tester.drag(_button, const Offset(-600, -300));
    await tester.pumpAndSettle();

    final end = tester.getTopLeft(_button);
    expect(end.dy, lessThan(start.dy - 200));
    // Dragged past the middle: snapped to the left edge (12 px margin).
    expect(end.dx, 12);
  });

  testWidgets('enabled: false renders the app only', (tester) async {
    await tester.pumpWidget(_App(inspector: inspector, enabled: false));

    expect(_button, findsNothing);
    expect(find.text('Taps: 0'), findsOneWidget);
  });

  testWidgets('works with MaterialApp.router and GoRouter', (tester) async {
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder:
              (context, state) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => context.push('/details'),
                    child: const Text('Go to details'),
                  ),
                ),
              ),
          routes: <RouteBase>[
            GoRoute(
              path: 'details',
              builder:
                  (context, state) =>
                      const Scaffold(body: Text('App details page')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder:
            (context, child) =>
                SymphonyInspectorOverlay(inspector: inspector, child: child!),
      ),
    );

    await tester.tap(find.text('Go to details'));
    await tester.pumpAndSettle();
    expect(find.text('App details page'), findsOneWidget);

    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    await tester.tap(find.text('/users'));
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallDetailScreen), findsOneWidget);

    // Back: first the panel's own page, then the panel itself...
    await _systemBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ApiCallDetailScreen), findsNothing);
    expect(_panel, findsOneWidget);
    await _systemBack(tester);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    // ...and only then the application route.
    expect(find.text('App details page'), findsOneWidget);
    await _systemBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('App details page'), findsNothing);
    expect(find.text('Go to details'), findsOneWidget);
  });

  group('with a ProviderScope', () {
    Widget scoped({required bool enableInspector, ApiInspector? explicit}) {
      return ProviderScope(
        overrides: [
          symphonyConfigProvider.overrideWithValue(
            SymphonyConfig(
              baseUrl: 'https://api.example.com',
              enableInspector: enableInspector,
            ),
          ),
        ],
        child: _App(inspector: explicit),
      );
    }

    testWidgets('follows SymphonyConfig.enableInspector', (tester) async {
      await tester.pumpWidget(scoped(enableInspector: false));
      expect(_button, findsNothing);

      await tester.pumpWidget(scoped(enableInspector: true));
      await tester.pump();
      expect(_button, findsOneWidget);
    });

    testWidgets('uses apiInspectorProvider by default', (tester) async {
      await tester.pumpWidget(scoped(enableInspector: true));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final shared = container.read(apiInspectorProvider);
      expect(shared.enabled, isTrue);

      _record(shared, '/shared');
      await tester.pump();
      expect(
        find.descendant(of: _button, matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(find.text('/shared'), findsOneWidget);
    });

    testWidgets('falls back to enabled when the config is missing', (
      tester,
    ) async {
      await tester.pumpWidget(ProviderScope(child: _App(inspector: inspector)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_button, findsOneWidget);
    });

    testWidgets('an explicit inspector wins over the provider', (tester) async {
      await tester.pumpWidget(
        scoped(enableInspector: true, explicit: inspector),
      );
      expect(
        find.descendant(of: _button, matching: find.text('3')),
        findsOneWidget,
      );
    });
  });
}
