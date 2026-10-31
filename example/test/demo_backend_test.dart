import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony_core/symphony_core.dart';
import 'package:symphony_core_example/core/backend/demo_backend.dart';
import 'package:symphony_core_example/core/backend/demo_database.dart';
import 'package:symphony_core_example/core/backend/demo_multipart.dart';
import 'package:symphony_core_example/features/files/domain/file_entities.dart';
import 'package:symphony_core_example/features/files/presentation/files_providers.dart';
import 'package:symphony_core_example/features/orders/domain/entities/order.dart';
import 'package:symphony_core_example/features/orders/domain/order_filter.dart';
import 'package:symphony_core_example/features/orders/presentation/providers/orders_providers.dart';
import 'package:symphony_core_example/features/reports/presentation/reports_providers.dart';
import 'package:symphony_core_example/features/settings/presentation/settings_providers.dart';

import 'support/example_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DemoBackend backend;
  late SymphonyCore core;

  setUp(() {
    backend = createTestBackend();
    core = createTestCore(backend);
  });

  tearDown(() => core.dispose());

  Future<void> signIn(String email, {String password = demoPassword}) async {
    final result = await core.auth.login(
      AuthCredentials.emailPassword(email: email, password: password),
    );
    expect(result.isSuccess, isTrue, reason: '${result.failureOrNull}');
  }

  group('authentication', () {
    test('wrong credentials surface the server message', () async {
      final result = await core.auth.login(
        AuthCredentials.emailPassword(
          email: 'admin@example.com',
          password: 'not-the-password',
        ),
      );

      final failure = result.failureOrNull;
      expect(failure, isA<AuthFailure>());
      expect(failure!.message, 'The e-mail or password is incorrect.');
      expect(failure.code, 'invalid_credentials');
      expect(core.read(isAuthenticatedProvider), isFalse);
    });

    test('the sessionValidator rejects unverified accounts', () async {
      final result = await core.auth.login(
        AuthCredentials.emailPassword(
          email: 'unverified@example.com',
          password: demoPassword,
        ),
      );

      expect(result.failureOrNull?.code, 'email_not_verified');
      expect(core.read(isAuthenticatedProvider), isFalse);
    });

    test('registration signs the new user in with the viewer role', () async {
      final result = await core.auth.register(
        const AuthCredentials(<String, Object?>{
          'name': 'Nora New',
          'email': 'nora@example.com',
          'password': 'correct-horse',
        }),
      );

      expect(result.isSuccess, isTrue, reason: '${result.failureOrNull}');
      final user = core.read(currentUserProvider)!;
      expect(user.displayName, 'Nora New');
      expect(user.roles, <String>{'viewer'});
      expect(user.permissions, isEmpty);
    });

    test('registering an existing e-mail returns field errors', () async {
      final result = await core.auth.register(
        const AuthCredentials(<String, Object?>{
          'name': 'Alice Again',
          'email': 'admin@example.com',
          'password': 'correct-horse',
        }),
      );

      final failure = result.failureOrNull;
      expect(failure, isA<ValidationFailure>());
      expect(
        (failure! as ValidationFailure).errorFor('email'),
        'An account with this e-mail already exists.',
      );
    });

    test('password recovery: request, confirm with the code, sign in',
        () async {
      final request = await core.auth.requestPasswordReset(
        const AuthCredentials(<String, Object?>{'email': 'staff@example.com'}),
      );
      expect(request.isSuccess, isTrue);

      final wrongCode = await core.auth.confirmPasswordReset(
        const AuthCredentials(<String, Object?>{
          'email': 'staff@example.com',
          'code': '000000',
          'password': 'brand-new-pass',
        }),
      );
      expect(wrongCode.failureOrNull, isA<ValidationFailure>());

      final confirm = await core.auth.confirmPasswordReset(
        const AuthCredentials(<String, Object?>{
          'email': 'staff@example.com',
          'code': demoResetCode,
          'password': 'brand-new-pass',
        }),
      );
      expect(confirm.isSuccess, isTrue, reason: '${confirm.failureOrNull}');

      await signIn('staff@example.com', password: 'brand-new-pass');
    });

    test('sign-out revokes the refresh token on the backend', () async {
      await signIn('viewer@example.com');

      await core.auth.logout();

      expect(core.read(isAuthenticatedProvider), isFalse);
      expect(
        backend.requestLog.map((r) => '${r.method} ${r.path} ${r.statusCode}'),
        contains('POST /auth/logout 204'),
      );
    });
  });

  group('authorization', () {
    test('the backend enforces permissions too (403 → ForbiddenFailure)',
        () async {
      await signIn('staff@example.com');

      final report = await core.read(reportsRepositoryProvider).fetchSummary();

      expect(report.failureOrNull, isA<ForbiddenFailure>());
      expect(backend.requestLog.last.statusCode, 403);
    });

    test('requests without a session are rejected (401)', () async {
      final result = await core.read(ordersRepositoryProvider).fetchOrders();

      expect(result.failureOrNull, isA<UnauthorizedFailure>());
    });
  });

  group('data', () {
    test('orders are filtered by status and decoded into entities', () async {
      await signIn('staff@example.com');

      final result = await core.read(ordersRepositoryProvider).fetchOrders(
            filter: const OrderFilter(status: OrderStatus.pending),
          );

      final orders = result.valueOrNull!;
      expect(orders, hasLength(3));
      expect(orders.every((o) => o.status == OrderStatus.pending), isTrue);
      expect(orders.first.number, 'SO-1018');
      expect(orders.first.total.currency, 'USD');
    });

    test('an unknown order is a NotFoundFailure', () async {
      await signIn('staff@example.com');

      final result =
          await core.read(ordersRepositoryProvider).fetchOrder('ord_42');

      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('the sales report is consistent with the orders', () async {
      await signIn('admin@example.com');

      final report = (await core.read(reportsRepositoryProvider).fetchSummary())
          .valueOrNull!;

      expect(report.orderCount, 18);
      expect(report.pendingOrders, 3);
      expect(report.weeklyRevenue, hasLength(4));
      expect(report.topProducts, isNotEmpty);
      final export = (await core.read(reportsRepositoryProvider).exportOrders())
          .valueOrNull!;
      expect(export.rowCount, 18);
      expect(export.filename, 'orders-report.csv');
    });
  });

  group('files', () {
    test('multipart upload and download round trip, with progress', () async {
      await signIn('viewer@example.com');
      final files = SampleFiles.generate(count: 2, sizeInBytes: 4096);
      final sent = <int>[];

      final upload = await core.read(filesRepositoryProvider).upload(
            files,
            note: 'Quarterly numbers',
            onProgress: (transferred, total) => sent.add(transferred),
          );

      final stored = upload.valueOrNull!;
      expect(stored.map((file) => file.name), <String>[
        'sample-1.txt',
        'sample-2.txt',
      ]);
      expect(stored.first.sizeInBytes, 4096);
      expect(sent, isNotEmpty);
      expect(sent.last, greaterThan(2 * 4096));

      final received = <int>[];
      final download = await core.read(filesRepositoryProvider).download(
            stored.first,
            onProgress: (transferred, total) => received.add(transferred),
          );
      expect(download.valueOrNull, files.first.bytes);
      expect(received.last, 4096);
      expect(
        backend.database.auditLog.first.summary,
        'Uploaded 2 file(s) — "Quarterly numbers"',
      );
    });

    test('the transfer controller records completed transfers', () async {
      await signIn('viewer@example.com');
      final controller = core.read(fileTransferControllerProvider.notifier);

      await controller.uploadSamples(count: 1, sizeInBytes: 1024);

      expect(
        core.read(fileTransferControllerProvider),
        isA<TransferSucceeded>(),
      );
      final history = await core.read(transferHistoryProvider).watch().first;
      expect(history.single.fileName, 'sample-1.txt');
      expect(history.single.direction, TransferDirection.upload);
    });
  });

  group('environments', () {
    test('updateBaseUrl switches hosts at runtime', () async {
      final status = core.read(serverStatusRepositoryProvider);
      expect((await status.check()).valueOrNull?.environment, 'production');

      core.apiClient.updateBaseUrl('https://staging.api.example.com');
      final staging = (await status.check()).valueOrNull!;

      expect(staging.host, 'staging.api.example.com');
      expect(staging.environment, 'staging');
    });

    test('a simulated outage becomes a NetworkFailure', () async {
      backend.offline = true;

      final result = await core.read(serverStatusRepositoryProvider).check();

      expect(result.failureOrNull, isA<NetworkFailure>());
    });
  });

  group('multipart parser', () {
    test('splits fields and files', () {
      const boundary = '--dio-boundary-123';
      final body = Uint8List.fromList(
        utf8.encode(
          '--$boundary\r\n'
          'content-disposition: form-data; name="note"\r\n\r\n'
          'hello\r\n'
          '--$boundary\r\n'
          'content-disposition: form-data; name="files"; '
          'filename="a;b.txt"\r\n'
          'content-type: text/plain\r\n\r\n'
          'line 1\r\nline 2\r\n'
          '--$boundary--\r\n',
        ),
      );

      final parts = parseMultipart(body, boundary);

      expect(parts, hasLength(2));
      expect(parts.first.name, 'note');
      expect(parts.first.isFile, isFalse);
      expect(parts.first.text, 'hello');
      expect(parts.last.filename, 'a;b.txt');
      expect(parts.last.contentType, 'text/plain');
      expect(parts.last.text, 'line 1\r\nline 2');
      expect(
        multipartBoundary('multipart/form-data; boundary="$boundary"'),
        boundary,
      );
    });
  });
}
