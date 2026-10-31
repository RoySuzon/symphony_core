import 'package:symphony_core/symphony_core.dart';

import '../../../core/network/api_envelope.dart';
import '../domain/entities/order.dart';

/// Response decoders of the orders endpoints (passed to `ApiClient` as
/// `decoder`). A malformed payload throws a [FormatException], which the
/// client turns into a `ParsingFailure`.
abstract final class OrderJson {
  /// `GET /orders` → `{"result": {"items": [...]}}`.
  static List<OrderSummary> decodeList(Object? body) => <OrderSummary>[
    for (final item in ApiEnvelope.list(body, 'items')) summary(item),
  ];

  /// `GET /orders/{id}` → `{"result": {"order": {...}}}`.
  static OrderDetail decodeDetail(Object? body) {
    final json = ApiEnvelope.requireMap(ApiEnvelope.result(body), 'order');
    final shipping = ApiEnvelope.requireMap(json, 'shipping');
    return OrderDetail(
      summary: summary(json),
      lines: <OrderLine>[
        for (final line
            in JsonReader.asList(json['lines']) ?? const <Object?>[])
          _line(line),
      ],
      subtotal: money(json['subtotal']),
      shippingFee: money(shipping['fee']),
      shippingAddress: JsonReader.asString(shipping['address']) ?? '',
      note: JsonReader.asString(json['note']),
      timeline: <OrderEvent>[
        for (final event
            in JsonReader.asList(json['timeline']) ?? const <Object?>[])
          _event(event),
      ],
    );
  }

  /// An order of a list (or the summary part of a detail payload).
  static OrderSummary summary(Object? value) {
    final json =
        JsonReader.asMap(value) ??
        (throw const FormatException('An order must be an object.'));
    final customer = ApiEnvelope.requireMap(json, 'customer');
    final status = OrderStatus.fromName(JsonReader.asString(json['status']));
    if (status == null) {
      throw FormatException('Unknown order status "${json['status']}".');
    }
    return OrderSummary(
      id: ApiEnvelope.requireString(json, 'id'),
      number: ApiEnvelope.requireString(json, 'number'),
      status: status,
      customerName: ApiEnvelope.requireString(customer, 'name'),
      customerEmail: JsonReader.asString(customer['email']) ?? '',
      total: money(json['total']),
      itemCount: JsonReader.asInt(json['item_count']) ?? 0,
      placedAt: ApiEnvelope.requireDate(json, 'placed_at'),
    );
  }

  /// `{"amount": 12990, "currency": "USD"}`.
  static Money money(Object? value) {
    final json =
        JsonReader.asMap(value) ??
        (throw const FormatException('An amount must be an object.'));
    return Money(
      amountInCents:
          JsonReader.asInt(json['amount']) ??
          (throw const FormatException('Missing amount.')),
      currency: JsonReader.asString(json['currency']) ?? 'USD',
    );
  }

  static OrderLine _line(Object? value) {
    final json =
        JsonReader.asMap(value) ??
        (throw const FormatException('An order line must be an object.'));
    return OrderLine(
      sku: ApiEnvelope.requireString(json, 'sku'),
      name: ApiEnvelope.requireString(json, 'name'),
      quantity: JsonReader.asInt(json['quantity']) ?? 1,
      unitPrice: money(json['unit_price']),
    );
  }

  static OrderEvent _event(Object? value) {
    final json =
        JsonReader.asMap(value) ??
        (throw const FormatException('An event must be an object.'));
    return OrderEvent(
      label: ApiEnvelope.requireString(json, 'status'),
      at: ApiEnvelope.requireDate(json, 'at'),
    );
  }
}
