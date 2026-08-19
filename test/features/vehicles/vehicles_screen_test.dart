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
import 'package:nivasaos_tenant_app/features/vehicles/vehicles_repository.dart';
import 'package:nivasaos_tenant_app/features/vehicles/vehicles_screen.dart';
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
  testWidgets('shows an empty state with no vehicles', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'vehicles': []}, 200));

    await tester.pumpWidget(
      _wrap(
        VehiclesScreen(
          authRepository: auth,
          vehiclesRepository: VehiclesRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No vehicles yet'), findsOneWidget);
  });

  testWidgets('lists existing vehicles', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async => _json({
        'vehicles': [
          {'vehicle_id': 'vehicle-1', 'plate_number': 'KA01AB1234', 'vehicle_type': 'car', 'color': 'White'},
        ],
      }, 200),
    );

    await tester.pumpWidget(
      _wrap(
        VehiclesScreen(
          authRepository: auth,
          vehiclesRepository: VehiclesRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KA01AB1234'), findsOneWidget);
    expect(find.text('Car · White'), findsOneWidget);
  });

  testWidgets('adds a vehicle and reloads the list', (tester) async {
    final auth = await _connectedAuth();
    var posted = false;
    var listCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posted = true;
        return _json({'vehicle_id': 'vehicle-1', 'plate_number': 'KA01AB1234', 'vehicle_type': 'car', 'color': null}, 201);
      }
      listCount += 1;
      if (listCount == 1) return _json({'vehicles': []}, 200);
      return _json({
        'vehicles': [
          {'vehicle_id': 'vehicle-1', 'plate_number': 'KA01AB1234', 'vehicle_type': 'car', 'color': null},
        ],
      }, 200);
    });

    await tester.pumpWidget(
      _wrap(
        VehiclesScreen(
          authRepository: auth,
          vehiclesRepository: VehiclesRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add vehicle'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'KA01AB1234');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(posted, isTrue);
    expect(find.text('KA01AB1234'), findsOneWidget);
  });

  testWidgets('deletes a vehicle', (tester) async {
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
          'vehicles': [
            {'vehicle_id': 'vehicle-1', 'plate_number': 'KA01AB1234', 'vehicle_type': 'car', 'color': null},
          ],
        }, 200);
      }
      return _json({'vehicles': []}, 200);
    });

    await tester.pumpWidget(
      _wrap(
        VehiclesScreen(
          authRepository: auth,
          vehiclesRepository: VehiclesRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('KA01AB1234'), findsNothing);
  });

  testWidgets('shows cached data with a stale banner when offline', (tester) async {
    final auth = await _connectedAuth();
    final cache = _InMemoryCacheStore();
    await cache.write(
      'vehicles',
      jsonEncode({
        'data': [
          {'vehicle_id': 'vehicle-1', 'plate_number': 'KA01AB1234', 'vehicle_type': 'car', 'color': 'White'},
        ],
        'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String(),
      }),
    );
    final client = MockClient((request) async => throw const SocketException('no route to host'));

    await tester.pumpWidget(
      _wrap(
        VehiclesScreen(
          authRepository: auth,
          vehiclesRepository: VehiclesRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KA01AB1234'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });
}
