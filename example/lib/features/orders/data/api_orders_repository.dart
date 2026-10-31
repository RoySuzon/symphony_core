import 'package:symphony_core/symphony_core.dart';

import '../domain/entities/order.dart';
import '../domain/order_filter.dart';
import '../domain/repositories/orders_repository.dart';
import 'order_json.dart';

/// [OrdersRepository] backed by the package's central [ApiClient].
///
/// The repository never touches Dio: the client adds the base URL, the
/// access token (refreshing it when it expired), logging and inspection,
/// and converts every error into a `Failure`. [guardResult] turns the call
/// into a `Result` at the repository boundary.
class ApiOrdersRepository implements OrdersRepository {
  /// Creates the repository.
  const ApiOrdersRepository(this._client);

  final ApiClient _client;

  @override
  Future<Result<List<OrderSummary>>> fetchOrders({
    OrderFilter filter = const OrderFilter(),
  }) {
    final status = filter.status;
    return guardResult(() async {
      final response = await _client.get<List<OrderSummary>>(
        '/orders',
        queryParameters: <String, dynamic>{
          if (status != null) 'status': status.name,
          if (filter.query.isNotEmpty) 'q': filter.query,
        },
        decoder: OrderJson.decodeList,
      );
      return response.data;
    }, mapError: _client.mapError);
  }

  @override
  Future<Result<OrderDetail>> fetchOrder(String id) {
    return guardResult(() async {
      final response = await _client.get<OrderDetail>(
        '/orders/${Uri.encodeComponent(id)}',
        decoder: OrderJson.decodeDetail,
      );
      return response.data;
    }, mapError: _client.mapError);
  }
}
