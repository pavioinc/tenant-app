import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivasaos_tenant_app/core/api_client.dart';
import 'package:nivasaos_tenant_app/core/push_notifications.dart';
import 'package:nivasaos_tenant_app/core/session_store.dart';
import 'package:nivasaos_tenant_app/features/auth/auth_repository.dart';
import 'package:nivasaos_tenant_app/features/auth/login_screen.dart';
import 'package:nivasaos_tenant_app/features/profile/settings_screen.dart';
import 'package:nivasaos_tenant_app/theme/nivasa_theme.dart';

// logout() awaits PushNotifications.unregister(), which calls Firebase.initializeApp()
// — unavailable in the widget-test environment (no real platform channels), and prone to
// hanging pumpAndSettle rather than throwing a catchable exception. Stub it out.
class _NoopPushNotifications extends PushNotifications {
  @override
  Future<void> register(String accessToken) async {}
  @override
  Future<void> unregister(String accessToken) async {}
}

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

Future<AuthRepository> _connectedAuth(http.Client client) async {
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
  return AuthRepository(
    apiClient: ApiClient(httpClient: client),
    sessionStore: SessionStore(storage: store),
    pushNotifications: _NoopPushNotifications(),
  );
}

void main() {
  testWidgets('logging out clears the session and navigates back to LoginScreen', (tester) async {
    final client = MockClient((request) async => _json({'logged_out': true}, 200));
    final auth = await _connectedAuth(client);

    await tester.pumpWidget(_wrap(SettingsScreen(authRepository: auth)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(await auth.currentSession(), isNull);
  });
}
