import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivasaos_tenant_app/core/api_client.dart';
import 'package:nivasaos_tenant_app/core/cache_store.dart';
import 'package:nivasaos_tenant_app/core/session_store.dart';
import 'package:nivasaos_tenant_app/core/url_opener.dart';
import 'package:nivasaos_tenant_app/features/auth/auth_repository.dart';
import 'package:nivasaos_tenant_app/features/contacts/contacts_repository.dart';
import 'package:nivasaos_tenant_app/features/contacts/contacts_screen.dart';
import 'package:nivasaos_tenant_app/theme/nivasa_theme.dart';

class _FakeUrlOpener implements UrlOpener {
  _FakeUrlOpener({this.result = true});
  final bool result;
  String? lastUrl;

  @override
  Future<bool> open(String url) async {
    lastUrl = url;
    return result;
  }
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
  testWidgets('shows an empty state with no contacts', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'contacts': []}, 200));

    await tester.pumpWidget(
      _wrap(
        ContactsScreen(
          authRepository: auth,
          contactsRepository: ContactsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No contacts on file yet'), findsOneWidget);
  });

  testWidgets('lists the org\'s managers and owners', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async => _json({
        'contacts': [
          {'name': 'Asha Manager', 'email': 'asha@example.com', 'phone': '+919876500000', 'role': 'manager'},
        ],
      }, 200),
    );

    await tester.pumpWidget(
      _wrap(
        ContactsScreen(
          authRepository: auth,
          contactsRepository: ContactsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Asha Manager'), findsOneWidget);
    expect(find.text('Manager'), findsOneWidget);
    expect(find.text('+919876500000'), findsOneWidget);
    expect(find.text('asha@example.com'), findsOneWidget);
  });

  testWidgets('shows an error state when the fetch fails', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'error': 'not_found', 'message': 'not connected to a property yet'}, 404));

    await tester.pumpWidget(
      _wrap(
        ContactsScreen(
          authRepository: auth,
          contactsRepository: ContactsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('not connected to a property yet'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows cached data with a stale banner when offline', (tester) async {
    final auth = await _connectedAuth();
    final cache = _InMemoryCacheStore();
    await cache.write(
      'contacts',
      jsonEncode({
        'data': [
          {'name': 'Asha Manager', 'email': 'asha@example.com', 'phone': '+919876500000', 'role': 'manager'},
        ],
        'cached_at': DateTime(2026, 8, 1, 9, 15).toIso8601String(),
      }),
    );
    final client = MockClient((request) async => throw const SocketException('no route to host'));

    await tester.pumpWidget(
      _wrap(
        ContactsScreen(
          authRepository: auth,
          contactsRepository: ContactsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Asha Manager'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });

  testWidgets('tapping the phone number opens a tel: link', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async => _json({
        'contacts': [
          {'name': 'Asha Manager', 'email': 'asha@example.com', 'phone': '+919876500000', 'role': 'manager'},
        ],
      }, 200),
    );
    final opener = _FakeUrlOpener();

    await tester.pumpWidget(
      _wrap(
        ContactsScreen(
          authRepository: auth,
          contactsRepository: ContactsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
          urlOpener: opener,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('+919876500000'));
    await tester.pumpAndSettle();

    expect(opener.lastUrl, 'tel:+919876500000');
  });

  testWidgets('tapping the email opens a mailto: link, with a fallback message when nothing handles it', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async => _json({
        'contacts': [
          {'name': 'Asha Manager', 'email': 'asha@example.com', 'phone': '+919876500000', 'role': 'manager'},
        ],
      }, 200),
    );
    final opener = _FakeUrlOpener(result: false);

    await tester.pumpWidget(
      _wrap(
        ContactsScreen(
          authRepository: auth,
          contactsRepository: ContactsRepository(apiClient: ApiClient(httpClient: client)),
          cacheStore: _InMemoryCacheStore(),
          urlOpener: opener,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('asha@example.com'));
    await tester.pumpAndSettle();

    expect(opener.lastUrl, 'mailto:asha@example.com');
    expect(find.textContaining('No email app found'), findsOneWidget);
  });
}
