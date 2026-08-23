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
import 'package:nivasaos_tenant_app/features/kyc/kyc_repository.dart';
import 'package:nivasaos_tenant_app/features/payments/payments_repository.dart';
import 'package:nivasaos_tenant_app/features/profile/profile_repository.dart';
import 'package:nivasaos_tenant_app/features/profile/profile_screen.dart';
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

/// ProfileScreen now stacks a lot more content (property info, rent-due card, permanent
/// address, emergency contact fields) than the default test surface can fit — same
/// reasoning as lease_screen_test.dart's own _useTallSurface: SingleChildScrollView only
/// renders within (or near) the viewport, so far-down widgets like "Save"/"Verify now"
/// can't be tapped at the default 800x600 size.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Map<String, dynamic> _kycStatusJson({String status = 'not_started', String? aadhaarLast4, String? verifiedAt}) => {
  'status': status,
  'aadhaar_last4': aadhaarLast4,
  'verified_at': verifiedAt,
};

Map<String, dynamic> _profileJson({
  String phone = '+919876543210',
  String language = 'en',
  String? propertyName = 'Sunrise Residency',
  String? propertyCity = 'Bengaluru',
  String? propertyAddress = '12 MG Road',
  String? permanentAddress,
  String? emergencyContactName,
  String? emergencyContactPhone,
  String? emergencyContactRelationship,
}) => {
  'tenant_id': 'tenant-1',
  'property_id': 'prop-1',
  'property_name': propertyName,
  'property_city': propertyCity,
  'property_address': propertyAddress,
  'name': 'Amit Kumar',
  'phone': phone,
  'email': 'amit@example.com',
  'language': language,
  'status': 'active',
  'permanent_address': permanentAddress,
  'emergency_contact_name': emergencyContactName,
  'emergency_contact_phone': emergencyContactPhone,
  'emergency_contact_relationship': emergencyContactRelationship,
  'account_full_name': 'Amit Kumar',
  'account_email': 'amit@nivasa.app',
};

Map<String, dynamic> _pendingInvoicesJson({List<Map<String, dynamic>> invoices = const [], int totalDue = 0}) => {
  'invoices': invoices,
  'total_due': totalDue,
};

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

Widget _profileScreen({
  required AuthRepository auth,
  required http.Client client,
  CacheStore? cacheStore,
}) {
  final apiClient = ApiClient(httpClient: client);
  return ProfileScreen(
    authRepository: auth,
    profileRepository: ProfileRepository(apiClient: apiClient),
    kycRepository: KycRepository(apiClient: apiClient),
    paymentsRepository: PaymentsRepository(apiClient: apiClient),
    cacheStore: cacheStore ?? _InMemoryCacheStore(),
  );
}

void main() {
  testWidgets('loads and displays the profile, property, and rent due', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer access-token');
      if (request.url.path == '/api/tenants/v1/tenant/me' && request.method == 'GET') {
        return _json(_profileJson(), 200);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me/kyc/status') {
        return _json(_kycStatusJson(), 200);
      }
      if (request.url.path == '/api/payments/v1/tenant/me/invoices') {
        return _json(
          _pendingInvoicesJson(
            invoices: [
              {'invoice_id': 'invoice-1', 'amount': 500000, 'currency': 'INR', 'due_date': '2026-09-05', 'status': 'pending'},
            ],
            totalDue: 500000,
          ),
          200,
        );
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(_wrap(_profileScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    expect(find.text('Amit Kumar'), findsOneWidget);
    expect(find.text('amit@example.com'), findsOneWidget);
    expect(find.widgetWithText(TextField, '+919876543210'), findsOneWidget);
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text('Verify now'), findsOneWidget);
    expect(find.text('Sunrise Residency, Bengaluru'), findsOneWidget);
    expect(find.text('12 MG Road'), findsOneWidget);
    expect(find.text('Rent due'), findsOneWidget);
    expect(find.textContaining('₹5000'), findsOneWidget);
  });

  testWidgets('shows "No rent due" when there are no pending invoices', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me' && request.method == 'GET') {
        return _json(_profileJson(), 200);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me/kyc/status') {
        return _json(_kycStatusJson(), 200);
      }
      if (request.url.path == '/api/payments/v1/tenant/me/invoices') {
        return _json(_pendingInvoicesJson(), 200);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(_wrap(_profileScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    expect(find.text('No rent due'), findsOneWidget);
  });

  testWidgets('saves an updated phone, language, permanent address, and emergency contact', (tester) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    var patchedBody = <String, dynamic>{};
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me' && request.method == 'GET') {
        return _json(_profileJson(), 200);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me' && request.method == 'PATCH') {
        patchedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(
          _profileJson(
            phone: '+919999999999',
            language: 'ml',
            permanentAddress: '221B Baker Street',
            emergencyContactName: 'Priya Kumar',
            emergencyContactPhone: '+919888888888',
            emergencyContactRelationship: 'Spouse',
          ),
          200,
        );
      }
      if (request.url.path == '/api/tenants/v1/tenant/me/kyc/status') {
        return _json(_kycStatusJson(), 200);
      }
      if (request.url.path == '/api/payments/v1/tenant/me/invoices') {
        return _json(_pendingInvoicesJson(), 200);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(_wrap(_profileScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '+919876543210'), '+919999999999');
    await tester.enterText(find.widgetWithText(TextField, 'Optional'), '221B Baker Street');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Priya Kumar');
    await tester.enterText(find.widgetWithText(TextField, 'Phone'), '+919888888888');
    await tester.enterText(find.widgetWithText(TextField, 'Relationship, e.g. Parent, Spouse, Sibling'), 'Spouse');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(patchedBody['phone'], '+919999999999');
    expect(patchedBody['permanent_address'], '221B Baker Street');
    expect(patchedBody['emergency_contact_name'], 'Priya Kumar');
    expect(patchedBody['emergency_contact_phone'], '+919888888888');
    expect(patchedBody['emergency_contact_relationship'], 'Spouse');
    expect(find.text('Profile updated'), findsOneWidget);
  });

  testWidgets('leaving emergency contact fields blank omits them from the PATCH body', (tester) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    var patchedBody = <String, dynamic>{};
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me' && request.method == 'GET') {
        return _json(_profileJson(), 200);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me' && request.method == 'PATCH') {
        patchedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(_profileJson(phone: '+919999999999'), 200);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me/kyc/status') {
        return _json(_kycStatusJson(), 200);
      }
      if (request.url.path == '/api/payments/v1/tenant/me/invoices') {
        return _json(_pendingInvoicesJson(), 200);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(_wrap(_profileScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '+919876543210'), '+919999999999');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(patchedBody['phone'], '+919999999999');
    expect(patchedBody.containsKey('permanent_address'), isFalse);
    expect(patchedBody.containsKey('emergency_contact_name'), isFalse);
    expect(patchedBody.containsKey('emergency_contact_phone'), isFalse);
    expect(patchedBody.containsKey('emergency_contact_relationship'), isFalse);
  });

  testWidgets('shows an error state when the fetch fails', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'error': 'internal_error', 'message': 'boom'}, 500));

    await tester.pumpWidget(_wrap(_profileScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows cached data with a stale banner when offline', (tester) async {
    final auth = await _connectedAuth();
    final cache = _InMemoryCacheStore();
    await cache.write(
      'profile',
      jsonEncode({
        'data': _profileJson(phone: '+919000000000'),
        'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String(),
      }),
    );
    final client = MockClient((request) async => throw const SocketException('no route to host'));

    await tester.pumpWidget(_wrap(_profileScreen(auth: auth, client: client, cacheStore: cache)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '+919000000000'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });

  testWidgets('shows Verified and no button once KYC is verified', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me' && request.method == 'GET') {
        return _json(_profileJson(), 200);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me/kyc/status') {
        return _json(_kycStatusJson(status: 'verified', aadhaarLast4: '9012', verifiedAt: '2026-08-21T12:00:00Z'), 200);
      }
      if (request.url.path == '/api/payments/v1/tenant/me/invoices') {
        return _json(_pendingInvoicesJson(), 200);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(_wrap(_profileScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    expect(find.text('Verified'), findsOneWidget);
    expect(find.textContaining('Aadhaar •••• 9012'), findsOneWidget);
    expect(find.text('Verify now'), findsNothing);
  });

  testWidgets('tapping Verify now opens the KYC screen', (tester) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me' && request.method == 'GET') {
        return _json(_profileJson(), 200);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me/kyc/status') {
        return _json(_kycStatusJson(), 200);
      }
      if (request.url.path == '/api/payments/v1/tenant/me/invoices') {
        return _json(_pendingInvoicesJson(), 200);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(_wrap(_profileScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verify now'));
    await tester.pumpAndSettle();

    expect(find.text('Verify with Aadhaar'), findsOneWidget);
  });
}
