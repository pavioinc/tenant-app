import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/cache_store.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';
import 'package:pavio_tenant_app/features/home/home_tab.dart';
import 'package:pavio_tenant_app/features/payments/payments_repository.dart';
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

/// Routes a fake client's responses by path, mirroring PaymentsScreen's own test helper
/// — HomeTab calls the exact same two GET endpoints.
http.Client _clientFor({
  Map<String, dynamic> invoices = const {'invoices': [], 'total_due': 0},
  Map<String, dynamic> transactions = const {'transactions': []},
}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/transactions')) return _json(transactions, 200);
    return _json(invoices, 200);
  });
}

void main() {
  testWidgets('greets the renter by full name and shows "Nothing to pay" with no dues', (
    tester,
  ) async {
    final auth = await _connectedAuth();

    await tester.pumpWidget(
      _wrap(
        HomeTab(
          onGoToPay: () {},
          authRepository: auth,
          paymentsRepository: PaymentsRepository(
            apiClient: ApiClient(httpClient: _clientFor()),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Amit Kumar'), findsOneWidget);
    expect(find.text('Namaskaram 🙏'), findsOneWidget);
    expect(find.text('Nothing to pay'), findsOneWidget);
    expect(find.text('No payments yet'), findsOneWidget);
  });

  testWidgets('shows the rent-due hero and switches to Pay when tapped', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = _clientFor(
      invoices: {
        'invoices': [_invoiceJson],
        'total_due': 150000,
      },
    );
    var tappedPay = false;

    await tester.pumpWidget(
      _wrap(
        HomeTab(
          onGoToPay: () => tappedPay = true,
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
    expect(find.text('Saturday 15 August'), findsOneWidget);

    await tester.tap(find.text('Rent due'));
    await tester.pumpAndSettle();

    expect(tappedPay, isTrue);
  });

  testWidgets('shows up to 3 recent payments, excluding pending charges', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = _clientFor(
      transactions: {
        'transactions': [
          {
            'transaction_id': 't-1',
            'type': 'charge',
            'title': 'Scheduled Charges',
            'subtitle': null,
            'amount': 179700,
            'currency': 'INR',
            'date': '2026-10-01',
          },
          {
            'transaction_id': 't-2',
            'type': 'payment',
            'title': 'Rent — September',
            'subtitle': 'UPI',
            'amount': 150000,
            'currency': 'INR',
            'date': '2026-09-02',
          },
        ],
      },
    );

    await tester.pumpWidget(
      _wrap(
        HomeTab(
          onGoToPay: () {},
          authRepository: auth,
          paymentsRepository: PaymentsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rent — September'), findsOneWidget);
    expect(find.textContaining('UPI'), findsOneWidget);
    expect(find.text('Scheduled Charges'), findsNothing);
    expect(find.text('No payments yet'), findsNothing);
  });
}
