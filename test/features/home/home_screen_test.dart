import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivasaos_tenant_app/core/api_client.dart';
import 'package:nivasaos_tenant_app/core/session_store.dart';
import 'package:nivasaos_tenant_app/features/auth/auth_repository.dart';
import 'package:nivasaos_tenant_app/features/home/home_screen.dart';
import 'package:nivasaos_tenant_app/features/profile/user_screen.dart';
import 'package:nivasaos_tenant_app/features/lease/lease_screen.dart';
import 'package:nivasaos_tenant_app/features/complaints/complaints_screen.dart';
import 'package:nivasaos_tenant_app/features/contacts/contacts_screen.dart';
import 'package:nivasaos_tenant_app/features/vehicles/vehicles_screen.dart';
import 'package:nivasaos_tenant_app/features/guests/guests_screen.dart';
import 'package:nivasaos_tenant_app/features/documents/documents_screen.dart';
import 'package:nivasaos_tenant_app/features/payments/payments_screen.dart';
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

http.Response _json(Map<String, dynamic> body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Widget _wrap(Widget child) =>
    MaterialApp(theme: NivasaTheme.light(), home: child);

Future<_InMemorySecureStore> _storeWithSession({
  required bool connected,
  String? email,
}) async {
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
      'role': 'tenant',
      'connected': connected,
      if (email != null) 'email': email,
      if (connected) 'org_id': 'org-1',
      if (connected) 'property_id': 'prop-1',
      if (connected) 'tenant_id': 'tenant-1',
    }),
  );
  return store;
}

/// The default test surface is too short to lay out the connect-prompt banner, the
/// payment banner, and the full 7-tile grid at once — ListView only builds elements for
/// children within (or near) the viewport, so an unscrolled findsNWidgets undercounts.
/// Widen it instead of scrolling, since these tests care about layout, not scroll
/// behavior.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'shows the almost-there card with locked pills for an unconnected renter, silently re-checking on load',
    (tester) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(connected: false);
      var refreshCalled = false;
      var meCalled = false;
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/v1/refresh') {
          refreshCalled = true;
          return _json({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'expires_at': DateTime.now()
                .add(const Duration(minutes: 30))
                .toIso8601String(),
          }, 200);
        }
        if (request.url.path == '/api/auth/v1/tenant/me') {
          meCalled = true;
          return _json({
            'user_id': 'account-1',
            'name': 'Amit Kumar',
            'role': 'tenant',
            'connected': false,
          }, 200);
        }
        throw StateError('unexpected request: ${request.url.path}');
      });
      final repo = AuthRepository(
        apiClient: ApiClient(httpClient: client),
        sessionStore: SessionStore(storage: store),
      );

      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      expect(refreshCalled, isTrue);
      expect(meCalled, isTrue);
      expect(find.text('Almost there'), findsOneWidget);
      // The 7 locked areas render as chips, not tappable tiles — no grid, no lock icon.
      expect(find.text('Maintenance'), findsOneWidget);
      expect(find.text('Pay Rent'), findsNothing);
      expect(find.byType(GridView), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
    },
  );

  testWidgets(
    'the almost-there card (1n mock) greets by first name and bolds the real email, with a working copy action',
    (tester) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(
        connected: false,
        email: 'amit@example.com',
      );
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/v1/refresh') {
          return _json({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'expires_at': DateTime.now()
                .add(const Duration(minutes: 30))
                .toIso8601String(),
          }, 200);
        }
        if (request.url.path == '/api/auth/v1/tenant/me') {
          return _json({
            'user_id': 'account-1',
            'name': 'Amit Kumar',
            'email': 'amit@example.com',
            'role': 'tenant',
            'connected': false,
          }, 200);
        }
        throw StateError('unexpected request: ${request.url.path}');
      });
      final repo = AuthRepository(
        apiClient: ApiClient(httpClient: client),
        sessionStore: SessionStore(storage: store),
      );

      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      // First-name-only greeting in the locked state, not the full "Amit Kumar".
      expect(find.text('Amit'), findsOneWidget);
      expect(find.text('Amit Kumar'), findsNothing);
      expect(find.textContaining('amit@example.com'), findsOneWidget);
      expect(find.text('Copy my email address'), findsOneWidget);

      await tester.tap(find.text('Copy my email address'));
      await tester.pumpAndSettle();

      expect(copiedText, 'amit@example.com');
      expect(find.text('Email address copied'), findsOneWidget);
    },
  );

  testWidgets(
    'reflects a connection picked up during the silent check without user action',
    (tester) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(connected: false);
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/v1/refresh') {
          return _json({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'expires_at': DateTime.now()
                .add(const Duration(minutes: 30))
                .toIso8601String(),
          }, 200);
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
      final repo = AuthRepository(
        apiClient: ApiClient(httpClient: client),
        sessionStore: SessionStore(storage: store),
      );

      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      expect(find.text('Almost there'), findsNothing);
    },
  );

  testWidgets('a connected renter sees no almost-there card', (tester) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: true);
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: store),
    );

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('Almost there'), findsNothing);
  });

  testWidgets('a connected renter tapping Payments navigates to PaymentsScreen', (
    tester,
  ) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: true);
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: store),
    );

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Payments'));
    // Same reasoning as the other navigation-only tests — PaymentsScreen's own fetch
    // uses a real ApiClient; flutter_test synthesizes a 400 for any unmocked call.
    await tester.pumpAndSettle();

    expect(find.byType(PaymentsScreen), findsOneWidget);
  });

  testWidgets(
    'the resident hub and everything-else list stay hidden entirely for an unconnected renter',
    (tester) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(connected: false);
      final repo = AuthRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async => _json({}, 200)),
        ),
        sessionStore: SessionStore(storage: store),
      );

      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      expect(find.text('Resident Hub'), findsNothing);
      expect(find.text('Everything else'), findsNothing);
    },
  );

  testWidgets('a connected renter tapping Lease navigates to LeaseScreen', (
    tester,
  ) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: true);
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: store),
    );

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lease'));
    // Same reasoning as the Profile navigation test below — LeaseScreen's own fetch uses
    // a real ApiClient, but flutter_test synthesizes a 400 for any unmocked HttpClient
    // call rather than making a real network request, so settling is safe.
    await tester.pumpAndSettle();

    expect(find.byType(LeaseScreen), findsOneWidget);
  });

  testWidgets(
    'a connected renter tapping Contacts navigates to ContactsScreen',
    (tester) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(connected: true);
      final repo = AuthRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async => _json({}, 200)),
        ),
        sessionStore: SessionStore(storage: store),
      );

      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Contacts'));
      await tester.pumpAndSettle();

      expect(find.byType(ContactsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'a connected renter tapping Vehicles navigates to VehiclesScreen',
    (tester) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(connected: true);
      final repo = AuthRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async => _json({}, 200)),
        ),
        sessionStore: SessionStore(storage: store),
      );

      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vehicles'));
      await tester.pumpAndSettle();

      expect(find.byType(VehiclesScreen), findsOneWidget);
    },
  );

  testWidgets('a connected renter tapping Guests navigates to GuestsScreen', (
    tester,
  ) async {
    _useTallSurface(tester);
    final store = await _storeWithSession(connected: true);
    final repo = AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: store),
    );

    await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guests'));
    await tester.pumpAndSettle();

    expect(find.byType(GuestsScreen), findsOneWidget);
  });

  testWidgets(
    'a connected renter tapping Documents navigates to DocumentsScreen',
    (tester) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(connected: true);
      final repo = AuthRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async => _json({}, 200)),
        ),
        sessionStore: SessionStore(storage: store),
      );

      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'a connected renter tapping Maintenance navigates to ComplaintsScreen',
    (tester) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(connected: true);
      final repo = AuthRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async => _json({}, 200)),
        ),
        sessionStore: SessionStore(storage: store),
      );

      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Maintenance'));
      await tester.pumpAndSettle();

      expect(find.byType(ComplaintsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'an unconnected renter tapping the header person icon navigates to UserScreen',
    (tester) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(connected: false);
      final repo = AuthRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async => _json({}, 200)),
        ),
        sessionStore: SessionStore(storage: store),
      );

      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('user-menu-button')));
      // UserScreen's own data fetch uses a real ApiClient (HomeScreen only passes it an
      // AuthRepository, not a fake ProfileRepository) — safe to settle anyway, since
      // flutter_test's TestWidgetsFlutterBinding intercepts dart:io's HttpClient globally
      // and synthesizes a 400 for anything not explicitly mocked, rather than making a real
      // network call. This only asserts the navigation itself happened.
      await tester.pumpAndSettle();

      expect(find.byType(UserScreen), findsOneWidget);
    },
  );

  testWidgets(
    'a connected renter has no header person icon, and reaches UserScreen via "Your account" instead',
    (tester) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(connected: true);
      final repo = AuthRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async => _json({}, 200)),
        ),
        sessionStore: SessionStore(storage: store),
      );

      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('user-menu-button')), findsNothing);

      await tester.tap(find.text('Your account'));
      await tester.pumpAndSettle();

      expect(find.byType(UserScreen), findsOneWidget);
    },
  );
}
