import 'package:flutter/material.dart';
import 'package:symphony_core/symphony_core.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../domain/entities/order.dart';

/// Color of [status] in the current theme.
Color orderStatusColor(BuildContext context, OrderStatus status) {
  final scheme = Theme.of(context).colorScheme;
  final colors = SymphonyColors.of(context);
  return switch (status) {
    OrderStatus.pending => colors.warning,
    OrderStatus.processing => colors.info,
    OrderStatus.shipped => scheme.primary,
    OrderStatus.delivered => colors.success,
    OrderStatus.cancelled => scheme.error,
  };
}

/// Icon of [status].
IconData orderStatusIcon(OrderStatus status) => switch (status) {
      OrderStatus.pending => Icons.hourglass_top_rounded,
      OrderStatus.processing => Icons.inventory_2_outlined,
      OrderStatus.shipped => Icons.local_shipping_outlined,
      OrderStatus.delivered => Icons.task_alt_rounded,
      OrderStatus.cancelled => Icons.cancel_outlined,
    };

/// Formats [money].
String formatMoney(Money money) =>
    Formatters.money(money.amountInCents, money.currency);

/// A colored status label.
class OrderStatusChip extends StatelessWidget {
  /// Creates the chip.
  const OrderStatusChip({super.key, required this.status});

  /// Displayed status.
  final OrderStatus status;

  @override
  Widget build(BuildContext context) => TagChip(
        label: status.label,
        icon: orderStatusIcon(status),
        color: orderStatusColor(context, status),
      );
}

/// One order of the list.
class OrderTile extends StatelessWidget {
  /// Creates the tile.
  const OrderTile({super.key, required this.order, required this.onTap});

  /// Displayed order.
  final OrderSummary order;

  /// Opens the order.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = orderStatusColor(context, order.status);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(36),
          foregroundColor: color,
          child: Icon(orderStatusIcon(order.status)),
        ),
        title: Text('${order.number} · ${order.customerName}'),
        subtitle: Text(
          '${Formatters.dateTime(order.placedAt)} · '
          '${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(formatMoney(order.total), style: theme.textTheme.titleSmall),
            const SizedBox(height: SymphonySpacing.xxs),
            Text(
              order.status.label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status filter chips of the orders list.
class OrderStatusFilterBar extends StatelessWidget {
  /// Creates the bar.
  const OrderStatusFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// Selected status (`null` = all).
  final OrderStatus? selected;

  /// Called with the new selection.
  final ValueChanged<OrderStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final status in OrderStatus.values) ...<Widget>[
            const SizedBox(width: SymphonySpacing.sm),
            ChoiceChip(
              label: Text(status.label),
              selected: selected == status,
              onSelected: (_) => onSelected(status),
            ),
          ],
        ],
      ),
    );
  }
}
