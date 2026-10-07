import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';
import 'package:pavio_tenant_app/features/kyc/kyc_repository.dart';
import 'package:pavio_tenant_app/features/kyc/kyc_screen.dart';
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

http.Response _json(Map<String, dynamic> body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Widget _wrap(Widget child) => MaterialApp(theme: PavioTheme.light(), home: child);

Future<AuthRepository> _connectedAuth() async {
  final store = _InMemorySecureStore();
  await store.write('pavio.access_token', 'access-token');
  await store.write('pavio.refresh_token', 'refresh-token');
  await store.write('pavio.access_token_expires_at', DateTime.now().add(const Duration(minutes: 30)).toIso8601String());
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
  testWidgets('rejects an aadhaar number that is not exactly 12 digits', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => throw StateError('should not call the network'));

    await tester.pumpWidget(
      _wrap(KycScreen(authRepository: auth, kycRepository: KycRepository(apiClient: ApiClient(httpClient: client)))),
    );

    await tester.enterText(find.byKey(const Key('aadhaar-field')), '12345');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your 12-digit Aadhaar number'), findsOneWidget);
  });

  testWidgets('requests an OTP, then verifies it and pops true', (tester) async {
    final auth = await _connectedAuth();
    Map<String, dynamic>? requestedBody;
    Map<String, dynamic>? verifiedBody;
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me/kyc/request-otp') {
        requestedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'requested': true, 'expires_in_seconds': 300, 'debug_code': '123456'}, 200);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me/kyc/verify-otp') {
        verifiedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'status': 'verified', 'aadhaar_last4': '9012', 'verified_at': '2026-08-21T12:00:00Z'}, 200);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    bool? popped;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => KycScreen(authRepository: auth, kycRepository: KycRepository(apiClient: ApiClient(httpClient: client))),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('aadhaar-field')), '234567890123');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();

    expect(requestedBody?['aadhaar_number'], '234567890123');
    expect(find.text('Enter the OTP'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(verifiedBody?['code'], '123456');
    expect(popped, isTrue);
  });

  testWidgets('shows an inline error for the wrong OTP without leaving the OTP step', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me/kyc/request-otp') {
        return _json({'requested': true, 'expires_in_seconds': 300}, 200);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me/kyc/verify-otp') {
        return _json({'error': 'wrong_code', 'message': 'incorrect code'}, 401);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(
      _wrap(KycScreen(authRepository: auth, kycRepository: KycRepository(apiClient: ApiClient(httpClient: client)))),
    );

    await tester.enterText(find.byKey(const Key('aadhaar-field')), '234567890123');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('otp-field')), '000000');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.text('incorrect code'), findsOneWidget);
    expect(find.text('Enter the OTP'), findsOneWidget);
  });
}
