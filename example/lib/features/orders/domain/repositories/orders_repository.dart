import 'package:symphony_core/symphony_core.dart';

import '../entities/order.dart';
import '../order_filter.dart';

/// Source of orders. The presentation layer only knows this interface; the
/// data layer implements it with the package's `ApiClient`.
abstract interface class OrdersRepository {
  /// Orders matching [filter], newest first.
  Future<Result<List<OrderSummary>>> fetchOrders({
    OrderFilter filter = const OrderFilter(),
  });

  /// The order [id], with its lines and history.
  Future<Result<OrderDetail>> fetchOrder(String id);
}
