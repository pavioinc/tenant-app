import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';
import 'package:pavio_tenant_app/features/rental/agreement_sign_screen.dart';
import 'package:pavio_tenant_app/features/rental/rental_repository.dart';
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

Future<AuthRepository> _connectedAuth() async {
  final store = _InMemorySecureStore();
  await store.write('pavio.access_token', 'access-token');
  await store.write('pavio.refresh_token', 'refresh-token');
  await store.write('pavio.access_token_expires_at', DateTime.now().add(const Duration(minutes: 30)).toIso8601String());
  await store.write(
    'pavio.user',
    jsonEncode({'user_id': 'account-1', 'name': 'Amit Kumar', 'role': 'tenant', 'connected': true, 'org_id': 'org-1', 'tenant_id': 'tenant-1'}),
  );
  return AuthRepository(sessionStore: SessionStore(storage: store));
}

const _draftAgreement = Agreement(
  agreementId: 'agreement-1',
  status: 'draft',
  monthlyRent: 800000,
  securityDeposit: 1600000,
  startDate: '2026-07-01',
  endDate: '2027-07-01',
  terms: 'Clause one.\nClause two.',
);

void main() {
  testWidgets('renders monthly rent, deposit, term, and every clause', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => throw StateError('unexpected request'));

    await tester.pumpWidget(
      MaterialApp(
        theme: PavioTheme.light(),
        home: AgreementSignScreen(
          agreement: _draftAgreement,
          authRepository: auth,
          rentalRepository: RentalRepository(apiClient: ApiClient(httpClient: client)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('₹8000'), findsOneWidget);
    expect(find.text('₹16000'), findsOneWidget);
    expect(find.text('2026-07-01 to 2027-07-01'), findsOneWidget);
    expect(find.textContaining('1. Clause one.'), findsOneWidget);
    expect(find.textContaining('2. Clause two.'), findsOneWidget);
  });

  testWidgets('shows an error and stays on the screen when the sign call fails', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me/agreements/agreement-1/sign') {
        return _json({'error': 'already_signed', 'message': 'this agreement has already been signed'}, 409);
      }
      throw StateError('unexpected request: ${request.method} ${request.url.path}');
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: PavioTheme.light(),
        home: AgreementSignScreen(
          agreement: _draftAgreement,
          authRepository: auth,
          rentalRepository: RentalRepository(apiClient: ApiClient(httpClient: client)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Amit Kumar');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final submitButton = find.widgetWithText(ElevatedButton, 'Sign & Submit');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('this agreement has already been signed'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign & Submit'), findsOneWidget); // still on the sign screen, not popped
  });
}
