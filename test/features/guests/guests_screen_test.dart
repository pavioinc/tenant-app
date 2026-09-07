import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivasaos_tenant_app/core/api_client.dart';
import 'package:nivasaos_tenant_app/core/cache_store.dart';
import 'package:nivasaos_tenant_app/core/session_store.dart';
import 'package:nivasaos_tenant_app/features/auth/auth_repository.dart';
import 'package:nivasaos_tenant_app/features/guests/guests_repository.dart';
import 'package:nivasaos_tenant_app/features/guests/guests_screen.dart';
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

Future<AuthRepository> _connectedAuth() async {
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
      'connected': true,
      'org_id': 'org-1',
      'property_id': 'prop-1',
      'tenant_id': 'tenant-1',
    }),
  );
  return AuthRepository(sessionStore: SessionStore(storage: store));
}

/// GuestsScreen's populated list can push content past the default test surface.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('shows the empty state as a first screen (1g mock)', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'guests': []}, 200));

    await tester.pumpWidget(
      _wrap(
        GuestsScreen(
          authRepository: auth,
          guestsRepository: GuestsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Expecting someone?'), findsOneWidget);
    expect(
      find.text(
        "Add your visitor here and the front desk will know they're coming. Only you and your property manager can see this list.",
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.person_add_alt), findsOneWidget);
    // Only the empty-state's own action — no separate pinned bar duplicating it.
    expect(find.text('Add a guest'), findsOneWidget);
  });

  testWidgets('lists an expected guest not yet arrived', (tester) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async => _json({
        'guests': [
          {
            'guest_id': 'guest-1',
            'name': 'Priya Friend',
            'phone': '+919888888888',
            'visit_date': '2026-08-20',
            'notes': null,
            'status': 'expected',
          },
        ],
      }, 200),
    );

    await tester.pumpWidget(
      _wrap(
        GuestsScreen(
          authRepository: auth,
          guestsRepository: GuestsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Priya Friend'), findsOneWidget);
    expect(find.text('20 Aug 2026 · +919888888888'), findsOneWidget);
    expect(find.text('Not arrived yet'), findsOneWidget);
    // The initials avatar renders from the name — no separate name-parsing bug.
    expect(find.text('PF'), findsOneWidget);
  });

  testWidgets(
    'shows a guest who has arrived with the real check-in time (CLO-231)',
    (tester) async {
      _useTallSurface(tester);
      final auth = await _connectedAuth();
      final client = MockClient(
        (request) async => _json({
          'guests': [
            {
              'guest_id': 'guest-1',
              'name': 'Priya Friend',
              'phone': null,
              'visit_date': '2026-08-20',
              'notes': null,
              'status': 'arrived',
              'arrived_at': '2026-08-20T09:05:00.000Z',
            },
          ],
        }, 200),
      );

      await tester.pumpWidget(
        _wrap(
          GuestsScreen(
            authRepository: auth,
            guestsRepository: GuestsRepository(
              apiClient: ApiClient(httpClient: client),
            ),
            cacheStore: _InMemoryCacheStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Inside since'), findsOneWidget);
    },
  );

  testWidgets('deletes a guest', (tester) async {
    _useTallSurface(tester);
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
          'guests': [
            {
              'guest_id': 'guest-1',
              'name': 'Priya Friend',
              'phone': null,
              'visit_date': '2026-08-20',
              'notes': null,
              'status': 'expected',
            },
          ],
        }, 200);
      }
      return _json({'guests': []}, 200);
    });

    await tester.pumpWidget(
      _wrap(
        GuestsScreen(
          authRepository: auth,
          guestsRepository: GuestsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('Priya Friend'), findsNothing);
  });

  testWidgets('adding a guest from the pinned bar reloads the list', (
    tester,
  ) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    var posted = false;
    var listCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posted = true;
        return _json({
          'guest_id': 'guest-2',
          'name': 'New Friend',
          'visit_date': '2026-08-25',
          'status': 'expected',
        }, 201);
      }
      listCount += 1;
      if (listCount == 1) {
        return _json({
          'guests': [
            {
              'guest_id': 'guest-1',
              'name': 'Priya Friend',
              'phone': null,
              'visit_date': '2026-08-20',
              'notes': null,
              'status': 'expected',
            },
          ],
        }, 200);
      }
      return _json({
        'guests': [
          {
            'guest_id': 'guest-1',
            'name': 'Priya Friend',
            'phone': null,
            'visit_date': '2026-08-20',
            'notes': null,
            'status': 'expected',
          },
          {
            'guest_id': 'guest-2',
            'name': 'New Friend',
            'phone': null,
            'visit_date': '2026-08-25',
            'notes': null,
            'status': 'expected',
          },
        ],
      }, 200);
    });

    await tester.pumpWidget(
      _wrap(
        GuestsScreen(
          authRepository: auth,
          guestsRepository: GuestsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The pinned bar's own "Add a guest" — a populated list is not the empty state.
    await tester.tap(find.text('Add a guest'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'New Friend');
    await tester.tap(find.text('Pick a visit date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(posted, isTrue);
    expect(find.text('New Friend'), findsOneWidget);
  });

  testWidgets('shows cached data with a stale banner when offline', (
    tester,
  ) async {
    _useTallSurface(tester);
    final auth = await _connectedAuth();
    final cache = _InMemoryCacheStore();
    await cache.write(
      'guests',
      jsonEncode({
        'data': [
          {
            'guest_id': 'guest-1',
            'name': 'Priya Friend',
            'phone': '+919888888888',
            'visit_date': '2026-08-20',
            'notes': null,
            'status': 'expected',
          },
        ],
        'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String(),
      }),
    );
    final client = MockClient(
      (request) async => throw const SocketException('no route to host'),
    );

    await tester.pumpWidget(
      _wrap(
        GuestsScreen(
          authRepository: auth,
          guestsRepository: GuestsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Priya Friend'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });
}
