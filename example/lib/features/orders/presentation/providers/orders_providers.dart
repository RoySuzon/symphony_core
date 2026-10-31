import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../data/api_orders_repository.dart';
import '../../domain/entities/order.dart';
import '../../domain/order_filter.dart';
import '../../domain/repositories/orders_repository.dart';

/// The orders repository, built on the shared `ApiClient`.
final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => ApiOrdersRepository(ref.watch(apiClientProvider)),
  name: 'ordersRepositoryProvider',
);

/// Current criteria of the orders list.
class OrderFilterController extends Notifier<OrderFilter> {
  @override
  OrderFilter build() => const OrderFilter();

  /// Shows only [status] (every status when `null`).
  void selectStatus(OrderStatus? status) => state = state.withStatus(status);

  /// Filters by order number or customer name.
  void search(String query) => state = state.withQuery(query);

  /// Removes every criterion.
  void clear() => state = const OrderFilter();
}

/// Criteria of the orders list.
final orderFilterProvider =
    NotifierProvider<OrderFilterController, OrderFilter>(
      OrderFilterController.new,
      name: 'orderFilterProvider',
    );

/// The orders matching [orderFilterProvider].
///
/// Scoped to the signed-in user: it refetches when another user signs in
/// and sends no request while signed out.
final ordersProvider = FutureProvider<Result<List<OrderSummary>>>((ref) {
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  if (userId == null) {
    return const Result<List<OrderSummary>>.failure(UnauthorizedFailure());
  }
  final filter = ref.watch(orderFilterProvider);
  return ref.watch(ordersRepositoryProvider).fetchOrders(filter: filter);
}, name: 'ordersProvider');

/// One order with its lines, by id.
final orderDetailProvider = FutureProvider.family<Result<OrderDetail>, String>((
  ref,
  id,
) {
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  if (userId == null) {
    return const Result<OrderDetail>.failure(UnauthorizedFailure());
  }
  return ref.watch(ordersRepositoryProvider).fetchOrder(id);
}, name: 'orderDetailProvider');

/// Number of pending orders, shown as the dashboard badge of the Orders
/// module. `null` when the user cannot read orders or the count failed.
final pendingOrdersCountProvider = FutureProvider<int?>((ref) async {
  final canRead = ref.watch(
    accessContextProvider.select(
      (access) => access.hasPermission('orders.read'),
    ),
  );
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  if (!canRead || userId == null) return null;
  final result = await ref
      .watch(ordersRepositoryProvider)
      .fetchOrders(filter: const OrderFilter(status: OrderStatus.pending));
  return result.valueOrNull?.length;
}, name: 'pendingOrdersCountProvider');
