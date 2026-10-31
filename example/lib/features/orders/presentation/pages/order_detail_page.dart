import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/async_result_view.dart';
import '../../domain/entities/order.dart';
import '../providers/orders_providers.dart';
import '../widgets/order_widgets.dart';

/// Details of one order — a route nested below the orders list
/// (`/orders/:orderId`), so the back button returns to the list.
class OrderDetailPage extends ConsumerWidget {
  /// Creates the page for [orderId].
  const OrderDetailPage({super.key, required this.orderId});

  /// Id of the displayed order.
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = orderDetailProvider(orderId);
    return AppPage(
      title: 'Order details',
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(provider),
        ),
      ],
      body: AsyncResultView<OrderDetail>(
        value: ref.watch(provider),
        loadingMessage: 'Loading order…',
        onRetry: () => ref.invalidate(provider),
        builder: (context, order) => _OrderDetailView(order: order),
      ),
    );
  }
}

class _OrderDetailView extends StatelessWidget {
  const _OrderDetailView({required this.order});

  final OrderDetail order;

  Future<void> _requestRefund(BuildContext context) async {
    final confirmed = await SymphonyDialogs.confirm(
      context,
      title: 'Refund ${order.summary.number}?',
      message: 'The customer will be refunded '
          '${formatMoney(order.summary.total)}.',
      confirmLabel: 'Refund',
      destructive: true,
      icon: Icons.currency_exchange,
    );
    // Positive `context.mounted` checks are understood by every supported
    // analyzer version (Dart 3.0 flags `if (!context.mounted) return;`).
    if (confirmed && context.mounted) {
      SymphonySnackbar.success(
        context,
        'Refund requested (demo: no request is sent).',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = order.summary;
    final note = order.note;
    return ListView(
      children: <Widget>[
        SectionCard(
          title: summary.number,
          subtitle: 'Placed ${Formatters.dateTime(summary.placedAt)}',
          icon: Icons.receipt_long_outlined,
          trailing: OrderStatusChip(status: summary.status),
          child: Column(
            children: <Widget>[
              InfoRow(label: 'Customer', value: summary.customerName),
              InfoRow(label: 'E-mail', value: summary.customerEmail),
              InfoRow(label: 'Ship to', value: order.shippingAddress),
              if (note != null) InfoRow(label: 'Note', value: note),
            ],
          ),
        ),
        const SizedBox(height: SymphonySpacing.lg),
        SectionCard(
          title: 'Items',
          icon: Icons.shopping_bag_outlined,
          child: Column(
            children: <Widget>[
              for (final line in order.lines)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(line.name),
                  subtitle: Text(
                    '${line.sku} · ${line.quantity} × '
                    '${formatMoney(line.unitPrice)}',
                  ),
                  trailing: Text(formatMoney(line.total)),
                ),
              const Divider(),
              InfoRow(label: 'Subtotal', value: formatMoney(order.subtotal)),
              InfoRow(
                label: 'Shipping',
                value: order.shippingFee.amountInCents == 0
                    ? 'Free'
                    : formatMoney(order.shippingFee),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('Total', style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    formatMoney(summary.total),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: SymphonySpacing.lg),
        SectionCard(
          title: 'History',
          icon: Icons.timeline,
          child: Column(
            children: <Widget>[
              for (final event in order.timeline)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.circle, size: 12),
                  title: Text(event.label.capitalize()),
                  trailing: Text(Formatters.dateTime(event.at)),
                ),
            ],
          ),
        ),
        const SizedBox(height: SymphonySpacing.lg),
        // Visible only with the `orders.write` permission (admin).
        AccessGate(
          requirement: const AccessRequirement(
            permissions: <String>{'orders.write'},
          ),
          fallback: Text(
            'Refunds require the orders.write permission.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          child: SymphonyButton(
            label: 'Refund order',
            icon: Icons.currency_exchange,
            variant: SymphonyButtonVariant.danger,
            onPressed: summary.status == OrderStatus.cancelled
                ? null
                : () => _requestRefund(context),
          ),
        ),
        const SizedBox(height: SymphonySpacing.lg),
      ],
    );
  }
}
