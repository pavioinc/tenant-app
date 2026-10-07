import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';
import 'package:pavio_tenant_app/features/auth/forgot_password_screen.dart';
import 'package:pavio_tenant_app/features/auth/reset_password_screen.dart';
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

void main() {
  testWidgets('shows a validation error for an invalid email without calling the network', (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return _json({}, 200);
    });

    await tester.pumpWidget(_wrap(ForgotPasswordScreen(authRepository: _repo(client))));
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Send reset code'));
    await tester.pump();

    expect(called, isFalse);
    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('submits the email and navigates to ResetPasswordScreen', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/auth/v1/tenant/password/forgot');
      expect(jsonDecode(request.body), {'email': 'amit@example.com'});
      return _json({'requested': true}, 200);
    });

    await tester.pumpWidget(_wrap(ForgotPasswordScreen(authRepository: _repo(client))));
    await tester.enterText(find.byType(TextField), 'amit@example.com');
    await tester.tap(find.text('Send reset code'));
    await tester.pumpAndSettle();

    expect(find.byType(ResetPasswordScreen), findsOneWidget);
  });

  testWidgets('shows a network error and stays put when the request never reaches the server', (tester) async {
    final client = MockClient((request) async => throw const SocketException('no route to host'));

    await tester.pumpWidget(_wrap(ForgotPasswordScreen(authRepository: _repo(client))));
    await tester.enterText(find.byType(TextField), 'amit@example.com');
    await tester.tap(find.text('Send reset code'));
    await tester.pumpAndSettle();

    expect(find.text('Network error — check your connection and try again'), findsOneWidget);
    expect(find.byType(ResetPasswordScreen), findsNothing);
  });
}
