import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivasaos_tenant_app/core/api_client.dart';
import 'package:nivasaos_tenant_app/core/cache_store.dart';
import 'package:nivasaos_tenant_app/core/session_store.dart';
import 'package:nivasaos_tenant_app/features/auth/auth_repository.dart';
import 'package:nivasaos_tenant_app/features/renewal/renewal_repository.dart';
import 'package:nivasaos_tenant_app/features/renewal/renewal_screen.dart';
import 'package:nivasaos_tenant_app/features/rental/rental_repository.dart';
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

http.Response _json(Map<String, dynamic> body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Widget _wrap(Widget child) => MaterialApp(theme: NivasaTheme.light(), home: child);

Future<AuthRepository> _connectedAuth() async {
  final store = _InMemorySecureStore();
  await store.write('nivasaos.access_token', 'access-token');
  await store.write('nivasaos.refresh_token', 'refresh-token');
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

const _rentalWithAgreement = {
  'tenant_id': 'tenant-1',
  'allocation': null,
  'bed': null,
  'agreement': {
    'status': 'signed',
    'monthly_rent': 800000,
    'security_deposit': 1600000,
    'start_date': '2026-07-01',
    'end_date': '2027-07-01',
  },
};

void main() {
  testWidgets('shows the agreement end date and empty request history', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me/rental') return _json(_rentalWithAgreement, 200);
      if (request.url.path == '/api/billing/v1/tenant/me/billing-profile') return _json({'billing_profile': null}, 200);
      if (request.url.path == '/api/tenants/v1/tenant/me/renewal-requests' && request.method == 'GET') {
        return _json({'renewal_requests': []}, 200);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(
      _wrap(RenewalScreen(
        authRepository: auth,
        renewalRepository: RenewalRepository(apiClient: ApiClient(httpClient: client)),
        rentalRepository: RentalRepository(apiClient: ApiClient(httpClient: client)),
        cacheStore: _InMemoryCacheStore(),
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ends 2027-07-01'), findsOneWidget);
    expect(find.text('No renewal requests yet'), findsOneWidget);
    expect(find.text('Request renewal'), findsOneWidget);
  });

  testWidgets('requests a renewal and shows it in history after reload', (tester) async {
    final auth = await _connectedAuth();
    var posted = false;
    var requestCount = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me/rental') return _json(_rentalWithAgreement, 200);
      if (request.url.path == '/api/billing/v1/tenant/me/billing-profile') return _json({'billing_profile': null}, 200);
      if (request.url.path == '/api/tenants/v1/tenant/me/renewal-requests' && request.method == 'POST') {
        posted = true;
        return _json({
          'renewal_request_id': 'renewal-1',
          'tenant_id': 'tenant-1',
          'property_id': 'prop-1',
          'agreement_id': 'agreement-1',
          'requested_end_date': null,
          'status': 'pending',
          'created_at': '2026-08-14T00:00:00Z',
        }, 201);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me/renewal-requests' && request.method == 'GET') {
        requestCount += 1;
        if (requestCount == 1) return _json({'renewal_requests': []}, 200);
        return _json({
          'renewal_requests': [
            {
              'renewal_request_id': 'renewal-1',
              'tenant_id': 'tenant-1',
              'property_id': 'prop-1',
              'agreement_id': 'agreement-1',
              'requested_end_date': null,
              'status': 'pending',
              'created_at': '2026-08-14T00:00:00Z',
            },
          ],
        }, 200);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(
      _wrap(RenewalScreen(
        authRepository: auth,
        renewalRepository: RenewalRepository(apiClient: ApiClient(httpClient: client)),
        rentalRepository: RentalRepository(apiClient: ApiClient(httpClient: client)),
        cacheStore: _InMemoryCacheStore(),
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Request renewal'));
    await tester.pumpAndSettle();

    expect(posted, isTrue);
    expect(find.text('A renewal request is pending — your property manager has been notified.'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('shows cached data with a stale banner and disables the renewal button when offline', (tester) async {
    final auth = await _connectedAuth();
    final cache = _InMemoryCacheStore();
    await cache.write(
      'rental_info',
      jsonEncode({'data': _rentalWithAgreement, 'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String()}),
    );
    await cache.write(
      'renewal_requests',
      jsonEncode({'data': <dynamic>[], 'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String()}),
    );
    final client = MockClient((request) async => throw const SocketException('no route to host'));

    await tester.pumpWidget(
      _wrap(RenewalScreen(
        authRepository: auth,
        renewalRepository: RenewalRepository(apiClient: ApiClient(httpClient: client)),
        rentalRepository: RentalRepository(apiClient: ApiClient(httpClient: client)),
        cacheStore: cache,
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ends 2027-07-01'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
    expect(find.text('Reconnect to request a renewal'), findsOneWidget);

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Reconnect to request a renewal'));
    expect(button.onPressed, isNull);
  });
}
