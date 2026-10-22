import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';
import 'package:pavio_tenant_app/features/home/home_screen.dart';
import 'package:pavio_tenant_app/features/profile/user_screen.dart';
import 'package:pavio_tenant_app/features/lease/lease_screen.dart';
import 'package:pavio_tenant_app/features/complaints/complaints_screen.dart';
import 'package:pavio_tenant_app/features/contacts/contacts_screen.dart';
import 'package:pavio_tenant_app/features/vehicles/vehicles_screen.dart';
import 'package:pavio_tenant_app/features/guests/guests_screen.dart';
import 'package:pavio_tenant_app/features/documents/documents_screen.dart';
import 'package:pavio_tenant_app/features/payments/payments_screen.dart';
import 'package:pavio_tenant_app/features/shell/main_shell.dart';
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

http.Response _json(Map<String, dynamic> body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Widget _wrap(Widget child) =>
    MaterialApp(theme: PavioTheme.light(), home: child);

Future<_InMemorySecureStore> _storeWithSession({
  required bool connected,
  String? email,
}) async {
  final store = _InMemorySecureStore();
  await store.write('pavio.access_token', 'access-token');
  await store.write('pavio.refresh_token', 'refresh-token');
  await store.write(
    'pavio.access_token_expires_at',
    DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
  );
  await store.write(
    'pavio.user',
    jsonEncode({
      'user_id': 'account-1',
      'name': 'Amit Kumar',
      'role': 'tenant',
      'connected': connected,
      'email': ?email,
      if (connected) 'org_id': 'org-1',
      if (connected) 'property_id': 'prop-1',
      if (connected) 'tenant_id': 'tenant-1',
    }),
  );
  return store;
}

/// The default test surface is too short to lay out the connect-prompt banner alongside
/// the locked-pills row at once — ListView only builds elements for children within (or
/// near) the viewport, so an unscrolled findsNWidgets undercounts. Widen it instead of
/// scrolling, since these tests care about layout, not scroll behavior.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Taps a bottom-nav destination by its label. All four tabs are built at once (inside
/// MainShell's IndexedStack), so plain `find.text(label)` would also match that tab's own
/// on-screen content if it happens to repeat the label — this scopes the tap to the
/// NavigationBar specifically.
Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
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
      expect(find.byType(MainShell), findsOneWidget);
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

  group('connected renter — bottom-tab shell', () {
    AuthRepository buildRepo(_InMemorySecureStore store) => AuthRepository(
      apiClient: ApiClient(httpClient: MockClient((_) async => _json({}, 200))),
      sessionStore: SessionStore(storage: store),
    );

    testWidgets(
      'a connected renter sees the 4-tab shell instead of the almost-there card',
      (tester) async {
        _useTallSurface(tester);
        final store = await _storeWithSession(connected: true);
        final repo = buildRepo(store);

        await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
        await tester.pumpAndSettle();

        expect(find.text('Almost there'), findsNothing);
        expect(find.byType(MainShell), findsOneWidget);
        final nav = find.byType(NavigationBar);
        expect(find.descendant(of: nav, matching: find.text('Home')), findsOneWidget);
        expect(find.descendant(of: nav, matching: find.text('Pay')), findsOneWidget);
        expect(find.descendant(of: nav, matching: find.text('Help')), findsOneWidget);
        expect(find.descendant(of: nav, matching: find.text('Me')), findsOneWidget);
      },
    );

    testWidgets('tapping Pay/Help/Me switches the visible tab, Home switches back', (
      tester,
    ) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(connected: true);
      final repo = buildRepo(store);

      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      IndexedStack stack() => tester.widget(find.byType(IndexedStack));

      expect(stack().index, 0);

      await _tapTab(tester, 'Pay');
      expect(stack().index, 1);
      expect(find.byType(PaymentsScreen), findsOneWidget);

      await _tapTab(tester, 'Help');
      expect(stack().index, 2);
      expect(find.byType(ComplaintsScreen), findsOneWidget);

      await _tapTab(tester, 'Me');
      expect(stack().index, 3);

      await _tapTab(tester, 'Home');
      expect(stack().index, 0);
    });

    Future<void> expectMeTabReaches(
      WidgetTester tester,
      String label,
      Type screenType,
    ) async {
      _useTallSurface(tester);
      final store = await _storeWithSession(connected: true);
      final repo = buildRepo(store);
      await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
      await tester.pumpAndSettle();

      await _tapTab(tester, 'Me');
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(find.byType(screenType), findsOneWidget, reason: label);
    }

    testWidgets('from the Me tab, a connected renter reaches Lease', (
      tester,
    ) async {
      await expectMeTabReaches(tester, 'Lease', LeaseScreen);
    });

    testWidgets('from the Me tab, a connected renter reaches Documents', (
      tester,
    ) async {
      await expectMeTabReaches(tester, 'Documents', DocumentsScreen);
    });

    testWidgets('from the Me tab, a connected renter reaches Guests', (
      tester,
    ) async {
      await expectMeTabReaches(tester, 'Guests', GuestsScreen);
    });

    testWidgets('from the Me tab, a connected renter reaches Vehicles', (
      tester,
    ) async {
      await expectMeTabReaches(tester, 'Vehicles', VehiclesScreen);
    });

    testWidgets('from the Me tab, a connected renter reaches Contacts', (
      tester,
    ) async {
      await expectMeTabReaches(tester, 'Contacts', ContactsScreen);
    });

    testWidgets(
      'a connected renter has no header person icon, and reaches UserScreen via the Me tab\'s "Your account" row',
      (tester) async {
        _useTallSurface(tester);
        final store = await _storeWithSession(connected: true);
        final repo = buildRepo(store);

        await tester.pumpWidget(_wrap(HomeScreen(authRepository: repo)));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('user-menu-button')), findsNothing);

        await _tapTab(tester, 'Me');
        await tester.tap(find.text('Your account'));
        await tester.pumpAndSettle();

        expect(find.byType(UserScreen), findsOneWidget);
      },
    );
  });
}
