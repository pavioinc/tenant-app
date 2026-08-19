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

http.Response _json(Map<String, dynamic> body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Widget _wrap(Widget child) => MaterialApp(theme: NivasaTheme.light(), home: child);

Future<AuthRepository> _connectedAuth() async {
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
  return AuthRepository(sessionStore: SessionStore(storage: store));
}

void main() {
  testWidgets('shows an empty state with no expected guests', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'guests': []}, 200));

    await tester.pumpWidget(
      _wrap(
        GuestsScreen(
          authRepository: auth,
          guestsRepository: GuestsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No expected guests yet'), findsOneWidget);
  });

  testWidgets('lists existing expected guests', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async => _json({
        'guests': [
          {'guest_id': 'guest-1', 'name': 'Priya Friend', 'phone': '+919888888888', 'visit_date': '2026-08-20', 'notes': null},
        ],
      }, 200),
    );

    await tester.pumpWidget(
      _wrap(
        GuestsScreen(
          authRepository: auth,
          guestsRepository: GuestsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Priya Friend'), findsOneWidget);
    expect(find.text('2026-08-20 · +919888888888'), findsOneWidget);
  });

  testWidgets('deletes a guest', (tester) async {
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
            {'guest_id': 'guest-1', 'name': 'Priya Friend', 'phone': null, 'visit_date': '2026-08-20', 'notes': null},
          ],
        }, 200);
      }
      return _json({'guests': []}, 200);
    });

    await tester.pumpWidget(
      _wrap(
        GuestsScreen(
          authRepository: auth,
          guestsRepository: GuestsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('Priya Friend'), findsNothing);
  });

  testWidgets('shows cached data with a stale banner when offline', (tester) async {
    final auth = await _connectedAuth();
    final cache = _InMemoryCacheStore();
    await cache.write(
      'guests',
      jsonEncode({
        'data': [
          {'guest_id': 'guest-1', 'name': 'Priya Friend', 'phone': '+919888888888', 'visit_date': '2026-08-20', 'notes': null},
        ],
        'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String(),
      }),
    );
    final client = MockClient((request) async => throw const SocketException('no route to host'));

    await tester.pumpWidget(
      _wrap(
        GuestsScreen(
          authRepository: auth,
          guestsRepository: GuestsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Priya Friend'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });
}
