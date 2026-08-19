import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivasaos_tenant_app/core/api_client.dart';
import 'package:nivasaos_tenant_app/core/session_store.dart';
import 'package:nivasaos_tenant_app/features/auth/auth_repository.dart';
import 'package:nivasaos_tenant_app/features/auth/signup_screen.dart';
import 'package:nivasaos_tenant_app/features/home/home_screen.dart';
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

http.Response _json(Map<String, dynamic> body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Widget _wrap(Widget child) => MaterialApp(theme: NivasaTheme.light(), home: child);

void main() {
  testWidgets('rejects a weak password client-side without calling the network', (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return _json({}, 201);
    });
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

    await tester.pumpWidget(_wrap(SignupScreen(authRepository: repo)));
    await tester.enterText(find.widgetWithText(TextField, 'Amit Kumar'), 'Amit Kumar');
    await tester.enterText(find.widgetWithText(TextField, 'you@example.com'), 'amit@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'At least 8 characters'), 'short');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(called, isFalse);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
  });

  testWidgets('creates an unconnected account and navigates to HomeScreen', (tester) async {
    // HomeScreen silently re-checks connection status on load when unconnected (see
    // home_screen.dart's initState), so this mock also has to answer /refresh and
    // /tenant/me — not just /tenant/signup.
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/v1/tenant/signup') {
        expect(jsonDecode(request.body), {'full_name': 'Amit Kumar', 'email': 'amit@example.com', 'password': 'correct-horse-battery-staple'});
        return _json({
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'expires_at': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
          'user': {'user_id': 'account-1', 'name': 'Amit Kumar', 'role': 'tenant', 'connected': false},
        }, 201);
      }
      if (request.url.path == '/api/auth/v1/refresh') {
        return _json({
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'expires_at': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
        }, 200);
      }
      if (request.url.path == '/api/auth/v1/tenant/me') {
        return _json({'user_id': 'account-1', 'name': 'Amit Kumar', 'role': 'tenant', 'connected': false}, 200);
      }
      throw StateError('unexpected request: ${request.url.path}');
    });
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

    await tester.pumpWidget(_wrap(SignupScreen(authRepository: repo)));
    await tester.enterText(find.widgetWithText(TextField, 'Amit Kumar'), 'Amit Kumar');
    await tester.enterText(find.widgetWithText(TextField, 'you@example.com'), 'amit@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'At least 8 characters'), 'correct-horse-battery-staple');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Connect with your property manager'), findsOneWidget);
  });

  testWidgets('surfaces email_taken from the server', (tester) async {
    final client = MockClient((request) async => _json({'error': 'email_taken', 'message': 'an account with this email already exists'}, 409));
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

    await tester.pumpWidget(_wrap(SignupScreen(authRepository: repo)));
    await tester.enterText(find.widgetWithText(TextField, 'Amit Kumar'), 'Amit Kumar');
    await tester.enterText(find.widgetWithText(TextField, 'you@example.com'), 'amit@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'At least 8 characters'), 'correct-horse-battery-staple');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('an account with this email already exists'), findsOneWidget);
  });
}
