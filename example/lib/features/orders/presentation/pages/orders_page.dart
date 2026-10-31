import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/async_result_view.dart';
import '../../domain/entities/order.dart';
import '../providers/orders_providers.dart';
import '../widgets/order_widgets.dart';

/// Orders list: search (debounced), status filter, pull to refresh.
///
/// Guarded by the `orders.read` permission in the router; the data comes
/// from [ordersProvider] (repository → `ApiClient` → demo backend).
class OrdersPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  final Debouncer _debouncer = Debouncer(const Duration(milliseconds: 350));
  late final TextEditingController _search =
      TextEditingController(text: ref.read(orderFilterProvider).query);

  @override
  void dispose() {
    _debouncer.dispose();
    _search.dispose();
    super.dispose();
  }

  OrderFilterController get _filter => ref.read(orderFilterProvider.notifier);

  void _clearFilters() {
    _search.clear();
    _filter.clear();
  }

  Future<void> _refresh() async {
    ref.invalidate(ordersProvider);
    await ref.read(ordersProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(orderFilterProvider);
    final orders = ref.watch(ordersProvider);
    return AppPage(
      title: 'Orders',
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(ordersProvider),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SymphonyTextField(
            controller: _search,
            hint: 'Search by order number or customer',
            prefixIcon: Icons.search,
            textInputAction: TextInputAction.search,
            onChanged: (value) => _debouncer.run(() => _filter.search(value)),
            onSubmitted: (value) {
              _debouncer.cancel();
              _filter.search(value);
            },
          ),
          const SizedBox(height: SymphonySpacing.md),
          OrderStatusFilterBar(
            selected: filter.status,
            onSelected: _filter.selectStatus,
          ),
          const SizedBox(height: SymphonySpacing.md),
          Expanded(
            child: AsyncResultView<List<OrderSummary>>(
              value: orders,
              loadingMessage: 'Loading orders…',
              onRetry: () => ref.invalidate(ordersProvider),
              isEmpty: (items) => items.isEmpty,
              emptyBuilder: (context) => SymphonyEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No orders found',
                message: filter.isActive
                    ? 'No order matches these filters.'
                    : 'New orders will appear here.',
                actionLabel: filter.isActive ? 'Clear filters' : null,
                onAction: filter.isActive ? _clearFilters : null,
              ),
              builder: (context, items) => RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: SymphonySpacing.sm),
                  itemBuilder: (context, index) {
                    final order = items[index];
                    return OrderTile(
                      order: order,
                      onTap: () => context.go(AppRoutes.orderDetail(order.id)),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
