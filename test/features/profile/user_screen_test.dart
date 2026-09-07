import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivasaos_tenant_app/core/api_client.dart';
import 'package:nivasaos_tenant_app/core/cache_store.dart';
import 'package:nivasaos_tenant_app/core/push_notifications.dart';
import 'package:nivasaos_tenant_app/core/session_store.dart';
import 'package:nivasaos_tenant_app/features/auth/auth_repository.dart';
import 'package:nivasaos_tenant_app/features/auth/login_screen.dart';
import 'package:nivasaos_tenant_app/features/profile/account_details_screen.dart';
import 'package:nivasaos_tenant_app/features/profile/app_feedback_screen.dart';
import 'package:nivasaos_tenant_app/features/profile/emergency_contacts_screen.dart';
import 'package:nivasaos_tenant_app/features/profile/legal_screens.dart';
import 'package:nivasaos_tenant_app/features/profile/notifications_screen.dart';
import 'package:nivasaos_tenant_app/features/profile/profile_repository.dart';
import 'package:nivasaos_tenant_app/features/profile/user_screen.dart';
import 'package:nivasaos_tenant_app/theme/nivasa_theme.dart';

// logout() awaits PushNotifications.unregister(), which calls Firebase.initializeApp() —
// unavailable in the widget-test environment. Same stub as the old settings_screen_test.dart.
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

class _InMemoryCacheStore implements CacheStore {
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
    MaterialApp(theme: NivasaTheme.light(), home: child);

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Map<String, dynamic> _profileJson({
  String language = 'en',
  String? propertyName = 'The Aire',
  String? propertyCity = 'Bengaluru',
  String? propertyAddress = '12 MG Road',
}) => {
  'tenant_id': 'tenant-1',
  'property_id': 'prop-1',
  'property_name': propertyName,
  'property_city': propertyCity,
  'property_address': propertyAddress,
  'name': 'Nijo George Payyappilly',
  'phone': '+919876543210',
  'email': 'nijo@example.com',
  'language': language,
  'status': 'active',
  'permanent_address': null,
  'emergency_contact_name': null,
  'emergency_contact_phone': null,
  'emergency_contact_relationship': null,
  'account_full_name': 'Nijo George Payyappilly',
  'account_email': 'nijo@nivasa.app',
};

Future<AuthRepository> _connectedAuth({http.Client? client}) async {
  final store = _InMemorySecureStore();
  await store.write('nivasaos.access_token', 'access-token');
  await store.write('nivasaos.refresh_token', 'refresh-token');
  await store.write(
    'nivasaos.access_token_expires_at',
    DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
  );
  await store.write(
    'nivasaos.user',
    jsonEncode({
      'user_id': 'account-1',
      'name': 'Nijo George Payyappilly',
      'role': 'tenant',
      'connected': true,
      'org_id': 'org-1',
      'property_id': 'prop-1',
      'tenant_id': 'tenant-1',
    }),
  );
  return AuthRepository(
    apiClient: client != null ? ApiClient(httpClient: client) : null,
    sessionStore: SessionStore(storage: store),
    pushNotifications: _NoopPushNotifications(),
  );
}

Future<AuthRepository> _unconnectedAuth({http.Client? client}) async {
  final store = _InMemorySecureStore();
  await store.write('nivasaos.access_token', 'access-token');
  await store.write('nivasaos.refresh_token', 'refresh-token');
  await store.write(
    'nivasaos.access_token_expires_at',
    DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
  );
  await store.write(
    'nivasaos.user',
    jsonEncode({
      'user_id': 'account-1',
      'name': 'Amit Kumar',
      'email': 'amit@example.com',
      'role': 'tenant',
      'connected': false,
    }),
  );
  return AuthRepository(
    apiClient: client != null ? ApiClient(httpClient: client) : null,
    sessionStore: SessionStore(storage: store),
    pushNotifications: _NoopPushNotifications(),
  );
}

Widget _userScreen({
  required AuthRepository auth,
  required http.Client client,
  CacheStore? cacheStore,
}) {
  final apiClient = ApiClient(httpClient: client);
  return UserScreen(
    authRepository: auth,
    profileRepository: ProfileRepository(apiClient: apiClient),
    cacheStore: cacheStore ?? _InMemoryCacheStore(),
  );
}

void main() {
  testWidgets('loads and displays name, property, and language', (
    tester,
  ) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me' &&
          request.method == 'GET') {
        return _json(_profileJson(), 200);
      }
      throw StateError(
        'unexpected request: ${request.method} ${request.url.path}',
      );
    });

    await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    expect(find.text('Nijo George Payyappilly'), findsOneWidget);
    expect(find.text('The Aire'), findsOneWidget);
    expect(find.text('Bengaluru'), findsOneWidget);
    expect(find.text('Language: English'), findsOneWidget);
    expect(find.text('Account Details'), findsOneWidget);
    expect(find.text('Emergency Contacts'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('App Feedback'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms & Conditions'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
  });

  testWidgets('expanding the property row reveals the full address', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json(_profileJson(), 200));

    await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    expect(find.text('12 MG Road'), findsNothing);
    await tester.tap(find.text('The Aire'));
    await tester.pumpAndSettle();
    expect(find.text('12 MG Road'), findsOneWidget);
  });

  testWidgets('tapping Account Details navigates to AccountDetailsScreen', (
    tester,
  ) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json(_profileJson(), 200));

    await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Account Details'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountDetailsScreen), findsOneWidget);
  });

  testWidgets(
    'tapping Emergency Contacts navigates to EmergencyContactsScreen',
    (tester) async {
      _useTallSurface(tester);
      final auth = await _connectedAuth();
      final client = MockClient((request) async => _json(_profileJson(), 200));

      await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Emergency Contacts'));
      await tester.pumpAndSettle();

      expect(find.byType(EmergencyContactsScreen), findsOneWidget);
    },
  );

  testWidgets('tapping Notifications navigates to NotificationsScreen', (
    tester,
  ) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json(_profileJson(), 200));

    await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('tapping App Feedback navigates to AppFeedbackScreen', (
    tester,
  ) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json(_profileJson(), 200));

    await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('App Feedback'));
    await tester.pumpAndSettle();

    expect(find.byType(AppFeedbackScreen), findsOneWidget);
  });

  testWidgets(
    'tapping Privacy Policy and Terms & Conditions navigates to the legal screens',
    (tester) async {
      _useTallSurface(tester);
      final auth = await _connectedAuth();
      final client = MockClient((request) async => _json(_profileJson(), 200));

      await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terms & Conditions'));
      await tester.pumpAndSettle();
      expect(find.byType(TermsScreen), findsOneWidget);
    },
  );

  testWidgets('picking a different language patches the profile', (
    tester,
  ) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    var patchedBody = <String, dynamic>{};
    final client = MockClient((request) async {
      if (request.url.path == '/api/tenants/v1/tenant/me' &&
          request.method == 'GET') {
        return _json(_profileJson(), 200);
      }
      if (request.url.path == '/api/tenants/v1/tenant/me' &&
          request.method == 'PATCH') {
        patchedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(_profileJson(language: 'ml'), 200);
      }
      throw StateError(
        'unexpected request: ${request.method} ${request.url.path}',
      );
    });

    await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Language:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Malayalam'));
    await tester.pumpAndSettle();

    expect(patchedBody['language'], 'ml');
    expect(find.text('Language: Malayalam'), findsOneWidget);
  });

  testWidgets(
    'signing out clears the session and navigates back to LoginScreen',
    (tester) async {
      _useTallSurface(tester);
      final auth = await _connectedAuth();
      final client = MockClient((request) async {
        if (request.url.path == '/api/tenants/v1/tenant/me' &&
            request.method == 'GET') {
          return _json(_profileJson(), 200);
        }
        if (request.url.path == '/api/auth/v1/logout') {
          return _json({'logged_out': true}, 200);
        }
        throw StateError(
          'unexpected request: ${request.method} ${request.url.path}',
        );
      });

      await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(await auth.currentSession(), isNull);
    },
  );

  testWidgets(
    'an unconnected renter sees a reduced account view instead of the missing_org_context error',
    (tester) async {
      _useTallSurface(tester);
      final auth = await _unconnectedAuth();
      // No request should be made at all — hitting tenant-service's tenant-self routes
      // pre-connection would 400 with missing_org_context (no org_id/tenant_id exists
      // yet), so the screen must skip the fetch entirely rather than surface that error.
      final client = MockClient(
        (request) async => throw StateError(
          'unexpected request: ${request.method} ${request.url.path}',
        ),
      );

      await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
      await tester.pumpAndSettle();

      expect(find.text('Amit Kumar'), findsOneWidget);
      expect(find.text('amit@example.com'), findsOneWidget);
      expect(
        find.textContaining('once your property manager adds you'),
        findsOneWidget,
      );
      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.text('X-Org-Id header is required'), findsNothing);
      expect(find.text('Account Details'), findsNothing);
      expect(find.text('Emergency Contacts'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets(
    'an unconnected renter can still sign out from the reduced account view',
    (tester) async {
      _useTallSurface(tester);
      final auth = await _unconnectedAuth();
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/v1/logout')
          return _json({'logged_out': true}, 200);
        throw StateError(
          'unexpected request: ${request.method} ${request.url.path}',
        );
      });

      await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(await auth.currentSession(), isNull);
    },
  );

  testWidgets('shows an error state when the fetch fails', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async =>
          _json({'error': 'internal_error', 'message': 'boom'}, 500),
    );

    await tester.pumpWidget(_wrap(_userScreen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows cached data with a stale banner when offline', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final cache = _InMemoryCacheStore();
    await cache.write(
      'profile',
      jsonEncode({
        'data': _profileJson(),
        'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String(),
      }),
    );
    final client = MockClient(
      (request) async => throw const SocketException('no route to host'),
    );

    await tester.pumpWidget(
      _wrap(_userScreen(auth: auth, client: client, cacheStore: cache)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nijo George Payyappilly'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });
}
