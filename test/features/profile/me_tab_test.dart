import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';
import 'package:pavio_tenant_app/features/contacts/contacts_screen.dart';
import 'package:pavio_tenant_app/features/documents/documents_screen.dart';
import 'package:pavio_tenant_app/features/guests/guests_screen.dart';
import 'package:pavio_tenant_app/features/kyc/kyc_repository.dart';
import 'package:pavio_tenant_app/features/lease/lease_screen.dart';
import 'package:pavio_tenant_app/features/profile/me_tab.dart';
import 'package:pavio_tenant_app/features/profile/user_screen.dart';
import 'package:pavio_tenant_app/features/vehicles/vehicles_screen.dart';
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

void main() {
  testWidgets('shows the renter\'s name and a verified KYC chip', (tester) async {
    final auth = await _connectedAuth();
    final kyc = KycRepository(
      apiClient: ApiClient(
        httpClient: MockClient(
          (_) async => _json({
            'status': 'verified',
            'aadhaar_last4': '1234',
            'verified_at': '2026-08-01T00:00:00.000Z',
          }, 200),
        ),
      ),
    );

    await tester.pumpWidget(
      _wrap(MeTab(authRepository: auth, kycRepository: kyc)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Amit Kumar'), findsOneWidget);
    expect(find.text('KYC verified'), findsOneWidget);
  });

  testWidgets('shows a pending KYC chip when not yet verified', (tester) async {
    final auth = await _connectedAuth();
    final kyc = KycRepository(
      apiClient: ApiClient(
        httpClient: MockClient(
          (_) async => _json({'status': 'pending'}, 200),
        ),
      ),
    );

    await tester.pumpWidget(
      _wrap(MeTab(authRepository: auth, kycRepository: kyc)),
    );
    await tester.pumpAndSettle();

    expect(find.text('KYC pending'), findsOneWidget);
  });

  Future<void> expectRowReaches(
    WidgetTester tester,
    String label,
    Type screenType,
  ) async {
    final auth = await _connectedAuth();
    final kyc = KycRepository(
      apiClient: ApiClient(
        httpClient: MockClient((_) async => _json({'status': 'verified'}, 200)),
      ),
    );
    await tester.pumpWidget(
      _wrap(MeTab(authRepository: auth, kycRepository: kyc)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();

    expect(find.byType(screenType), findsOneWidget, reason: label);
  }

  testWidgets('the Lease row navigates to LeaseScreen', (tester) async {
    await expectRowReaches(tester, 'Lease', LeaseScreen);
  });

  testWidgets('the Documents row navigates to DocumentsScreen', (
    tester,
  ) async {
    await expectRowReaches(tester, 'Documents', DocumentsScreen);
  });

  testWidgets('the Guests row navigates to GuestsScreen', (tester) async {
    await expectRowReaches(tester, 'Guests', GuestsScreen);
  });

  testWidgets('the Vehicles row navigates to VehiclesScreen', (tester) async {
    await expectRowReaches(tester, 'Vehicles', VehiclesScreen);
  });

  testWidgets('the Contacts row navigates to ContactsScreen', (tester) async {
    await expectRowReaches(tester, 'Contacts', ContactsScreen);
  });

  testWidgets('the Your account row navigates to UserScreen', (tester) async {
    await expectRowReaches(tester, 'Your account', UserScreen);
  });
}
