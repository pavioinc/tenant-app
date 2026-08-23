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
import 'package:nivasaos_tenant_app/features/lease/lease_screen.dart';
import 'package:nivasaos_tenant_app/features/renewal/renewal_repository.dart';
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

const _rentalWithEverything = {
  'tenant_id': 'tenant-1',
  'allocation': {'check_in_date': '2026-07-01'},
  'bed': {'label': 'B', 'room_name': '204', 'floor_name': 'Floor 1'},
  'agreement': {
    'status': 'signed',
    'monthly_rent': 800000,
    'security_deposit': 1600000,
    'start_date': '2026-07-01',
    'end_date': '2027-07-01',
  },
};

/// LeaseScreen stacks a lot more content than either of its two predecessor screens did
/// (room/rent/agreement/offers cards plus the full renewal section) — same reasoning as
/// home_screen_test.dart's `_useTallSurface`: ListView only builds elements within (or
/// near) the viewport, so the default test surface undercounts far-down widgets.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _leaseScreen({
  required AuthRepository auth,
  required http.Client client,
  CacheStore? cacheStore,
}) => _wrap(
  LeaseScreen(
    authRepository: auth,
    rentalRepository: RentalRepository(apiClient: ApiClient(httpClient: client)),
    renewalRepository: RenewalRepository(apiClient: ApiClient(httpClient: client)),
    cacheStore: cacheStore ?? _InMemoryCacheStore(),
  ),
);

void main() {
  testWidgets('shows room, rent, and agreement details plus empty renewal history', (tester) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me/rental') return _json(_rentalWithEverything, 200);
      if (request.url.path == '/api/billing/v1/tenant/me/billing-profile') {
        return _json({
          'billing_profile': {'amount': 800000, 'cycle_type': 'monthly'},
        }, 200);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me/renewal-requests' && request.method == 'GET') {
        return _json({'renewal_requests': []}, 200);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(_leaseScreen(auth: auth, client: client));
    await tester.pumpAndSettle();

    expect(find.text('204 · Bed B'), findsOneWidget);
    expect(find.text('Checked in 2026-07-01'), findsOneWidget);
    expect(find.text('₹8000/month'), findsOneWidget);
    expect(find.text('Signed'), findsOneWidget);
    expect(find.text('Monthly rent ₹8000 · Deposit ₹16000'), findsOneWidget);
    expect(find.text('No renewal requests yet'), findsOneWidget);
    expect(find.text('Request renewal'), findsOneWidget);
  });

  testWidgets('shows empty states when nothing is set up yet', (tester) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me/rental') {
        return _json({'tenant_id': 'tenant-1', 'allocation': null, 'bed': null, 'agreement': null}, 200);
      }
      if (request.url.path == '/api/billing/v1/tenant/me/billing-profile') return _json({'billing_profile': null}, 200);
      if (request.url.path == '/api/tenants/v1/tenant/me/renewal-requests' && request.method == 'GET') {
        return _json({'renewal_requests': []}, 200);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(_leaseScreen(auth: auth, client: client));
    await tester.pumpAndSettle();

    expect(find.text('Not assigned to a bed yet'), findsOneWidget);
    expect(find.text('No billing set up yet'), findsOneWidget);
    expect(find.text('No agreement on file yet'), findsOneWidget);
  });

  testWidgets('shows an error state when the fetch fails', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'error': 'not_found', 'message': 'not connected to a property yet'}, 404));

    await tester.pumpWidget(_leaseScreen(auth: auth, client: client));
    await tester.pumpAndSettle();

    expect(find.text('not connected to a property yet'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('requests a renewal and shows it in history after reload', (tester) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    var posted = false;
    var requestCount = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me/rental') return _json(_rentalWithEverything, 200);
      if (request.url.path == '/api/billing/v1/tenant/me/billing-profile') {
        return _json({
          'billing_profile': {'amount': 800000, 'cycle_type': 'monthly'},
        }, 200);
      }
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

    await tester.pumpWidget(_leaseScreen(auth: auth, client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Request renewal'));
    await tester.pumpAndSettle();

    expect(posted, isTrue);
    expect(find.text('A renewal request is pending — your property manager has been notified.'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('shows cached data with a stale banner and lets Reconnect retry the fetch when offline', (tester) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    final cache = _InMemoryCacheStore();
    await cache.write(
      'rental_info',
      jsonEncode({'data': _rentalWithEverything, 'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String()}),
    );
    await cache.write(
      'renewal_requests',
      jsonEncode({'data': <dynamic>[], 'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String()}),
    );
    final client = MockClient((request) async => throw const SocketException('no route to host'));

    await tester.pumpWidget(_leaseScreen(auth: auth, client: client, cacheStore: cache));
    await tester.pumpAndSettle();

    expect(find.text('204 · Bed B'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
    expect(find.text('Reconnect to request a renewal'), findsOneWidget);

    // Enabled (not disabled-with-a-misleading-label) — tapping it actually retries the
    // fetch rather than doing nothing. Still offline, so it falls back to the same
    // cached data again without crashing.
    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Reconnect to request a renewal'));
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('Reconnect to request a renewal'));
    await tester.pumpAndSettle();

    expect(find.text('204 · Bed B'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });
}
