import 'dart:convert';
import 'dart:typed_data';

/// Password of every demo account.
const String demoPassword = 'password123';

/// Verification code accepted by the demo password reset endpoint.
const String demoResetCode = '123456';

/// Every permission known by the demo backend.
const Set<String> demoAllPermissions = <String>{
  'orders.read',
  'orders.write',
  'reports.view',
  'reports.export',
  'users.manage',
  'audit.view',
};

/// A user account of the demo backend.
class DemoAccount {
  /// Creates an account.
  DemoAccount({
    required this.id,
    required this.email,
    required this.password,
    required this.givenName,
    required this.familyName,
    required this.roles,
    required this.permissions,
    required this.department,
    required this.createdAt,
    this.emailVerified = true,
  });

  /// Account id.
  final String id;

  /// Sign-in e-mail.
  final String email;

  /// Plain-text password (demo only!).
  String password;

  /// First name.
  final String givenName;

  /// Last name.
  final String familyName;

  /// Role names.
  final Set<String> roles;

  /// Permission names.
  final Set<String> permissions;

  /// Free-form attribute returned with the profile.
  final String department;

  /// Whether the e-mail address was verified.
  final bool emailVerified;

  /// Creation date.
  final DateTime createdAt;

  /// Last successful sign-in.
  DateTime? lastLoginAt;

  /// Full name.
  String get fullName => '$givenName $familyName'.trim();

  /// The account as returned by the authentication endpoints — a
  /// deliberately non-standard shape, decoded on the client by a custom
  /// `AuthResponseMapping`.
  Map<String, Object?> toAccountJson() => <String, Object?>{
        'uid': id,
        'profile': <String, Object?>{
          'given_name': givenName,
          'family_name': familyName,
          'avatar': null,
        },
        'contact': <String, Object?>{'mail': email},
        'groups': <Object?>[
          for (final role in roles)
            <String, Object?>{'slug': role, 'label': _label(role)},
        ],
        // OAuth-style space separated scopes.
        'grants': (permissions.toList()..sort()).join(' '),
        'department': department,
        'email_verified': emailVerified,
        'member_since': createdAt.toIso8601String(),
      };

  /// The account as listed by the administration endpoints.
  Map<String, Object?> toAdminJson() => <String, Object?>{
        'id': id,
        'name': fullName,
        'email': email,
        'roles': roles.toList()..sort(),
        'permissions': permissions.toList()..sort(),
        'department': department,
        'status': emailVerified ? 'active' : 'pending_verification',
        'last_login_at': lastLoginAt?.toIso8601String(),
      };

  static String _label(String role) =>
      role.isEmpty ? role : role[0].toUpperCase() + role.substring(1);
}

/// A product of the demo catalog.
class DemoProduct {
  /// Creates a product.
  const DemoProduct(this.sku, this.name, this.priceInCents);

  /// Stock keeping unit.
  final String sku;

  /// Display name.
  final String name;

  /// Unit price, in cents.
  final int priceInCents;
}

/// An order line.
class DemoOrderLine {
  /// Creates a line.
  const DemoOrderLine(this.product, this.quantity);

  /// Ordered product.
  final DemoProduct product;

  /// Quantity.
  final int quantity;

  /// Line total, in cents.
  int get totalInCents => product.priceInCents * quantity;
}

/// A customer order.
class DemoOrder {
  /// Creates an order.
  const DemoOrder({
    required this.id,
    required this.number,
    required this.customerName,
    required this.customerEmail,
    required this.status,
    required this.placedAt,
    required this.lines,
    required this.address,
    this.note,
  });

  /// Order id.
  final String id;

  /// Human readable number.
  final String number;

  /// Customer name.
  final String customerName;

  /// Customer e-mail.
  final String customerEmail;

  /// `pending`, `processing`, `shipped`, `delivered` or `cancelled`.
  final String status;

  /// Placement date.
  final DateTime placedAt;

  /// Ordered products.
  final List<DemoOrderLine> lines;

  /// Shipping address.
  final String address;

  /// Optional customer note.
  final String? note;

  /// Sum of the lines, in cents.
  int get subtotalInCents =>
      lines.fold(0, (sum, line) => sum + line.totalInCents);

  /// Shipping fee: free above $100.
  int get shippingInCents => subtotalInCents >= 10000 ? 0 : 995;

  /// Grand total, in cents.
  int get totalInCents => subtotalInCents + shippingInCents;

  /// Number of items.
  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  static Map<String, Object?> _money(int cents) =>
      <String, Object?>{'amount': cents, 'currency': 'USD'};

  /// The order as listed by `GET /orders`.
  Map<String, Object?> toSummaryJson() => <String, Object?>{
        'id': id,
        'number': number,
        'status': status,
        'customer': <String, Object?>{
          'name': customerName,
          'email': customerEmail,
        },
        'total': _money(totalInCents),
        'item_count': itemCount,
        'placed_at': placedAt.toIso8601String(),
      };

  /// The order as returned by `GET /orders/{id}`.
  Map<String, Object?> toDetailJson() => <String, Object?>{
        ...toSummaryJson(),
        'lines': <Object?>[
          for (final line in lines)
            <String, Object?>{
              'sku': line.product.sku,
              'name': line.product.name,
              'quantity': line.quantity,
              'unit_price': _money(line.product.priceInCents),
            },
        ],
        'subtotal': _money(subtotalInCents),
        'shipping': <String, Object?>{
          'fee': _money(shippingInCents),
          'address': address,
        },
        'note': note,
        'timeline': _timeline(),
      };

  List<Object?> _timeline() {
    const flow = <String>['pending', 'processing', 'shipped', 'delivered'];
    final events = <Object?>[
      <String, Object?>{'status': 'placed', 'at': placedAt.toIso8601String()},
    ];
    final reached = status == 'cancelled' ? 0 : flow.indexOf(status);
    for (var step = 1; step <= reached; step++) {
      events.add(<String, Object?>{
        'status': flow[step],
        'at': placedAt.add(Duration(hours: 9 * step)).toIso8601String(),
      });
    }
    if (status == 'cancelled') {
      events.add(<String, Object?>{
        'status': 'cancelled',
        'at': placedAt.add(const Duration(hours: 3)).toIso8601String(),
      });
    }
    return events;
  }
}

/// A file stored by the demo backend.
class DemoStoredFile {
  /// Creates a file whose content is produced on first use.
  DemoStoredFile({
    required this.id,
    required this.name,
    required this.contentType,
    required this.uploadedAt,
    required this.uploadedBy,
    required Uint8List Function() content,
  }) : _content = content;

  /// File id.
  final String id;

  /// File name.
  final String name;

  /// MIME type.
  final String contentType;

  /// Upload date.
  final DateTime uploadedAt;

  /// Who uploaded it.
  final String uploadedBy;

  final Uint8List Function() _content;
  Uint8List? _bytes;

  /// File content.
  Uint8List get bytes => _bytes ??= _content();

  /// The file as listed by `GET /files`.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'size': bytes.length,
        'content_type': contentType,
        'uploaded_at': uploadedAt.toIso8601String(),
        'uploaded_by': uploadedBy,
      };
}

/// An entry of the audit log.
class DemoAuditEvent {
  /// Creates an event.
  const DemoAuditEvent({
    required this.id,
    required this.at,
    required this.actor,
    required this.action,
    required this.summary,
  });

  /// Event id.
  final String id;

  /// Event date.
  final DateTime at;

  /// E-mail of the user who triggered it (or `system`).
  final String actor;

  /// Dotted action name, e.g. `auth.login`.
  final String action;

  /// Human readable description.
  final String summary;

  /// The event as listed by `GET /admin/audit-log`.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'at': at.toIso8601String(),
        'actor': actor,
        'action': action,
        'summary': summary,
      };
}

/// The deterministic data set of the demo backend.
///
/// Everything is generated from fixed tables, so every run (and every test)
/// sees exactly the same accounts, orders and files.
class DemoDatabase {
  /// Creates the seeded data set.
  DemoDatabase()
      : accounts = _seedAccounts(),
        orders = _seedOrders() {
    files.addAll(_seedFiles(orders));
    auditLog.addAll(_seedAudit());
  }

  /// Reference instant of the seed data.
  static final DateTime seedDate = DateTime.utc(2026, 10, 30, 16);

  /// Accounts (registration adds more).
  final List<DemoAccount> accounts;

  /// Orders, newest first.
  final List<DemoOrder> orders;

  /// Stored files, newest first.
  final List<DemoStoredFile> files = <DemoStoredFile>[];

  /// Audit log, newest first.
  final List<DemoAuditEvent> auditLog = <DemoAuditEvent>[];

  int _fileSequence = 0;
  int _eventSequence = 0;

  /// The account signing in with [email] (case-insensitive), if any.
  DemoAccount? accountByEmail(String email) {
    final normalized = email.trim().toLowerCase();
    for (final account in accounts) {
      if (account.email == normalized) return account;
    }
    return null;
  }

  /// The account with [id], if any.
  DemoAccount? accountById(String id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  /// The order with [id] (or number), if any.
  DemoOrder? orderById(String id) {
    for (final order in orders) {
      if (order.id == id || order.number == id) return order;
    }
    return null;
  }

  /// The file with [id], if any.
  DemoStoredFile? fileById(String id) {
    for (final file in files) {
      if (file.id == id) return file;
    }
    return null;
  }

  /// Stores an uploaded file.
  DemoStoredFile addFile({
    required String name,
    required String contentType,
    required Uint8List bytes,
    required String uploadedBy,
    required DateTime at,
  }) {
    _fileSequence++;
    final file = DemoStoredFile(
      id: 'file_upload_$_fileSequence',
      name: name,
      contentType: contentType,
      uploadedAt: at,
      uploadedBy: uploadedBy,
      content: () => bytes,
    );
    files.insert(0, file);
    return file;
  }

  /// Appends an audit event (newest first, at most 100 entries kept).
  void record(String actor, String action, String summary, DateTime at) {
    _eventSequence++;
    auditLog.insert(
      0,
      DemoAuditEvent(
        id: 'evt_live_$_eventSequence',
        at: at,
        actor: actor,
        action: action,
        summary: summary,
      ),
    );
    if (auditLog.length > 100) auditLog.removeLast();
  }

  static List<DemoAccount> _seedAccounts() => <DemoAccount>[
        DemoAccount(
          id: 'usr_admin',
          email: 'admin@example.com',
          password: demoPassword,
          givenName: 'Alice',
          familyName: 'Admin',
          roles: <String>{'admin'},
          permissions: <String>{...demoAllPermissions},
          department: 'Operations',
          createdAt: DateTime.utc(2024, 3, 4),
        ),
        DemoAccount(
          id: 'usr_staff',
          email: 'staff@example.com',
          password: demoPassword,
          givenName: 'Sam',
          familyName: 'Staff',
          roles: <String>{'staff'},
          permissions: <String>{'orders.read'},
          department: 'Customer service',
          createdAt: DateTime.utc(2025, 1, 13),
        ),
        DemoAccount(
          id: 'usr_viewer',
          email: 'viewer@example.com',
          password: demoPassword,
          givenName: 'Victor',
          familyName: 'Viewer',
          roles: <String>{'viewer'},
          permissions: <String>{},
          department: 'Marketing',
          createdAt: DateTime.utc(2025, 6, 2),
        ),
        DemoAccount(
          id: 'usr_unverified',
          email: 'unverified@example.com',
          password: demoPassword,
          givenName: 'Uma',
          familyName: 'Unverified',
          roles: <String>{'viewer'},
          permissions: <String>{},
          department: 'Sales',
          createdAt: DateTime.utc(2026, 10, 1),
          emailVerified: false,
        ),
      ];

  static const List<DemoProduct> _products = <DemoProduct>[
    DemoProduct('SKU-AUR-01', 'Aurora Desk Lamp', 4900),
    DemoProduct('SKU-NIM-02', 'Nimbus Wireless Mouse', 2900),
    DemoProduct('SKU-ORB-03', 'Orbit Mechanical Keyboard', 12900),
    DemoProduct('SKU-PUL-04', 'Pulse Noise-Cancelling Headphones', 19900),
    DemoProduct('SKU-TER-05', 'Terra Standing Desk', 54900),
    DemoProduct('SKU-LUM-06', 'Lumen 27" Monitor', 32900),
    DemoProduct('SKU-ZEN-07', 'Zen Ergonomic Chair', 39900),
    DemoProduct('SKU-VOL-08', 'Volt USB-C Hub', 5900),
  ];

  static const List<String> _customers = <String>[
    'Olivia Martin',
    'Noah Bennett',
    'Emma Clarke',
    'Liam Turner',
    'Sophia Patel',
    'Mason Rivera',
    'Ava Nguyen',
    'Lucas Fischer',
  ];

  static const List<String> _cities = <String>[
    '12 Harbour Street, Bristol',
    '8 Rue des Lilas, Lyon',
    '221 Market Avenue, Austin',
    '4 Canal Road, Amsterdam',
    '77 King Street, Toronto',
    '19 Garden Lane, Dublin',
  ];

  static const List<String> _statuses = <String>[
    'pending',
    'pending',
    'processing',
    'pending',
    'processing',
    'shipped',
    'processing',
    'shipped',
    'delivered',
    'shipped',
    'cancelled',
    'delivered',
    'delivered',
    'shipped',
    'delivered',
    'delivered',
    'cancelled',
    'delivered',
  ];

  static List<DemoOrder> _seedOrders() {
    return <DemoOrder>[
      for (var i = 0; i < _statuses.length; i++)
        DemoOrder(
          id: 'ord_${1018 - i}',
          number: 'SO-${1018 - i}',
          customerName: _customers[(i * 3) % _customers.length],
          customerEmail: '${_customers[(i * 3) % _customers.length]}'
                  '@example.org'
              .toLowerCase()
              .replaceAll(' ', '.'),
          status: _statuses[i],
          placedAt: seedDate.subtract(Duration(hours: i * 37, minutes: i * 13)),
          lines: <DemoOrderLine>[
            for (var k = 0; k <= i % 3; k++)
              DemoOrderLine(
                _products[(i * 5 + k * 3) % _products.length],
                1 + (i + k) % 3,
              ),
          ],
          address: _cities[i % _cities.length],
          note:
              i % 4 == 1 ? 'Please leave the parcel at the front desk.' : null,
        ),
    ];
  }

  static List<DemoStoredFile> _seedFiles(List<DemoOrder> orders) {
    final at = DateTime.utc(2026, 10, 12, 9, 30);
    return <DemoStoredFile>[
      DemoStoredFile(
        id: 'file_orders_csv',
        name: 'orders-export.csv',
        contentType: 'text/csv',
        uploadedAt: at,
        uploadedBy: 'System',
        content: () => ordersCsv(orders),
      ),
      DemoStoredFile(
        id: 'file_catalog',
        name: 'product-catalog.json',
        contentType: 'application/json',
        uploadedAt: at.subtract(const Duration(days: 3)),
        uploadedBy: 'Alice Admin',
        content: _catalogJson,
      ),
      DemoStoredFile(
        id: 'file_brochure',
        name: 'brochure-2026.pdf',
        contentType: 'application/pdf',
        uploadedAt: at.subtract(const Duration(days: 9)),
        uploadedBy: 'Alice Admin',
        content: _brochurePdf,
      ),
    ];
  }

  /// A CSV export of [orders].
  static Uint8List ordersCsv(List<DemoOrder> orders) {
    final buffer = StringBuffer('number,customer,status,items,total_usd\n');
    for (final order in orders) {
      buffer.writeln(
        '${order.number},"${order.customerName}",${order.status},'
        '${order.itemCount},${(order.totalInCents / 100).toStringAsFixed(2)}',
      );
    }
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  static Uint8List _catalogJson() {
    final entries = <Object?>[
      for (var i = 0; i < 1200; i++)
        <String, Object?>{
          'sku': '${_products[i % _products.length].sku}-V${i ~/ 8}',
          'name': '${_products[i % _products.length].name} '
              '(variant ${i ~/ 8 + 1})',
          'price': _products[i % _products.length].priceInCents / 100,
          'stock': (i * 37) % 120,
        },
    ];
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(entries)),
    );
  }

  static Uint8List _brochurePdf() {
    const length = 1536 * 1024;
    final bytes = Uint8List(length);
    final header = ascii.encode('%PDF-1.4\n% Symphony demo brochure\n');
    bytes.setAll(0, header);
    for (var i = header.length; i < length; i++) {
      bytes[i] = (i * 31 + 7) & 0xff;
    }
    return bytes;
  }

  static List<DemoAuditEvent> _seedAudit() => <DemoAuditEvent>[
        DemoAuditEvent(
          id: 'evt_seed_3',
          at: DateTime.utc(2026, 10, 30, 10, 2),
          actor: 'staff@example.com',
          action: 'orders.view',
          summary: 'Viewed order SO-1015',
        ),
        DemoAuditEvent(
          id: 'evt_seed_2',
          at: DateTime.utc(2026, 10, 29, 8, 15),
          actor: 'admin@example.com',
          action: 'users.update',
          summary: 'Granted orders.read to Sam Staff',
        ),
        DemoAuditEvent(
          id: 'evt_seed_1',
          at: DateTime.utc(2026, 10, 29, 8, 12),
          actor: 'admin@example.com',
          action: 'auth.login',
          summary: 'Signed in',
        ),
      ];
}
