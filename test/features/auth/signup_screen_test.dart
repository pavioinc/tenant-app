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

const _strongPassword = 'Correct-Horse-1!';

Future<void> _fillRequiredFields(WidgetTester tester, {String password = _strongPassword}) async {
  await tester.enterText(find.widgetWithText(TextField, 'example@email.com'), 'amit@example.com');
  await tester.enterText(find.widgetWithText(TextField, 'John'), 'Amit');
  await tester.enterText(find.widgetWithText(TextField, 'Smith'), 'Kumar');
  await tester.enterText(find.widgetWithText(TextField, 'Enter your password'), password);
}

void main() {
  testWidgets('shows the lease-email banner and the password complexity hint', (tester) async {
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((request) async => _json({}, 500))),
      sessionStore: SessionStore(storage: _InMemorySecureStore()),
    );
    await tester.pumpWidget(_wrap(SignupScreen(authRepository: repo)));

    expect(find.textContaining('must use the email address associated with your lease'), findsOneWidget);
    expect(find.textContaining('1 lowercase letter, 1 uppercase letter, 1 number, and 1 special character'), findsOneWidget);
  });

  testWidgets('rejects an invalid email client-side without calling the network', (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return _json({}, 201);
    });
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

    await tester.pumpWidget(_wrap(SignupScreen(authRepository: repo)));
    await _fillRequiredFields(tester);
    await tester.enterText(find.widgetWithText(TextField, 'example@email.com'), 'not-an-email');
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pump();

    expect(called, isFalse);
    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('rejects a weak password client-side without calling the network', (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return _json({}, 201);
    });
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

    await tester.pumpWidget(_wrap(SignupScreen(authRepository: repo)));
    await _fillRequiredFields(tester, password: 'short');
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pump();

    expect(called, isFalse);
    expect(find.text('Password does not meet the requirements below'), findsOneWidget);
  });

  testWidgets('rejects a missing last name client-side', (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return _json({}, 201);
    });
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

    await tester.pumpWidget(_wrap(SignupScreen(authRepository: repo)));
    await tester.enterText(find.widgetWithText(TextField, 'example@email.com'), 'amit@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'John'), 'Amit');
    await tester.enterText(find.widgetWithText(TextField, 'Enter your password'), _strongPassword);
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pump();

    expect(called, isFalse);
    expect(find.text('Enter your last name'), findsOneWidget);
  });

  testWidgets('creates an unconnected account (no birthdate given) and navigates to HomeScreen', (tester) async {
    // HomeScreen silently re-checks connection status on load when unconnected (see
    // home_screen.dart's initState), so this mock also has to answer /refresh and
    // /tenant/me — not just /tenant/signup.
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/v1/tenant/signup') {
        expect(jsonDecode(request.body), {
          'first_name': 'Amit',
          'last_name': 'Kumar',
          'email': 'amit@example.com',
          'password': _strongPassword,
        });
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
    await _fillRequiredFields(tester);
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Almost there'), findsOneWidget);
  });

  testWidgets('surfaces email_taken from the server', (tester) async {
    final client = MockClient((request) async => _json({'error': 'email_taken', 'message': 'an account with this email already exists'}, 409));
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

    await tester.pumpWidget(_wrap(SignupScreen(authRepository: repo)));
    await _fillRequiredFields(tester);
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(find.text('an account with this email already exists'), findsOneWidget);
  });

  testWidgets('tapping "Already have an account? Log In" navigates without submitting', (tester) async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return _json({}, 201);
    });
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

    await tester.pumpWidget(_wrap(SignupScreen(authRepository: repo)));
    await tester.ensureVisible(find.textContaining('Already have an account?'));
    await tester.tap(find.textContaining('Already have an account?'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
