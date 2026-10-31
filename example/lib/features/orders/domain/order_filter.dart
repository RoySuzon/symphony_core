import 'package:flutter/foundation.dart';

import 'entities/order.dart';

/// Criteria of the orders list.
@immutable
class OrderFilter {
  /// Creates a filter.
  const OrderFilter({this.status, this.query = ''});

  /// Only orders with this status (all statuses when `null`).
  final OrderStatus? status;

  /// Free text matched against the order number and the customer name.
  final String query;

  /// Whether any criterion is set.
  bool get isActive => status != null || query.isNotEmpty;

  /// A copy with [status] (which may be `null` to show every status).
  OrderFilter withStatus(OrderStatus? status) =>
      OrderFilter(status: status, query: query);

  /// A copy with [query] (trimmed).
  OrderFilter withQuery(String query) =>
      OrderFilter(status: status, query: query.trim());

  @override
  bool operator ==(Object other) =>
      other is OrderFilter && other.status == status && other.query == query;

  @override
  int get hashCode => Object.hash(status, query);
}
