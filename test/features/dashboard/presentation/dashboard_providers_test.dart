import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/src/core/access/access_context.dart';
import 'package:symphony_core/src/features/dashboard/dashboard.dart';

import '../dashboard_test_utils.dart';

List<String> ids(Iterable<DashboardItem> items) =>
    <String>[for (final item in items) item.id];

void main() {
  test('dashboardItemsProvider defaults to an empty menu', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(dashboardItemsProvider), isEmpty);
  });

  test('visibleDashboardItemsProvider filters for the current access', () {
    final container = createAccessContainer(menu: sampleMenu);

    expect(
      ids(container.read(visibleDashboardItemsProvider)),
      <String>['orders', 'help'],
    );

    changeAccess(container, signedIn(roles: <String>{'admin'}));
    expect(
      ids(container.read(visibleDashboardItemsProvider)),
      <String>['orders', 'sales', 'admin', 'help'],
    );
  });

  test('visibleDashboardItemsProvider notifies listeners on access change', () {
    final container = createAccessContainer(menu: sampleMenu);
    final updates = <List<String>>[];
    final subscription = container.listen<List<DashboardItem>>(
      visibleDashboardItemsProvider,
      (previous, next) => updates.add(ids(next)),
    );
    addTearDown(subscription.close);

    changeAccess(container, signedIn(roles: <String>{'sales'}));
    container.read(visibleDashboardItemsProvider);
    changeAccess(container, AccessContext.unauthenticated);
    container.read(visibleDashboardItemsProvider);

    expect(updates, <List<String>>[
      <String>['orders', 'sales', 'help'],
      <String>['orders', 'help'],
    ]);
  });

  test('visibleDashboardItemsProvider rejects duplicate ids in debug', () {
    final container = createAccessContainer(
      menu: const <DashboardItem>[
        DashboardItem(id: 'same', label: 'A'),
        DashboardItem(id: 'same', label: 'B'),
      ],
    );

    expect(
      () => container.read(visibleDashboardItemsProvider),
      throwsA(
        predicate<Object>(
          (error) => '$error'.contains('Duplicate DashboardItem ids: same.'),
        ),
      ),
    );
  });
}
