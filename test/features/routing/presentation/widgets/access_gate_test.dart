import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/core.dart';
import 'package:symphony_core/src/features/routing/routing.dart';

import '../../routing_test_helpers.dart';

const AccessRequirement canWriteOrders = AccessRequirement(
  permissions: <String>{'orders.write'},
);

Future<ProviderContainer> pumpScoped(
  WidgetTester tester,
  Widget child, {
  AccessContext initialAccess = AccessContext.unknown,
}) async {
  await tester.pumpWidget(
    routingTestScope(
      initialAccess: initialAccess,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  return ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
    listen: false,
  );
}

void main() {
  group('AccessGate', () {
    testWidgets('shows the child to allowed users', (tester) async {
      await pumpScoped(
        tester,
        const AccessGate(
          requirement: canWriteOrders,
          fallback: Text('read only'),
          child: Text('new order'),
        ),
        initialAccess: signedIn(permissions: <String>{'orders.write'}),
      );

      expect(find.text('new order'), findsOneWidget);
      expect(find.text('read only'), findsNothing);
    });

    testWidgets('shows the fallback to other users', (tester) async {
      await pumpScoped(
        tester,
        const AccessGate(
          requirement: canWriteOrders,
          fallback: Text('read only'),
          child: Text('new order'),
        ),
        initialAccess: signedIn(),
      );

      expect(find.text('new order'), findsNothing);
      expect(find.text('read only'), findsOneWidget);
    });

    testWidgets('renders nothing without a fallback', (tester) async {
      await pumpScoped(
        tester,
        const AccessGate(
          requirement: AccessRequirement.authenticated,
          child: Text('profile'),
        ),
        initialAccess: signedOut,
      );

      expect(find.text('profile'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AccessGate),
          matching: find.byType(SizedBox),
        ),
        findsOneWidget,
      );
    });

    testWidgets('reacts to access changes', (tester) async {
      final container = await pumpScoped(
        tester,
        const AccessGate(
          requirement: AccessRequirement(roles: <String>{'admin'}),
          fallback: Text('hidden'),
          child: Text('admin panel'),
        ),
      );
      expect(find.text('hidden'), findsOneWidget);

      container
          .read(testAccessProvider.notifier)
          .set(signedIn(roles: <String>{'admin'}));
      await tester.pumpAndSettle();
      expect(find.text('admin panel'), findsOneWidget);

      container.read(testAccessProvider.notifier).set(signedOut);
      await tester.pumpAndSettle();
      expect(find.text('hidden'), findsOneWidget);
      expect(find.text('admin panel'), findsNothing);
    });
  });

  group('SymphonyAccessWidgetRef', () {
    testWidgets('watchCanAccess rebuilds and readCanAccess reads once',
        (tester) async {
      final pressed = <bool>[];
      final container = await pumpScoped(
        tester,
        Consumer(
          builder: (context, ref, child) {
            final allowed = ref.watchCanAccess(canWriteOrders);
            return TextButton(
              onPressed: () => pressed.add(ref.readCanAccess(canWriteOrders)),
              child: Text(allowed ? 'allowed' : 'denied'),
            );
          },
        ),
        initialAccess: signedIn(),
      );
      expect(find.text('denied'), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      expect(pressed, <bool>[false]);

      container
          .read(testAccessProvider.notifier)
          .set(signedIn(permissions: <String>{'orders.write'}));
      await tester.pumpAndSettle();
      expect(find.text('allowed'), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      expect(pressed, <bool>[false, true]);
    });
  });
}
