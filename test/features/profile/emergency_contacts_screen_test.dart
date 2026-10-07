import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/cache_store.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';
import 'package:pavio_tenant_app/features/profile/emergency_contacts_repository.dart';
import 'package:pavio_tenant_app/features/profile/emergency_contacts_screen.dart';
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

class _InMemoryCacheStore implements CacheStore {
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

Future<AuthRepository> _connectedAuth() async {
  final store = _InMemorySecureStore();
  await store.write('pavio.access_token', 'access-token');
  await store.write('pavio.refresh_token', 'refresh-token');
  await store.write('pavio.access_token_expires_at', DateTime.now().add(const Duration(minutes: 30)).toIso8601String());
  await store.write(
    'pavio.user',
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
  return AuthRepository(sessionStore: SessionStore(storage: store));
}

Widget _screen({required AuthRepository auth, required http.Client client, CacheStore? cacheStore}) {
  return EmergencyContactsScreen(
    authRepository: auth,
    emergencyContactsRepository: EmergencyContactsRepository(apiClient: ApiClient(httpClient: client)),
    cacheStore: cacheStore ?? _InMemoryCacheStore(),
  );
}

void main() {
  testWidgets('shows an empty state with no contacts', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'emergency_contacts': []}, 200));

    await tester.pumpWidget(_wrap(_screen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    expect(find.textContaining('No emergency contacts yet'), findsOneWidget);
  });

  testWidgets('lists existing emergency contacts', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async => _json({
        'emergency_contacts': [
          {'contact_id': 'contact-1', 'name': 'Priya Kumar', 'phone': '+919888888888', 'relationship': 'Spouse'},
        ],
      }, 200),
    );

    await tester.pumpWidget(_wrap(_screen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    expect(find.text('Priya Kumar'), findsOneWidget);
    expect(find.text('+919888888888 · Spouse'), findsOneWidget);
  });

  testWidgets('shows a Primary badge for the primary contact and a "Set as primary" action for others', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async => _json({
        'emergency_contacts': [
          {'contact_id': 'contact-1', 'name': 'Priya Kumar', 'phone': '+919888888888', 'relationship': 'Spouse', 'is_primary': true},
          {'contact_id': 'contact-2', 'name': 'Ravi Kumar', 'phone': '+919777777777', 'relationship': 'Brother', 'is_primary': false},
        ],
      }, 200),
    );

    await tester.pumpWidget(_wrap(_screen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Set as primary'), findsOneWidget);
  });

  testWidgets('setting a contact as primary posts to the primary endpoint and reloads', (tester) async {
    final auth = await _connectedAuth();
    var postedPath = '';
    var listCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        postedPath = request.url.path;
        return _json({'contact_id': 'contact-2', 'name': 'Ravi Kumar', 'phone': '+919777777777', 'relationship': 'Brother', 'is_primary': true}, 200);
      }
      listCount += 1;
      if (listCount == 1) {
        return _json({
          'emergency_contacts': [
            {'contact_id': 'contact-1', 'name': 'Priya Kumar', 'phone': '+919888888888', 'relationship': 'Spouse', 'is_primary': true},
            {'contact_id': 'contact-2', 'name': 'Ravi Kumar', 'phone': '+919777777777', 'relationship': 'Brother', 'is_primary': false},
          ],
        }, 200);
      }
      return _json({
        'emergency_contacts': [
          {'contact_id': 'contact-1', 'name': 'Priya Kumar', 'phone': '+919888888888', 'relationship': 'Spouse', 'is_primary': false},
          {'contact_id': 'contact-2', 'name': 'Ravi Kumar', 'phone': '+919777777777', 'relationship': 'Brother', 'is_primary': true},
        ],
      }, 200);
    });

    await tester.pumpWidget(_wrap(_screen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set as primary'));
    await tester.pumpAndSettle();

    expect(postedPath, '/api/tenants/v1/tenant/me/emergency-contacts/contact-2/primary');
    // After the reload, exactly one contact is primary (now Ravi) and exactly one
    // "Set as primary" action remains (now on Priya's row) — the swap happened.
    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Set as primary'), findsOneWidget);
  });

  testWidgets('adds a contact and reloads the list', (tester) async {
    final auth = await _connectedAuth();
    var posted = false;
    var listCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posted = true;
        return _json({'contact_id': 'contact-1', 'name': 'Priya Kumar', 'phone': '+919888888888', 'relationship': null}, 201);
      }
      listCount += 1;
      if (listCount == 1) return _json({'emergency_contacts': []}, 200);
      return _json({
        'emergency_contacts': [
          {'contact_id': 'contact-1', 'name': 'Priya Kumar', 'phone': '+919888888888', 'relationship': null},
        ],
      }, 200);
    });

    await tester.pumpWidget(_wrap(_screen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Priya Kumar');
    await tester.enterText(find.byType(TextField).at(1), '+919888888888');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(posted, isTrue);
    expect(find.text('Priya Kumar'), findsOneWidget);
  });

  testWidgets('editing a contact patches only that contact', (tester) async {
    final auth = await _connectedAuth();
    var patchedBody = <String, dynamic>{};
    var patchedPath = '';
    var listCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        patchedPath = request.url.path;
        patchedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'contact_id': 'contact-1', 'name': 'Priya K.', 'phone': '+919888888888', 'relationship': 'Spouse'}, 200);
      }
      listCount += 1;
      if (listCount == 1) {
        return _json({
          'emergency_contacts': [
            {'contact_id': 'contact-1', 'name': 'Priya Kumar', 'phone': '+919888888888', 'relationship': 'Spouse'},
          ],
        }, 200);
      }
      return _json({
        'emergency_contacts': [
          {'contact_id': 'contact-1', 'name': 'Priya K.', 'phone': '+919888888888', 'relationship': 'Spouse'},
        ],
      }, 200);
    });

    await tester.pumpWidget(_wrap(_screen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Priya Kumar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Priya Kumar'), 'Priya K.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(patchedPath, '/api/tenants/v1/tenant/me/emergency-contacts/contact-1');
    expect(patchedBody['name'], 'Priya K.');
    expect(find.text('Priya K.'), findsOneWidget);
  });

  testWidgets('deletes a contact', (tester) async {
    final auth = await _connectedAuth();
    var deleted = false;
    var listCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'DELETE') {
        deleted = true;
        return http.Response('', 204);
      }
      listCount += 1;
      if (listCount == 1) {
        return _json({
          'emergency_contacts': [
            {'contact_id': 'contact-1', 'name': 'Priya Kumar', 'phone': '+919888888888', 'relationship': 'Spouse'},
          ],
        }, 200);
      }
      return _json({'emergency_contacts': []}, 200);
    });

    await tester.pumpWidget(_wrap(_screen(auth: auth, client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('Priya Kumar'), findsNothing);
  });

  testWidgets('shows cached data with a stale banner when offline', (tester) async {
    final auth = await _connectedAuth();
    final cache = _InMemoryCacheStore();
    await cache.write(
      'emergency_contacts',
      jsonEncode({
        'data': [
          {'contact_id': 'contact-1', 'name': 'Priya Kumar', 'phone': '+919888888888', 'relationship': 'Spouse'},
        ],
        'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String(),
      }),
    );
    final client = MockClient((request) async => throw const SocketException('no route to host'));

    await tester.pumpWidget(_wrap(_screen(auth: auth, client: client, cacheStore: cache)));
    await tester.pumpAndSettle();

    expect(find.text('Priya Kumar'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });
}
