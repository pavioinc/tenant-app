import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/session_store.dart';
import 'package:pavio_tenant_app/features/auth/auth_repository.dart';

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

void main() {
  group('AuthRepository.signup', () {
    test('saves an unconnected session and returns it', () async {
      final store = _InMemorySecureStore();
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/v1/tenant/signup');
        expect(jsonDecode(request.body), {
          'first_name': 'Amit',
          'last_name': 'Kumar',
          'email': 'amit@example.com',
          'password': 'Correct-Horse-1!',
        });
        return _json({
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'expires_at': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
          'user': {'user_id': 'account-1', 'name': 'Amit Kumar', 'role': 'tenant', 'connected': false},
        }, 201);
      });
      final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: store));

      final session = await repo.signup(firstName: 'Amit', lastName: 'Kumar', email: 'amit@example.com', password: 'Correct-Horse-1!');

      expect(session.user.connected, false);
      expect(await store.read('pavio.access_token'), 'access-token');
    });

    test('includes birthdate only when given', () async {
      final client = MockClient((request) async {
        expect(jsonDecode(request.body), {
          'first_name': 'Amit',
          'last_name': 'Kumar',
          'email': 'amit@example.com',
          'password': 'Correct-Horse-1!',
          'birthdate': '1995-06-15',
        });
        return _json({
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'expires_at': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
          'user': {'user_id': 'account-1', 'name': 'Amit Kumar', 'role': 'tenant', 'connected': false},
        }, 201);
      });
      final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

      await repo.signup(
        firstName: 'Amit',
        lastName: 'Kumar',
        email: 'amit@example.com',
        password: 'Correct-Horse-1!',
        birthdate: '1995-06-15',
      );
    });

    test('surfaces email_taken as an ApiException', () async {
      final client = MockClient((request) async => _json({'error': 'email_taken', 'message': 'an account with this email already exists'}, 409));
      final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

      await expectLater(
        repo.signup(firstName: 'Amit', lastName: 'Kumar', email: 'amit@example.com', password: 'Correct-Horse-1!'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'email_taken')),
      );
    });
  });

  group('AuthRepository.login', () {
    test('saves a connected session, including org/property/tenant ids', () async {
      final store = _InMemorySecureStore();
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/v1/tenant/login');
        return _json({
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'expires_at': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
          'user': {
            'user_id': 'account-1',
            'name': 'Amit Kumar',
            'role': 'tenant',
            'connected': true,
            'org_id': 'org-1',
            'property_id': 'prop-1',
            'tenant_id': 'tenant-1',
          },
        }, 200);
      });
      final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: store));

      final session = await repo.login(email: 'amit@example.com', password: 'correct-horse-battery-staple');

      expect(session.user.connected, true);
      expect(session.user.orgId, 'org-1');
      final persisted = await repo.currentSession();
      expect(persisted?.user.tenantId, 'tenant-1');
    });

    test('surfaces invalid_credentials as an ApiException', () async {
      final client = MockClient((request) async => _json({'error': 'invalid_credentials', 'message': 'incorrect email or password'}, 401));
      final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

      await expectLater(
        repo.login(email: 'amit@example.com', password: 'wrong'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  group('AuthRepository.refreshConnectionStatus', () {
    test('rotates the refresh token then re-reads /tenant/me, persisting the merged session', () async {
      final store = _InMemorySecureStore();
      await store.write('pavio.access_token', 'old-access');
      await store.write('pavio.refresh_token', 'old-refresh');
      await store.write('pavio.user', jsonEncode({'user_id': 'account-1', 'name': 'Amit Kumar', 'role': 'tenant', 'connected': false}));

      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/v1/refresh') {
          expect(jsonDecode(request.body), {'refresh_token': 'old-refresh'});
          return _json({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'expires_at': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
          }, 200);
        }
        if (request.url.path == '/api/auth/v1/tenant/me') {
          expect(request.headers['Authorization'], 'Bearer new-access');
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

      final session = await repo.refreshConnectionStatus();

      expect(session.accessToken, 'new-access');
      expect(session.user.connected, true);
      expect(session.user.propertyId, 'prop-1');
      expect(await store.read('pavio.access_token'), 'new-access');
    });

    test('throws StateError when there is no active session', () async {
      final client = MockClient((request) async => _json({}, 200));
      final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: _InMemorySecureStore()));

      await expectLater(repo.refreshConnectionStatus(), throwsA(isA<StateError>()));
    });
  });

  group('AuthRepository.logout', () {
    test('clears the stored session even if the network call fails', () async {
      final store = _InMemorySecureStore();
      await store.write('pavio.access_token', 'a');
      await store.write('pavio.refresh_token', 'r');
      await store.write('pavio.user', jsonEncode({'user_id': 'account-1', 'name': 'Amit', 'role': 'tenant', 'connected': false}));

      final client = MockClient((request) async => http.Response('', 500));
      final repo = AuthRepository(apiClient: ApiClient(httpClient: client), sessionStore: SessionStore(storage: store));

      await repo.logout();

      expect(await repo.currentSession(), isNull);
    });
  });
}
