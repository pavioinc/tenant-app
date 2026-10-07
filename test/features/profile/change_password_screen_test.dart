import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';
import 'package:pavio_tenant_app/features/profile/change_password_screen.dart';
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

Future<AuthRepository> _connectedAuth(http.Client client) async {
  final store = _InMemorySecureStore();
  await store.write('pavio.access_token', 'access-token');
  await store.write('pavio.refresh_token', 'refresh-token');
  await store.write('pavio.access_token_expires_at', DateTime.now().add(const Duration(minutes: 30)).toIso8601String());
  await store.write(
    'pavio.user',
    jsonEncode({'user_id': 'account-1', 'name': 'Amit Kumar', 'role': 'tenant', 'connected': true, 'org_id': 'org-1', 'property_id': 'prop-1'}),
  );
  return AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: store));
}

// Pushed on top of a dummy home screen (rather than pumped directly as `home`) so a
// successful submit's Navigator.pop() has somewhere real to land — matches how this
// screen is actually reached from SettingsScreen.
Widget _wrap(AuthRepository auth) {
  return MaterialApp(
    theme: PavioTheme.light(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChangePasswordScreen(authRepository: auth))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows validation errors for empty/short/mismatched fields without calling the network', (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return _json({}, 200);
    });
    final auth = await _connectedAuth(client);

    await tester.pumpWidget(_wrap(auth));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'short');
    await tester.enterText(find.byType(TextField).at(2), 'different');
    await tester.tap(find.text('Update password'));
    await tester.pump();

    expect(called, isFalse);
    expect(find.text('Enter your current password'), findsOneWidget);
    expect(find.text('Must be at least 8 characters'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('shows the server error against the current-password field on invalid_password', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/auth/v1/tenant/password');
      return _json({'error': 'invalid_password', 'message': 'current password is incorrect'}, 401);
    });
    final auth = await _connectedAuth(client);

    await tester.pumpWidget(_wrap(auth));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'wrong-password');
    await tester.enterText(find.byType(TextField).at(1), 'a-new-strong-password');
    await tester.enterText(find.byType(TextField).at(2), 'a-new-strong-password');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(find.text('Current password is incorrect'), findsOneWidget);
  });

  testWidgets('updates the password and pops back on success', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/auth/v1/tenant/password');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['current_password'], 'correct-horse-battery-staple');
      expect(body['new_password'], 'a-new-strong-password');
      return _json({'updated': true}, 200);
    });
    final auth = await _connectedAuth(client);

    await tester.pumpWidget(_wrap(auth));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'correct-horse-battery-staple');
    await tester.enterText(find.byType(TextField).at(1), 'a-new-strong-password');
    await tester.enterText(find.byType(TextField).at(2), 'a-new-strong-password');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(find.text('Password updated'), findsOneWidget);
  });
}
