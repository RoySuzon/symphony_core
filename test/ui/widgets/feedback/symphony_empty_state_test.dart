import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/ui/ui.dart';

import '../../ui_test_utils.dart';

void main() {
  group('SymphonyEmptyState', () {
    testWidgets('renders the title, message and default icon', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SymphonyEmptyState(
            title: 'No orders yet',
            message: 'Orders you place will appear here.',
          ),
        ),
      );

      expect(find.text('No orders yet'), findsOneWidget);
      expect(find.text('Orders you place will appear here.'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.byType(SymphonyButton), findsNothing);
    });

    testWidgets('shows the action button and calls onAction', (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        buildTestApp(
          SymphonyEmptyState(
            title: 'No invoices',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Create invoice',
            actionIcon: Icons.add,
            onAction: () => actions++,
          ),
        ),
      );

      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      await tester.tap(find.text('Create invoice'));
      expect(actions, 1);
    });

    testWidgets('hides the action without a callback', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SymphonyEmptyState(title: 'Empty', actionLabel: 'Add'),
        ),
      );

      expect(find.text('Add'), findsNothing);
    });

    testWidgets('renders a custom action widget', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const SymphonyEmptyState(
            title: 'Empty',
            action: Text('Custom action'),
          ),
        ),
      );

      expect(find.text('Custom action'), findsOneWidget);
    });

    testWidgets('uses a smaller layout in compact mode', (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        buildTestApp(
          SymphonyEmptyState(
            title: 'Nothing here',
            compact: true,
            actionLabel: 'Refresh',
            onAction: () => actions++,
          ),
        ),
      );

      expect(tester.widget<Icon>(find.byIcon(Icons.inbox_outlined)).size, 32);
      expect(find.byType(TextButton), findsOneWidget);
      await tester.tap(find.text('Refresh'));
      expect(actions, 1);

      await tester.pumpWidget(
        buildTestApp(const SymphonyEmptyState(title: 'Nothing here')),
      );
      expect(tester.widget<Icon>(find.byIcon(Icons.inbox_outlined)).size, 40);
    });
  });
}
