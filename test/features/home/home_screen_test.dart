import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivasaos_tenant_app/core/api_client.dart';
import 'package:nivasaos_tenant_app/core/session_store.dart';
import 'package:nivasaos_tenant_app/features/auth/auth_repository.dart';
import 'package:nivasaos_tenant_app/features/auth/login_screen.dart';
import 'package:nivasaos_tenant_app/features/home/home_screen.dart';
import 'package:nivasaos_tenant_app/features/profile/profile_screen.dart';
import 'package:nivasaos_tenant_app/features/rental/rental_screen.dart';
import 'package:nivasaos_tenant_app/features/renewal/renewal_screen.dart';
import 'package:nivasaos_tenant_app/features/complaints/complaints_screen.dart';
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

Future<_InMemorySecureStore> _storeWithSession({required bool connected}) async {
  final store = _InMemorySecureStore();
  await store.write('nivasaos.access_token', 'access-token');
  await store.write('nivasaos.refresh_token', 'refresh-token');
  await store.write(
    'nivasaos.user',
    jsonEncode({
      'user_id': 'account-1',
      'name': 'Amit Kumar',
      'role': 'tenant',
      'connected': connected,
      if (connected) 'org_id': 'org-1',
      if (connected) 'property_id': 'prop-1',
      if (connected) 'tenant_id': 'tenant-1',
    }),
  );
  return store;
}

/// The default test surface is too short to lay out the connect-prompt banner plus all 5
/// menu tiles at once — ListView only builds elements for children within (or near) the
/// viewport, so an unscrolled findsNWidgets(5) undercounts. Widen it instead of scrolling,
/// since these tests care about layout, not scroll behavior.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('shows the connect prompt and locked menu for an unconnected renter, silently re-checking on load', (tester) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: false);
    var refreshCalled = false;
    var meCalled = false;
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/v1/refresh') {
        refreshCalled = true;
        return _json({'access_token': 'new-access', 'refresh_token': 'new-refresh'}, 200);
      }
      if (request.url.path == '/api/auth/v1/tenant/me') {
        meCalled = true;
        return _json({'user_id': 'account-1', 'name': 'Amit Kumar', 'role': 'tenant', 'connected': false}, 200);
      }
      throw StateError('unexpected request: ${request.url.path}');
    });
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: store));

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();

    expect(refreshCalled, isTrue);
    expect(meCalled, isTrue);
    expect(find.text('Connect with your property manager'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(5));

    await tester.tap(find.text('Pay rent'));
    await tester.pump();
    expect(find.textContaining('Connect with your property manager first'), findsOneWidget);
  });

  testWidgets('reflects a connection picked up during the silent check without user action', (tester) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: false);
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/v1/refresh') {
        return _json({'access_token': 'new-access', 'refresh_token': 'new-refresh'}, 200);
      }
      if (request.url.path == '/api/auth/v1/tenant/me') {
        return _json({
          'user_id': 'account-1',
          'name': 'Amit Kumar',
          'role': 'tenant',
          'connected': true,
          'org_id': 'org-1',
          'property_id': 'prop-1',
          'tenant_id': 'tenant-1',
        }, 200);
      }
      throw StateError('unexpected request: ${request.url.path}');
    });
    final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: store));

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('Connect with your property manager'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('a connected renter sees no connect prompt and menu items say "coming soon"', (tester) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: true);
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: store),
    );

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('Connect with your property manager'), findsNothing);

    await tester.tap(find.text('Pay rent'));
    await tester.pump();
    expect(find.text('Pay rent is coming soon'), findsOneWidget);
  });

  testWidgets('a connected renter tapping My rental navigates to RentalScreen', (tester) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: true);
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: store),
    );

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My rental'));
    // Same reasoning as the Profile navigation test below — RentalScreen's own fetch uses
    // a real ApiClient, but flutter_test synthesizes a 400 for any unmocked HttpClient
    // call rather than making a real network request, so settling is safe.
    await tester.pumpAndSettle();

    expect(find.byType(RentalScreen), findsOneWidget);
  });

  testWidgets('a connected renter tapping Complaints navigates to ComplaintsScreen', (tester) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: true);
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: store),
    );

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Complaints'));
    await tester.pumpAndSettle();

    expect(find.byType(ComplaintsScreen), findsOneWidget);
  });

  testWidgets('a connected renter tapping Renewal navigates to RenewalScreen', (tester) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: true);
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: store),
    );

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Renewal'));
    // Same reasoning as the other navigation-only tests — RenewalScreen's own fetches use
    // a real ApiClient; flutter_test synthesizes a 400 for any unmocked call.
    await tester.pumpAndSettle();

    expect(find.byType(RenewalScreen), findsOneWidget);
  });

  testWidgets('a connected renter tapping Profile navigates to ProfileScreen', (tester) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: true);
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: store),
    );

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    // ProfileScreen's own data fetch uses a real ApiClient (HomeScreen only passes it an
    // AuthRepository, not a fake ProfileRepository) — safe to settle anyway, since
    // flutter_test's TestWidgetsFlutterBinding intercepts dart:io's HttpClient globally
    // and synthesizes a 400 for anything not explicitly mocked, rather than making a real
    // network call. This only asserts the navigation itself happened.
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('logout navigates back to LoginScreen', (tester) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: true);
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({'logged_out': true}, 200))),
      sessionStore: SessionStore(storage: store),
    );

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
