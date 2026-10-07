import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';
import 'package:pavio_tenant_app/features/auth/login_screen.dart';
import 'package:pavio_tenant_app/features/auth/reset_password_screen.dart';
import 'package:pavio_tenant_app/widgets/pavio_button.dart';
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

AuthRepository _repo(http.Client client) =>
    AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

const _strongPassword = 'New-Str0ng-Pass!';

void main() {
  testWidgets('shows validation errors for an empty code, weak password, and mismatched confirmation', (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return _json({}, 200);
    });

    await tester.pumpWidget(_wrap(ResetPasswordScreen(authRepository: _repo(client))));
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, ''); // reset code left empty
    await tester.enterText(fields.at(1), 'short');
    await tester.enterText(fields.at(2), 'different');
    await tester.tap(find.widgetWithText(PavioPrimaryButton, 'Reset password'));
    await tester.pump();

    expect(called, isFalse);
    expect(find.text('Enter the reset code from your email'), findsOneWidget);
    expect(find.text('Password does not meet the requirements below'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('resets the password and navigates to LoginScreen', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/auth/v1/tenant/password/reset');
      expect(jsonDecode(request.body), {'token': 'reset-code-123', 'new_password': _strongPassword});
      return _json({'updated': true}, 200);
    });

    await tester.pumpWidget(_wrap(ResetPasswordScreen(authRepository: _repo(client))));
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'reset-code-123');
    await tester.enterText(fields.at(1), _strongPassword);
    await tester.enterText(fields.at(2), _strongPassword);
    await tester.tap(find.widgetWithText(PavioPrimaryButton, 'Reset password'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Password updated — log in with your new password'), findsOneWidget);
  });

  testWidgets('shows an invalid-code error on an expired/used token, without navigating', (tester) async {
    final client = MockClient(
      (request) async => _json({'error': 'invalid_token', 'message': 'this reset link is invalid or has expired'}, 400),
    );

    await tester.pumpWidget(_wrap(ResetPasswordScreen(authRepository: _repo(client))));
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'stale-code');
    await tester.enterText(fields.at(1), _strongPassword);
    await tester.enterText(fields.at(2), _strongPassword);
    await tester.tap(find.widgetWithText(PavioPrimaryButton, 'Reset password'));
    await tester.pumpAndSettle();

    expect(find.text('This code is invalid or has expired — request a new one'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
