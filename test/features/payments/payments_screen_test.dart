import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/cache_store.dart';
import 'package:pavio_tenant_app/core/razorpay_checkout.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';
import 'package:pavio_tenant_app/features/payments/payments_repository.dart';
import 'package:pavio_tenant_app/features/payments/payments_screen.dart';
import 'package:pavio_tenant_app/theme/pavio_theme.dart';

class _InMemorySecureStore implements SecureStore {
  final _values = <String, String>{};

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class _InMemoryCacheStore implements CacheStore {
  final _values = <String, String>{};

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class _FakeRazorpayCheckout implements RazorpayCheckout {
  CheckoutOrder? openedWith;
  bool succeed = true;
  String failureMessage = 'Payment cancelled';

  @override
  void open({
    required CheckoutOrder order,
    required String name,
    required String description,
    required void Function() onSuccess,
    required void Function(String message) onError,
  }) {
    openedWith = order;
    if (succeed) {
      onSuccess();
    } else {
      onError(failureMessage);
    }
  }

  @override
  void dispose() {}
}

http.Response _json(Map<String, dynamic> body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Widget _wrap(Widget child) =>
    MaterialApp(theme: PavioTheme.light(), home: child);

Future<AuthRepository> _connectedAuth() async {
  final store = _InMemorySecureStore();
  await store.write('pavio.access_token', 'access-token');
  await store.write('pavio.refresh_token', 'refresh-token');
  await store.write(
    'pavio.access_token_expires_at',
    DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
  );
  await store.write(
    'pavio.user',
    jsonEncode({
      'user_id': 'account-1',
      'name': 'Amit Kumar',
      'role': 'tenant',
      'connected': true,
      'org_id': 'org-1',
      'property_id': 'prop-1',
      'tenant_id': 'tenant-1',
    }),
  );
  return AuthRepository(sessionStore: SessionStore(storage: store));
}

const _invoiceJson = {
  'invoice_id': 'invoice-1',
  'amount': 150000,
  'currency': 'INR',
  'due_date': '2026-08-15',
  'status': 'pending',
};

const _emptyTransactions = {'transactions': []};

/// Routes a fake client's responses by path, since the screen now calls two GET
/// endpoints (invoices + transactions) instead of one.
http.Client _clientFor({
  Map<String, dynamic> invoices = const {'invoices': [], 'total_due': 0},
  Map<String, dynamic> transactions = _emptyTransactions,
  Map<String, dynamic>? orderResponse,
}) {
  return MockClient((request) async {
    if (request.method == 'POST') {
      return _json(orderResponse!, 201);
    }
    if (request.url.path.endsWith('/transactions')) {
      return _json(transactions, 200);
    }
    return _json(invoices, 200);
  });
}

void main() {
  testWidgets('shows nothing due and hides the Pay bar with nothing pending', (
    tester,
  ) async {
    final auth = await _connectedAuth();

    await tester.pumpWidget(
      _wrap(
        PaymentsScreen(
          authRepository: auth,
          paymentsRepository: PaymentsRepository(
            apiClient: ApiClient(httpClient: _clientFor()),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing to Pay'), findsOneWidget);
    expect(find.text('No recent activity'), findsOneWidget);
    // No CTA to pay ₹0 — the pinned Pay bar only exists when there's something to pay.
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets(
    'shows the gold rent-due hero, due date, and invoice count (1c mock)',
    (tester) async {
      final auth = await _connectedAuth();
      final client = _clientFor(
        invoices: {
          'invoices': [_invoiceJson],
          'total_due': 150000,
        },
      );

      await tester.pumpWidget(
        _wrap(
          PaymentsScreen(
            authRepository: auth,
            paymentsRepository: PaymentsRepository(
              apiClient: ApiClient(httpClient: client),
            ),
            cacheStore: _InMemoryCacheStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rent due'), findsOneWidget);
      expect(find.text('₹1,500'), findsOneWidget);
      // 2026-08-15 is a Saturday.
      expect(find.text('Saturday 15 August · 1 invoice'), findsOneWidget);
      expect(find.text('See the 1 invoice'), findsOneWidget);
      expect(find.text('Pay ₹1,500'), findsOneWidget);
    },
  );

  testWidgets('See the invoices reveals the pending invoice in a sheet', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = _clientFor(
      invoices: {
        'invoices': [_invoiceJson],
        'total_due': 150000,
      },
    );

    await tester.pumpWidget(
      _wrap(
        PaymentsScreen(
          authRepository: auth,
          paymentsRepository: PaymentsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Due 15 Aug 2026'), findsNothing);

    await tester.tap(find.text('See the 1 invoice'));
    await tester.pumpAndSettle();

    expect(find.text('Due 15 Aug 2026'), findsOneWidget);
    expect(find.text('Pay'), findsOneWidget);
  });

  testWidgets(
    'renders confirmed payments with their billing period and method, excludes pending charges',
    (tester) async {
      final auth = await _connectedAuth();
      final client = _clientFor(
        transactions: {
          'transactions': [
            {
              'transaction_id': 'invoice-1',
              'type': 'charge',
              'title': 'Scheduled Charges',
              'subtitle': null,
              'amount': 179700,
              'currency': 'INR',
              'date': '2026-10-01',
            },
            {
              'transaction_id': 'payment-1',
              'type': 'payment',
              'title': 'Rent · August',
              'subtitle': 'UPI',
              'amount': 330000,
              'currency': 'INR',
              'date': '2026-08-05',
            },
            {
              'transaction_id': 'payment-2',
              'type': 'payment',
              'title': 'Payment',
              'subtitle': null,
              'amount': 660000,
              'currency': 'INR',
              'date': '2026-03-01',
            },
          ],
        },
      );

      await tester.pumpWidget(
        _wrap(
          PaymentsScreen(
            authRepository: auth,
            paymentsRepository: PaymentsRepository(
              apiClient: ApiClient(httpClient: client),
            ),
            cacheStore: _InMemoryCacheStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The recent-payments section is paid history only — pending charges belong to the
      // hero/invoices sheet above, not here (1c's own separation of "due" from "paid").
      expect(find.text('Scheduled Charges'), findsNothing);
      expect(find.text('₹1,797'), findsNothing);

      expect(find.text('Rent · August'), findsOneWidget);
      expect(find.text('Paid 5 Aug 2026 · UPI'), findsOneWidget);
      expect(find.text('₹3,300'), findsOneWidget);

      expect(find.text('Payment'), findsOneWidget);
      expect(find.text('Paid 1 Mar 2026'), findsOneWidget);
      expect(find.text('₹6,600'), findsOneWidget);
    },
  );

  testWidgets(
    'paying creates an order and opens checkout with the right amount',
    (tester) async {
      final auth = await _connectedAuth();
      final client = _clientFor(
        invoices: {
          'invoices': [_invoiceJson],
          'total_due': 150000,
        },
        orderResponse: {
          'payment_id': 'payment-1',
          'invoice_id': 'invoice-1',
          'razorpay_order_id': 'order_123',
          'key_id': 'rzp_test_key',
        },
      );
      final checkout = _FakeRazorpayCheckout();

      await tester.pumpWidget(
        _wrap(
          PaymentsScreen(
            authRepository: auth,
            paymentsRepository: PaymentsRepository(
              apiClient: ApiClient(httpClient: client),
            ),
            cacheStore: _InMemoryCacheStore(),
            checkout: checkout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pay ₹1,500'));
      await tester.pumpAndSettle();

      expect(checkout.openedWith?.keyId, 'rzp_test_key');
      expect(checkout.openedWith?.razorpayOrderId, 'order_123');
      expect(checkout.openedWith?.amountMinorUnits, 150000);
      expect(find.textContaining('Payment submitted'), findsOneWidget);
    },
  );

  testWidgets('shows an error when checkout fails', (tester) async {
    final auth = await _connectedAuth();
    final client = _clientFor(
      invoices: {
        'invoices': [_invoiceJson],
        'total_due': 150000,
      },
      orderResponse: {
        'payment_id': 'payment-1',
        'invoice_id': 'invoice-1',
        'razorpay_order_id': 'order_123',
        'key_id': 'rzp_test_key',
      },
    );
    final checkout = _FakeRazorpayCheckout()
      ..succeed = false
      ..failureMessage = 'Payment cancelled by user';

    await tester.pumpWidget(
      _wrap(
        PaymentsScreen(
          authRepository: auth,
          paymentsRepository: PaymentsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
          checkout: checkout,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pay ₹1,500'));
    await tester.pumpAndSettle();

    expect(find.text('Payment cancelled by user'), findsOneWidget);
  });

  testWidgets(
    'shows cached data with a stale banner and lets Reconnect retry the fetch when offline',
    (tester) async {
      final auth = await _connectedAuth();
      final cache = _InMemoryCacheStore();
      await cache.write(
        'payments_invoices',
        jsonEncode({
          'data': {
            'invoices': [_invoiceJson],
            'total_due': 150000,
          },
          'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String(),
        }),
      );
      final client = MockClient(
        (request) async => throw const SocketException('no route to host'),
      );

      await tester.pumpWidget(
        _wrap(
          PaymentsScreen(
            authRepository: auth,
            paymentsRepository: PaymentsRepository(
              apiClient: ApiClient(httpClient: client),
            ),
            cacheStore: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Showing saved data from'), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);

      // Enabled (not disabled-with-a-misleading-label) — tapping it actually retries the
      // fetch rather than doing nothing. Still offline, so it falls back to the same
      // cached data again without crashing.
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Reconnect'),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Showing saved data from'), findsOneWidget);
    },
  );
}
