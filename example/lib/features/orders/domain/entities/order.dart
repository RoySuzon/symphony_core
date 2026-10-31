import 'package:flutter/foundation.dart';

/// Lifecycle of an order.
enum OrderStatus {
  /// Waiting for payment or confirmation.
  pending('Pending'),

  /// Being prepared.
  processing('Processing'),

  /// Handed to the carrier.
  shipped('Shipped'),

  /// Received by the customer.
  delivered('Delivered'),

  /// Cancelled.
  cancelled('Cancelled');

  const OrderStatus(this.label);

  /// Display name.
  final String label;

  /// The status named [name] (as sent by the API), or `null`.
  static OrderStatus? fromName(String? name) {
    for (final status in values) {
      if (status.name == name) return status;
    }
    return null;
  }
}

/// An amount of money in the smallest currency unit.
@immutable
class Money {
  /// Creates an amount.
  const Money({required this.amountInCents, required this.currency});

  /// Amount in cents.
  final int amountInCents;

  /// ISO 4217 currency code.
  final String currency;

  /// This amount multiplied by [factor].
  Money times(int factor) =>
      Money(amountInCents: amountInCents * factor, currency: currency);

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.amountInCents == amountInCents &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(amountInCents, currency);
}

/// An order as listed by the orders screen.
@immutable
class OrderSummary {
  /// Creates a summary.
  const OrderSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.customerName,
    required this.customerEmail,
    required this.total,
    required this.itemCount,
    required this.placedAt,
  });

  /// Order id (used in URLs).
  final String id;

  /// Human readable number, e.g. `SO-1018`.
  final String number;

  /// Current status.
  final OrderStatus status;

  /// Customer name.
  final String customerName;

  /// Customer e-mail.
  final String customerEmail;

  /// Grand total.
  final Money total;

  /// Number of items.
  final int itemCount;

  /// Placement date.
  final DateTime placedAt;
}

/// One product line of an order.
@immutable
class OrderLine {
  /// Creates a line.
  const OrderLine({
    required this.sku,
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  /// Product reference.
  final String sku;

  /// Product name.
  final String name;

  /// Quantity.
  final int quantity;

  /// Unit price.
  final Money unitPrice;

  /// Line total.
  Money get total => unitPrice.times(quantity);
}

/// A step of the order history.
@immutable
class OrderEvent {
  /// Creates an event.
  const OrderEvent({required this.label, required this.at});

  /// What happened (`placed`, `shipped`...).
  final String label;

  /// When it happened.
  final DateTime at;
}

/// A complete order.
@immutable
class OrderDetail {
  /// Creates an order.
  const OrderDetail({
    required this.summary,
    required this.lines,
    required this.subtotal,
    required this.shippingFee,
    required this.shippingAddress,
    required this.timeline,
    this.note,
  });

  /// Summary fields (number, status, customer, total...).
  final OrderSummary summary;

  /// Ordered products.
  final List<OrderLine> lines;

  /// Sum of the lines.
  final Money subtotal;

  /// Shipping fee.
  final Money shippingFee;

  /// Delivery address.
  final String shippingAddress;

  /// Customer note.
  final String? note;

  /// Order history, oldest first.
  final List<OrderEvent> timeline;
}
