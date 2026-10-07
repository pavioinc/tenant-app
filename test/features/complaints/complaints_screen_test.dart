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
import 'package:pavio_tenant_app/features/complaints/complaint_detail_screen.dart';
import 'package:pavio_tenant_app/features/complaints/complaints_repository.dart';
import 'package:pavio_tenant_app/features/complaints/complaints_screen.dart';
import 'package:pavio_tenant_app/features/rental/rental_repository.dart';
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

http.Response _json(Map<String, dynamic> body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Widget _wrap(Widget child) =>
    MaterialApp(theme: PavioTheme.light(), home: child);

Future<AuthRepository> _connectedAuth() async {
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
      'connected': true,
      'org_id': 'org-1',
      'property_id': 'prop-1',
      'tenant_id': 'tenant-1',
    }),
  );
  return AuthRepository(sessionStore: SessionStore(storage: store));
}

const _rentalWithBed = {
  'tenant_id': 'tenant-1',
  'allocation': null,
  'bed': {'label': 'B', 'room_name': '204', 'floor_name': 'Floor 1'},
  'agreement': null,
};

/// Routes a fake client's responses by path — the screen now also calls the rental
/// endpoint (for the card subtitle's room name) alongside complaints.
http.Client _clientFor({
  Map<String, dynamic> complaints = const {'complaints': []},
  Map<String, dynamic>? notes,
  Map<String, dynamic>? postResponse,
}) {
  return MockClient((request) async {
    if (request.method == 'POST') {
      return _json(postResponse!, 201);
    }
    if (request.url.path.endsWith('/notes')) {
      return _json(notes ?? {'notes': []}, 200);
    }
    if (request.url.path.contains('billing-profile')) {
      return _json({'billing_profile': null}, 200);
    }
    if (request.url.path.endsWith('/rental')) {
      return _json(_rentalWithBed, 200);
    }
    return _json(complaints, 200);
  });
}

void main() {
  testWidgets('shows an empty state with no open requests', (tester) async {
    final auth = await _connectedAuth();

    await tester.pumpWidget(
      _wrap(
        ComplaintsScreen(
          authRepository: auth,
          complaintsRepository: ComplaintsRepository(
            apiClient: ApiClient(httpClient: _clientFor()),
          ),
          rentalRepository: RentalRepository(
            apiClient: ApiClient(httpClient: _clientFor()),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No open requests'), findsOneWidget);
    expect(find.text('Open · 0'), findsOneWidget);
    expect(find.text('Resolved · 0'), findsOneWidget);
  });

  testWidgets(
    'lists open complaints with a coloured spine, relative date, and room subtitle (1e mock)',
    (tester) async {
      final auth = await _connectedAuth();
      final client = _clientFor(
        complaints: {
          'complaints': [
            {
              'complaint_id': 'complaint-1',
              'category': 'Plumbing',
              'description': 'Dripping tap in the bathroom',
              'status': 'in_progress',
              'created_at': DateTime.now()
                  .subtract(const Duration(days: 6))
                  .toIso8601String(),
              'latest_note': {
                'author_type': 'manager',
                'author_name': 'Ravi',
                'body': 'Plumber visiting Thursday',
              },
            },
          ],
        },
      );

      await tester.pumpWidget(
        _wrap(
          ComplaintsScreen(
            authRepository: auth,
            complaintsRepository: ComplaintsRepository(
              apiClient: ApiClient(httpClient: client),
            ),
            rentalRepository: RentalRepository(
              apiClient: ApiClient(httpClient: client),
            ),
            cacheStore: _InMemoryCacheStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open · 1'), findsOneWidget);
      expect(find.text('Resolved · 0'), findsOneWidget);
      expect(find.text('Dripping tap in the bathroom'), findsOneWidget);
      expect(find.text('Plumbing · Room 204'), findsOneWidget);
      expect(find.text('6 days ago'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Ravi: Plumber visiting Thursday'), findsOneWidget);
    },
  );

  testWidgets('shows "No reply yet" when the complaint has no notes', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = _clientFor(
      complaints: {
        'complaints': [
          {
            'complaint_id': 'complaint-1',
            'category': 'Electrical',
            'description': 'Corridor light flickering',
            'status': 'open',
            'created_at': DateTime.now()
                .subtract(const Duration(days: 9))
                .toIso8601String(),
            'latest_note': null,
          },
        ],
      },
    );

    await tester.pumpWidget(
      _wrap(
        ComplaintsScreen(
          authRepository: auth,
          complaintsRepository: ComplaintsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          rentalRepository: RentalRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No reply yet'), findsOneWidget);
    expect(find.text('9 days ago'), findsOneWidget);
  });

  testWidgets('Resolved tab shows only resolved complaints', (tester) async {
    final auth = await _connectedAuth();
    final client = _clientFor(
      complaints: {
        'complaints': [
          {
            'complaint_id': 'complaint-1',
            'category': 'Plumbing',
            'description': 'Dripping tap',
            'status': 'open',
            'created_at': '2026-08-20',
            'latest_note': null,
          },
          {
            'complaint_id': 'complaint-2',
            'category': 'Cleaning',
            'description': 'Common bathroom not cleaned',
            'status': 'resolved',
            'created_at': '2026-08-11',
            'latest_note': null,
          },
        ],
      },
    );

    await tester.pumpWidget(
      _wrap(
        ComplaintsScreen(
          authRepository: auth,
          complaintsRepository: ComplaintsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          rentalRepository: RentalRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dripping tap'), findsOneWidget);
    expect(find.text('Common bathroom not cleaned'), findsNothing);

    await tester.tap(find.text('Resolved · 1'));
    await tester.pumpAndSettle();

    expect(find.text('Dripping tap'), findsNothing);
    expect(find.text('Common bathroom not cleaned'), findsOneWidget);
  });

  testWidgets('submits a new maintenance request and reloads the list', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    var posted = false;
    var listCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posted = true;
        return _json({
          'complaint_id': 'complaint-2',
          'category': 'Plumbing',
          'description': 'Leaky tap',
          'status': 'open',
          'created_at': '2026-08-14',
        }, 201);
      }
      if (request.url.path.endsWith('/rental'))
        return _json(_rentalWithBed, 200);
      listCount += 1;
      if (listCount == 1) return _json({'complaints': []}, 200);
      return _json({
        'complaints': [
          {
            'complaint_id': 'complaint-2',
            'category': 'Plumbing',
            'description': 'Leaky tap',
            'status': 'open',
            'created_at': '2026-08-14',
            'latest_note': null,
          },
        ],
      }, 200);
    });

    await tester.pumpWidget(
      _wrap(
        ComplaintsScreen(
          authRepository: auth,
          complaintsRepository: ComplaintsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          rentalRepository: RentalRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New request'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Leaky tap');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(posted, isTrue);
    expect(find.text('Leaky tap'), findsOneWidget);
  });

  testWidgets('shows cached data with a stale banner when offline', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final cache = _InMemoryCacheStore();
    await cache.write(
      'complaints',
      jsonEncode({
        'data': [
          {
            'complaint_id': 'complaint-1',
            'category': 'Electrical',
            'description': 'Fan not working',
            'status': 'open',
            'created_at': '2026-08-14',
            'latest_note': null,
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
        ComplaintsScreen(
          authRepository: auth,
          complaintsRepository: ComplaintsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          rentalRepository: RentalRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fan not working'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });

  testWidgets('tapping a complaint card navigates to ComplaintDetailScreen', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = _clientFor(
      complaints: {
        'complaints': [
          {
            'complaint_id': 'complaint-1',
            'category': 'Electrical',
            'description': 'Fan not working',
            'status': 'open',
            'created_at': '2026-08-14',
            'latest_note': null,
          },
        ],
      },
    );

    await tester.pumpWidget(
      _wrap(
        ComplaintsScreen(
          authRepository: auth,
          complaintsRepository: ComplaintsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          rentalRepository: RentalRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fan not working'));
    await tester.pumpAndSettle();

    expect(find.byType(ComplaintDetailScreen), findsOneWidget);
  });
}
