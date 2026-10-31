import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:symphony_core/symphony_core.dart';

import 'demo_database.dart';
import 'demo_http.dart';
import 'demo_tokens.dart';

/// Signature of a route handler of the demo backend.
typedef DemoHandler = FutureOr<DemoResponse> Function(DemoRequest request);

/// A deterministic, in-process HTTP backend for the example application.
///
/// It is a Dio [HttpClientAdapter]: installed with
/// `httpClientAdapterProvider.overrideWithValue(DemoBackend())`, it answers
/// every request of the package's `ApiClient` without any network, while
/// the whole client pipeline (interceptors, token refresh, retries, API
/// inspector, logging, error mapping) runs for real.
///
/// The backend accepts any host, so `ApiClient.updateBaseUrl` can switch
/// between "environments" at runtime. It validates bearer tokens and
/// permissions like a real server: access tokens live [accessTokenLifetime]
/// (30 seconds by default) and expired ones are rejected with `401`, which
/// makes the client's transparent refresh + retry visible in the inspector.
///
/// Endpoints (JSON bodies use the envelope
/// `{"status": "ok" | "error", "result" | "error": ...}`):
///
/// | Method | Path                        | Access                |
/// |--------|-----------------------------|-----------------------|
/// | GET    | /status                     | public                |
/// | POST   | /auth/login                 | public                |
/// | POST   | /auth/token/refresh         | refresh token         |
/// | POST   | /auth/logout                | bearer (may be expired) |
/// | GET    | /auth/me                    | bearer                |
/// | POST   | /auth/register              | public                |
/// | POST   | /auth/password/forgot       | public                |
/// | POST   | /auth/password/reset        | public                |
/// | GET    | /orders, /orders/{id}       | `orders.read`         |
/// | GET    | /reports/summary            | `reports.view`        |
/// | GET    | /reports/export             | `reports.export`      |
/// | GET    | /admin/users, /admin/audit-log | role `admin`       |
/// | GET    | /files                      | bearer                |
/// | POST   | /files (multipart)          | bearer                |
/// | GET    | /files/{id}/content         | bearer                |
class DemoBackend implements HttpClientAdapter {
  /// Creates a backend.
  ///
  /// * [latency] is added to every response.
  /// * [uploadBytesPerSecond] / [downloadBytesPerSecond] simulate the
  ///   bandwidth of request and download bodies so that progress callbacks
  ///   are visible; `null` transfers instantly (tests).
  /// * [clock] drives token expiry (tests use a fake clock).
  DemoBackend({
    this.latency = const Duration(milliseconds: 350),
    this.accessTokenLifetime = const Duration(seconds: 30),
    this.refreshTokenLifetime = const Duration(days: 7),
    this.uploadBytesPerSecond = 768 * 1024,
    this.downloadBytesPerSecond = 2 * 1024 * 1024,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       database = DemoDatabase() {
    _tokens = DemoTokenService(
      clock: _clock,
      accessTokenLifetime: accessTokenLifetime,
      refreshTokenLifetime: refreshTokenLifetime,
    );
    _routes = <_DemoRoute>[
      _DemoRoute('GET', '/status', _status),
      _DemoRoute('POST', '/auth/login', _login),
      _DemoRoute('POST', '/auth/token/refresh', _refresh),
      _DemoRoute('POST', '/auth/logout', _logout),
      _DemoRoute('GET', '/auth/me', _me),
      _DemoRoute('POST', '/auth/register', _register),
      _DemoRoute('POST', '/auth/password/forgot', _forgotPassword),
      _DemoRoute('POST', '/auth/password/reset', _resetPassword),
      _DemoRoute('GET', '/orders', _orders),
      _DemoRoute('GET', '/orders/:id', _order),
      _DemoRoute('GET', '/reports/summary', _reportSummary),
      _DemoRoute('GET', '/reports/export', _reportExport),
      _DemoRoute('GET', '/admin/users', _adminUsers),
      _DemoRoute('GET', '/admin/audit-log', _auditLog),
      _DemoRoute('GET', '/files', _files),
      _DemoRoute('POST', '/files', _upload),
      _DemoRoute('GET', '/files/:id/content', _download),
    ];
  }

  /// Delay added to every response.
  Duration latency;

  /// Simulated upload bandwidth (`null`: instant).
  final int? uploadBytesPerSecond;

  /// Simulated download bandwidth (`null`: instant).
  final int? downloadBytesPerSecond;

  /// Lifetime of access tokens.
  final Duration accessTokenLifetime;

  /// Lifetime of refresh tokens.
  final Duration refreshTokenLifetime;

  /// When `true`, every request fails with a connection error, as if the
  /// device were offline.
  bool offline = false;

  /// The data set served by this backend.
  final DemoDatabase database;

  final DateTime Function() _clock;
  late final DemoTokenService _tokens;
  late final List<_DemoRoute> _routes;
  final List<DemoRequestRecord> _requestLog = <DemoRequestRecord>[];

  /// The requests handled so far, oldest first (at most 200).
  List<DemoRequestRecord> get requestLog =>
      List<DemoRequestRecord>.unmodifiable(_requestLog);

  /// Expires every access token issued so far: the next authenticated call
  /// receives a `401` and the client refreshes the session transparently.
  void expireAccessTokens() {
    _tokens.expireAccessTokens();
    database.record('system', 'auth.expire', 'Access tokens expired', _now());
  }

  /// Revokes every refresh token issued so far: the next refresh fails and
  /// the client signs the user out ("session expired").
  void revokeSessions() {
    _tokens.revokeRefreshTokens();
    database.record('system', 'auth.revoke', 'All sessions revoked', _now());
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    var cancelled = false;
    unawaited(cancelFuture?.then((_) => cancelled = true));

    final body = await _receiveBody(requestStream);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (cancelled) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        message: 'The request was cancelled.',
      );
    }
    final request = DemoRequest.fromOptions(options, body);
    if (offline) {
      _log(request, 0, 'offline');
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'Simulated network outage: the demo backend is offline.',
      );
    }

    final DemoResponse response;
    String? errorCode;
    try {
      response = await _dispatch(request);
    } on DemoHttpException catch (error) {
      errorCode = error.code;
      return _toResponseBody(request, error.toResponse(), errorCode);
    }
    return _toResponseBody(request, response, errorCode);
  }

  @override
  void close({bool force = false}) {}

  DateTime _now() => _clock().toUtc();

  Future<DemoResponse> _dispatch(DemoRequest request) async {
    final segments = _segments(request.path);
    var pathMatched = false;
    for (final route in _routes) {
      final parameters = route.match(segments);
      if (parameters == null) continue;
      pathMatched = true;
      if (route.method != request.method) continue;
      request.pathParameters = parameters;
      return route.handler(request);
    }
    if (pathMatched) {
      throw DemoHttpException(
        405,
        'method_not_allowed',
        '${request.method} is not supported on ${request.path}.',
      );
    }
    throw DemoHttpException.notFound('No route for ${request.path}.');
  }

  /// Reads the request body, simulating the upload bandwidth chunk by chunk
  /// (Dio reports send progress as the adapter consumes the stream).
  Future<Uint8List> _receiveBody(Stream<Uint8List>? stream) async {
    if (stream == null) return Uint8List(0);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
      final delay = _transferTime(chunk.length, uploadBytesPerSecond);
      if (delay != null) await Future<void>.delayed(delay);
    }
    return builder.takeBytes();
  }

  ResponseBody _toResponseBody(
    DemoRequest request,
    DemoResponse response,
    String? errorCode,
  ) {
    _log(request, response.statusCode, errorCode);
    final headers = <String, List<String>>{
      'content-length': <String>['${response.body.length}'],
      'x-served-by': <String>[request.host],
      'x-request-id': <String>['req-${_requestLog.length}'],
      for (final entry in response.headers.entries)
        entry.key: <String>[entry.value],
    };
    final contentType = response.contentType;
    if (contentType != null) headers['content-type'] = <String>[contentType];
    final stream =
        response.simulateTransfer
            ? _chunked(response.body)
            : Stream<Uint8List>.value(response.body);
    return ResponseBody(
      stream,
      response.statusCode,
      statusMessage: _reasonPhrase(response.statusCode),
      headers: headers,
    );
  }

  Stream<Uint8List> _chunked(Uint8List bytes) async* {
    const chunkSize = 64 * 1024;
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = math.min(offset + chunkSize, bytes.length);
      final delay = _transferTime(end - offset, downloadBytesPerSecond);
      if (delay != null) await Future<void>.delayed(delay);
      yield Uint8List.sublistView(bytes, offset, end);
    }
  }

  static Duration? _transferTime(int bytes, int? bytesPerSecond) {
    if (bytesPerSecond == null || bytesPerSecond <= 0) return null;
    final micros = bytes * Duration.microsecondsPerSecond ~/ bytesPerSecond;
    // Tiny chunks (JSON bodies, multipart headers) are not worth a timer.
    return micros < 2000 ? null : Duration(microseconds: micros);
  }

  void _log(DemoRequest request, int statusCode, String? errorCode) {
    _requestLog.add(
      DemoRequestRecord(
        method: request.method,
        path: request.path,
        statusCode: statusCode,
        errorCode: errorCode,
        at: _now(),
      ),
    );
    if (_requestLog.length > 200) _requestLog.removeAt(0);
  }

  // ---------------------------------------------------------------------
  // Authentication helpers
  // ---------------------------------------------------------------------

  DemoAccount _authenticate(DemoRequest request, {bool allowExpired = false}) {
    final header = request.header('authorization');
    if (header == null || !header.toLowerCase().startsWith('bearer ')) {
      throw const DemoHttpException.unauthorized(
        'missing_token',
        'Authentication required.',
      );
    }
    final claims = _tokens.verifyAccessToken(
      header.substring(7).trim(),
      allowExpired: allowExpired,
    );
    final account = database.accountById(claims.subject);
    if (account == null) {
      throw const DemoHttpException.unauthorized(
        'unknown_account',
        'This account no longer exists.',
      );
    }
    return account;
  }

  DemoAccount _authorize(DemoRequest request, String permission) {
    final account = _authenticate(request);
    if (!account.permissions.contains(permission)) {
      throw DemoHttpException.forbidden(
        'The permission "$permission" is required.',
      );
    }
    return account;
  }

  DemoAccount _requireAdmin(DemoRequest request) {
    final account = _authenticate(request);
    if (!account.roles.contains('admin')) {
      throw const DemoHttpException.forbidden(
        'This area is reserved for administrators.',
      );
    }
    return account;
  }

  /// Sign-in / refresh payload: credentials plus (optionally) the account.
  Map<String, Object?> _credentials(DemoAccount account) => <String, Object?>{
    'jwt': _tokens.issueAccessToken(account.id),
    'renewal_token': _tokens.issueRefreshToken(account.id),
    'kind': 'Bearer',
    'ttl': accessTokenLifetime.inSeconds,
  };

  // ---------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------

  DemoResponse _status(DemoRequest request) {
    final host = request.uri.host;
    return DemoResponse.ok(<String, Object?>{
      'service': 'symphony-demo-backend',
      'version': '1.4.2',
      'host': request.host,
      'environment':
          host.startsWith('staging')
              ? 'staging'
              : host == 'localhost' ||
                  host.startsWith('10.') ||
                  host == '127.0.0.1'
              ? 'local'
              : 'production',
      'server_time': _now().toIso8601String(),
    });
  }

  DemoResponse _login(DemoRequest request) {
    final login = request.field('login');
    final secret = request.field('secret');
    if (login == null || secret == null) {
      throw DemoHttpException.validation(
        'Please fill in every field.',
        <String, List<String>>{
          if (login == null) 'email': <String>['The e-mail is required.'],
          if (secret == null) 'password': <String>['The password is required.'],
        },
      );
    }
    final account = database.accountByEmail(login);
    if (account == null || account.password != secret) {
      database.record(login, 'auth.login_failed', 'Failed sign-in', _now());
      throw const DemoHttpException.unauthorized(
        'invalid_credentials',
        'The e-mail or password is incorrect.',
      );
    }
    account.lastLoginAt = _now();
    database.record(account.email, 'auth.login', 'Signed in', _now());
    return DemoResponse.ok(<String, Object?>{
      'credentials': _credentials(account),
      'account': account.toAccountJson(),
    });
  }

  DemoResponse _refresh(DemoRequest request) {
    final token = request.field('renewal_token');
    if (token == null) {
      throw const DemoHttpException.unauthorized(
        'invalid_refresh_token',
        'A renewal token is required.',
      );
    }
    final claims = _tokens.verifyRefreshToken(token);
    final account = database.accountById(claims.subject);
    if (account == null) {
      throw const DemoHttpException.unauthorized(
        'unknown_account',
        'This account no longer exists.',
      );
    }
    // Refresh tokens rotate: the presented one cannot be used again.
    _tokens.revoke(claims);
    database.record(account.email, 'auth.refresh', 'Token refreshed', _now());
    return DemoResponse.ok(<String, Object?>{
      'credentials': _credentials(account),
    });
  }

  DemoResponse _logout(DemoRequest request) {
    final account = _authenticate(request, allowExpired: true);
    final token = request.field('renewal_token');
    if (token != null) {
      try {
        _tokens.revoke(_tokens.verifyRefreshToken(token));
      } on DemoHttpException {
        // Already unusable: nothing to revoke.
      }
    }
    database.record(account.email, 'auth.logout', 'Signed out', _now());
    return DemoResponse.noContent();
  }

  DemoResponse _me(DemoRequest request) {
    final account = _authenticate(request);
    return DemoResponse.ok(<String, Object?>{
      'account': account.toAccountJson(),
    });
  }

  DemoResponse _register(DemoRequest request) {
    final name = request.field('full_name');
    final email = request.field('email')?.toLowerCase();
    final password = request.json['password'];
    final errors = <String, List<String>>{
      if (name == null) 'name': <String>['Please tell us your name.'],
      if (email == null || !email.contains('@'))
        'email': <String>['A valid e-mail address is required.']
      else if (database.accountByEmail(email) != null)
        'email': <String>['An account with this e-mail already exists.'],
      if (password is! String || password.length < 8)
        'password': <String>['Use at least 8 characters.'],
    };
    if (errors.isNotEmpty || name == null || email == null) {
      throw DemoHttpException.validation(
        'Please correct the highlighted fields.',
        errors,
      );
    }
    final parts = name.split(RegExp(r'\s+'));
    final account = DemoAccount(
      id: 'usr_${database.accounts.length + 1}',
      email: email,
      password: '$password',
      givenName: parts.first,
      familyName: parts.skip(1).join(' '),
      roles: <String>{'viewer'},
      permissions: <String>{},
      department: 'New members',
      createdAt: _now(),
    )..lastLoginAt = _now();
    database.accounts.add(account);
    database.record(email, 'auth.register', 'Created an account', _now());
    return DemoResponse.ok(<String, Object?>{
      'credentials': _credentials(account),
      'account': account.toAccountJson(),
    }, statusCode: 201);
  }

  DemoResponse _forgotPassword(DemoRequest request) {
    final email = request.field('email');
    if (email == null) {
      throw const DemoHttpException.validation(
        'The e-mail is required.',
        <String, List<String>>{
          'email': <String>['The e-mail is required.'],
        },
      );
    }
    final account = database.accountByEmail(email);
    if (account != null) {
      database.record(
        account.email,
        'auth.password_reset_requested',
        'Requested a password reset (code $demoResetCode)',
        _now(),
      );
    }
    // Same answer whether the account exists or not (no user enumeration).
    return DemoResponse.ok(<String, Object?>{
      'message': 'If the account exists, a code was sent.',
    }, statusCode: 202);
  }

  DemoResponse _resetPassword(DemoRequest request) {
    final email = request.field('email');
    final code = request.field('code');
    final password = request.json['new_password'];
    final account = email == null ? null : database.accountByEmail(email);
    if (account == null || code != demoResetCode) {
      throw const DemoHttpException.validation(
        'The verification code is invalid.',
        <String, List<String>>{
          'code': <String>[
            'Invalid code. In this demo the code is '
                '$demoResetCode.',
          ],
        },
      );
    }
    if (password is! String || password.length < 8) {
      throw const DemoHttpException.validation(
        'The new password is too short.',
        <String, List<String>>{
          'password': <String>['Use at least 8 characters.'],
        },
      );
    }
    account.password = password;
    database.record(
      account.email,
      'auth.password_reset',
      'Reset the password',
      _now(),
    );
    return DemoResponse.ok(const <String, Object?>{
      'message': 'Password updated.',
    });
  }

  DemoResponse _orders(DemoRequest request) {
    _authorize(request, 'orders.read');
    final status = request.query('status');
    final search = request.query('q')?.trim().toLowerCase() ?? '';
    final items =
        database.orders.where((order) {
          if (status != null && status.isNotEmpty && order.status != status) {
            return false;
          }
          if (search.isEmpty) return true;
          return order.number.toLowerCase().contains(search) ||
              order.customerName.toLowerCase().contains(search);
        }).toList();
    return DemoResponse.ok(<String, Object?>{
      'items': <Object?>[for (final order in items) order.toSummaryJson()],
      'total': items.length,
    });
  }

  DemoResponse _order(DemoRequest request) {
    _authorize(request, 'orders.read');
    final id = request.pathParameters['id'] ?? '';
    final order = database.orderById(id);
    if (order == null) {
      throw DemoHttpException.notFound('Order "$id" does not exist.');
    }
    return DemoResponse.ok(<String, Object?>{'order': order.toDetailJson()});
  }

  DemoResponse _reportSummary(DemoRequest request) {
    _authorize(request, 'reports.view');
    final orders = database.orders;
    final billable =
        orders.where((order) => order.status != 'cancelled').toList();
    final revenue = billable.fold<int>(
      0,
      (sum, order) => sum + order.totalInCents,
    );

    final byStatus = <String, int>{};
    for (final order in orders) {
      byStatus[order.status] = (byStatus[order.status] ?? 0) + 1;
    }

    final weekStart = DemoDatabase.seedDate.subtract(const Duration(days: 6));
    final weekly = <Object?>[];
    for (var week = 3; week >= 0; week--) {
      final from = weekStart.subtract(Duration(days: 7 * week));
      final to = from.add(const Duration(days: 7));
      final amount = billable
          .where((o) => !o.placedAt.isBefore(from) && o.placedAt.isBefore(to))
          .fold<int>(0, (sum, order) => sum + order.totalInCents);
      weekly.add(<String, Object?>{
        'week_start': from.toIso8601String(),
        'amount': amount,
      });
    }

    final quantities = <String, int>{};
    final revenues = <String, int>{};
    final names = <String, String>{};
    for (final order in billable) {
      for (final line in order.lines) {
        final sku = line.product.sku;
        names[sku] = line.product.name;
        quantities[sku] = (quantities[sku] ?? 0) + line.quantity;
        revenues[sku] = (revenues[sku] ?? 0) + line.totalInCents;
      }
    }
    final top =
        quantities.keys.toList()
          ..sort((a, b) => revenues[b]!.compareTo(revenues[a]!));

    return DemoResponse.ok(<String, Object?>{
      'currency': 'USD',
      'generated_at': _now().toIso8601String(),
      'kpis': <String, Object?>{
        'revenue': revenue,
        'orders': orders.length,
        'average_order_value':
            billable.isEmpty ? 0 : revenue ~/ billable.length,
        'pending_orders': byStatus['pending'] ?? 0,
      },
      'weekly_revenue': weekly,
      'status_breakdown': byStatus,
      'top_products': <Object?>[
        for (final sku in top.take(5))
          <String, Object?>{
            'sku': sku,
            'name': names[sku],
            'quantity': quantities[sku],
            'revenue': revenues[sku],
          },
      ],
    });
  }

  DemoResponse _reportExport(DemoRequest request) {
    final account = _authorize(request, 'reports.export');
    database.record(account.email, 'reports.export', 'Exported orders', _now());
    return DemoResponse.file(
      DemoDatabase.ordersCsv(database.orders),
      contentType: 'text/csv',
      filename: 'orders-report.csv',
    );
  }

  DemoResponse _adminUsers(DemoRequest request) {
    _requireAdmin(request);
    return DemoResponse.ok(<String, Object?>{
      'items': <Object?>[
        for (final account in database.accounts) account.toAdminJson(),
      ],
    });
  }

  DemoResponse _auditLog(DemoRequest request) {
    _requireAdmin(request);
    return DemoResponse.ok(<String, Object?>{
      'items': <Object?>[for (final event in database.auditLog) event.toJson()],
    });
  }

  DemoResponse _files(DemoRequest request) {
    _authenticate(request);
    return DemoResponse.ok(<String, Object?>{
      'items': <Object?>[for (final file in database.files) file.toJson()],
    });
  }

  DemoResponse _upload(DemoRequest request) {
    final account = _authenticate(request);
    final parts = request.multipart.where((part) => part.isFile).toList();
    if (parts.isEmpty) {
      throw const DemoHttpException.badRequest(
        'Send at least one file as multipart/form-data.',
      );
    }
    final note =
        request.multipart
            .where((part) => !part.isFile && part.name == 'note')
            .map((part) => part.text)
            .join();
    final stored = <DemoStoredFile>[
      for (final part in parts)
        database.addFile(
          name: part.filename!,
          contentType: part.contentType ?? 'application/octet-stream',
          bytes: part.bytes,
          uploadedBy: account.fullName,
          at: _now(),
        ),
    ];
    database.record(
      account.email,
      'files.upload',
      'Uploaded ${stored.length} file(s)'
          '${note.isEmpty ? '' : ' — "$note"'}',
      _now(),
    );
    return DemoResponse.ok(<String, Object?>{
      'files': <Object?>[for (final file in stored) file.toJson()],
    }, statusCode: 201);
  }

  DemoResponse _download(DemoRequest request) {
    _authenticate(request);
    final id = request.pathParameters['id'] ?? '';
    final file = database.fileById(id);
    if (file == null) {
      throw DemoHttpException.notFound('File "$id" does not exist.');
    }
    return DemoResponse.file(
      file.bytes,
      contentType: file.contentType,
      filename: file.name,
    );
  }

  static List<String> _segments(String path) =>
      path.split('/').where((segment) => segment.isNotEmpty).toList();

  static String _reasonPhrase(int statusCode) => switch (statusCode) {
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    204 => 'No Content',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    422 => 'Unprocessable Entity',
    _ => 'Status $statusCode',
  };
}

class _DemoRoute {
  _DemoRoute(this.method, String pattern, this.handler)
    : _segments = DemoBackend._segments(pattern);

  final String method;
  final DemoHandler handler;
  final List<String> _segments;

  /// The path parameters when [segments] match this route, otherwise `null`.
  Map<String, String>? match(List<String> segments) {
    if (segments.length != _segments.length) return null;
    final parameters = <String, String>{};
    for (var i = 0; i < segments.length; i++) {
      final expected = _segments[i];
      if (expected.startsWith(':')) {
        parameters[expected.substring(1)] = Uri.decodeComponent(segments[i]);
      } else if (expected != segments[i]) {
        return null;
      }
    }
    return parameters;
  }
}
