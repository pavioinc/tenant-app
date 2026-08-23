import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivasaos_tenant_app/core/api_client.dart';
import 'package:nivasaos_tenant_app/core/cache_store.dart';
import 'package:nivasaos_tenant_app/core/razorpay_checkout.dart';
import 'package:nivasaos_tenant_app/core/session_store.dart';
import 'package:nivasaos_tenant_app/features/auth/auth_repository.dart';
import 'package:nivasaos_tenant_app/features/payments/payments_repository.dart';
import 'package:nivasaos_tenant_app/features/payments/payments_screen.dart';
import 'package:nivasaos_tenant_app/theme/nivasa_theme.dart';

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

http.Response _json(Map<String, dynamic> body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Widget _wrap(Widget child) => MaterialApp(theme: NivasaTheme.light(), home: child);

Future<AuthRepository> _connectedAuth() async {
  final store = _InMemorySecureStore();
  await store.write('nivasaos.access_token', 'access-token');
  await store.write('nivasaos.refresh_token', 'refresh-token');
  await store.write('nivasaos.access_token_expires_at', DateTime.now().add(const Duration(minutes: 30)).toIso8601String());
  await store.write(
    'nivasaos.user',
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

const _invoiceJson = {'invoice_id': 'invoice-1', 'amount': 150000, 'currency': 'INR', 'due_date': '2026-08-15', 'status': 'pending'};

void main() {
  testWidgets('shows total due and an empty state with nothing pending', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'invoices': [], 'total_due': 0}, 200));

    await tester.pumpWidget(
      _wrap(
        PaymentsScreen(
          authRepository: auth,
          paymentsRepository: PaymentsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('₹0'), findsOneWidget);
    expect(find.text('Nothing to pay right now'), findsOneWidget);
  });

  testWidgets('lists pending invoices with the total due', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'invoices': [_invoiceJson], 'total_due': 150000}, 200));

    await tester.pumpWidget(
      _wrap(
        PaymentsScreen(
          authRepository: auth,
          paymentsRepository: PaymentsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('₹1500'), findsNWidgets(2));
    expect(find.text('Due 2026-08-15'), findsOneWidget);
    expect(find.text('Pay'), findsOneWidget);
  });

  testWidgets('paying creates an order and opens checkout with the right amount', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        return _json({'payment_id': 'payment-1', 'invoice_id': 'invoice-1', 'razorpay_order_id': 'order_123', 'key_id': 'rzp_test_key'}, 201);
      }
      return _json({'invoices': [_invoiceJson], 'total_due': 150000}, 200);
    });
    final checkout = _FakeRazorpayCheckout();

    await tester.pumpWidget(
      _wrap(
        PaymentsScreen(
          authRepository: auth,
          paymentsRepository: PaymentsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
          checkout: checkout,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();

    expect(checkout.openedWith?.keyId, 'rzp_test_key');
    expect(checkout.openedWith?.razorpayOrderId, 'order_123');
    expect(checkout.openedWith?.amountMinorUnits, 150000);
    expect(find.textContaining('Payment submitted'), findsOneWidget);
  });

  testWidgets('shows an error when checkout fails', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        return _json({'payment_id': 'payment-1', 'invoice_id': 'invoice-1', 'razorpay_order_id': 'order_123', 'key_id': 'rzp_test_key'}, 201);
      }
      return _json({'invoices': [_invoiceJson], 'total_due': 150000}, 200);
    });
    final checkout = _FakeRazorpayCheckout()
      ..succeed = false
      ..failureMessage = 'Payment cancelled by user';

    await tester.pumpWidget(
      _wrap(
        PaymentsScreen(
          authRepository: auth,
          paymentsRepository: PaymentsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
          checkout: checkout,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();

    expect(find.text('Payment cancelled by user'), findsOneWidget);
  });

  testWidgets('shows cached data with a stale banner and lets Reconnect retry the fetch when offline', (tester) async {
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
    final client = MockClient((request) async => throw const SocketException('no route to host'));

    await tester.pumpWidget(
      _wrap(
        PaymentsScreen(
          authRepository: auth,
          paymentsRepository: PaymentsRepository(apiClient: ApiClient(httpClient: client)),
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
    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Reconnect'));
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('Reconnect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });
}
