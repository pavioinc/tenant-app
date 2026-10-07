import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';
import 'package:pavio_tenant_app/features/auth/forgot_password_screen.dart';
import 'package:pavio_tenant_app/features/auth/login_screen.dart';
import 'package:pavio_tenant_app/features/auth/signup_screen.dart';
import 'package:pavio_tenant_app/features/home/home_screen.dart';
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

void main() {
  testWidgets('shows a validation error for empty fields without calling the network', (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return _json({}, 200);
    });
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

    await tester.pumpWidget(_wrap(LoginScreen(authRepository: repo)));
    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(called, isFalse);
    expect(find.text('Enter your email and password'), findsOneWidget);
  });

  testWidgets('toggles password visibility', (tester) async {
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 500))),
      sessionStore: SessionStore(storage: _InMemorySecureStore()),
    );

    await tester.pumpWidget(_wrap(LoginScreen(authRepository: repo)));

    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('navigates to HomeScreen on successful login', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/auth/v1/tenant/login');
      return _json({
        'access_token': 'access-token',
        'refresh_token': 'refresh-token',
        'expires_at': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
        'user': {'user_id': 'account-1', 'name': 'Amit Kumar', 'role': 'tenant', 'connected': true, 'org_id': 'org-1', 'property_id': 'prop-1'},
      }, 200);
    });
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

    await tester.pumpWidget(_wrap(LoginScreen(authRepository: repo)));
    await tester.enterText(find.byType(TextField).first, 'amit@example.com');
    await tester.enterText(find.byType(TextField).last, 'correct-horse-battery-staple');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('shows the server error message on invalid credentials', (tester) async {
    final client = MockClient((request) async => _json({'error': 'invalid_credentials', 'message': 'incorrect email or password'}, 401));
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

    await tester.pumpWidget(_wrap(LoginScreen(authRepository: repo)));
    await tester.enterText(find.byType(TextField).first, 'amit@example.com');
    await tester.enterText(find.byType(TextField).last, 'wrong-password');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('incorrect email or password'), findsOneWidget);
  });

  testWidgets('the "create an account" link navigates to SignupScreen', (tester) async {
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: _InMemorySecureStore()),
    );

    await tester.pumpWidget(_wrap(LoginScreen(authRepository: repo)));
    await tester.tap(find.text('New to Pavio? Create an account'));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsOneWidget);
  });

  testWidgets('the "Forgot password?" link navigates to ForgotPasswordScreen', (tester) async {
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: _InMemorySecureStore()),
    );

    await tester.pumpWidget(_wrap(LoginScreen(authRepository: repo)));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  });
}
