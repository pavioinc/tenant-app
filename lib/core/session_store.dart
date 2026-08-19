import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin seam over FlutterSecureStorage so tests can swap in an in-memory fake instead of
/// hitting a platform channel that doesn't exist in the widget-test environment.
abstract class SecureStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Mirrors auth-service's tenantAuth.ts `userResponse()` shape exactly. [orgId],
/// [propertyId], and [tenantId] are only ever present when [connected] is true — a renter
/// who hasn't been added by a property manager yet has none of them, and that's the
/// normal, expected state right after signup (see auth_repository.dart).
class TenantUser {
  const TenantUser({
    required this.userId,
    required this.name,
    required this.role,
    required this.connected,
    this.orgId,
    this.propertyId,
    this.tenantId,
  });

  final String userId;
  final String name;
  final String role;
  final bool connected;
  final String? orgId;
  final String? propertyId;
  final String? tenantId;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'name': name,
    'role': role,
    'connected': connected,
    if (orgId != null) 'org_id': orgId,
    if (propertyId != null) 'property_id': propertyId,
    if (tenantId != null) 'tenant_id': tenantId,
  };

  factory TenantUser.fromJson(Map<String, dynamic> json) => TenantUser(
    userId: json['user_id'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
    connected: json['connected'] as bool? ?? false,
    orgId: json['org_id'] as String?,
    propertyId: json['property_id'] as String?,
    tenantId: json['tenant_id'] as String?,
  );
}

class Session {
  const Session({required this.accessToken, required this.refreshToken, required this.user, this.accessTokenExpiresAt});

  final String accessToken;
  final String refreshToken;
  final TenantUser user;
  /// Null for sessions saved before this field existed — treated as "unknown, refresh
  /// to be safe" by AuthRepository.currentSession(), not as "definitely still valid".
  final DateTime? accessTokenExpiresAt;
}

/// Tokens live in the platform keystore/keychain (flutter_secure_storage), not
/// SharedPreferences — same rationale as an access/refresh token pair never belonging in
/// plain-text storage on the owner-dashboard side (there it's localStorage, the browser's
/// closest equivalent boundary; here it's the OS-backed secure store).
class SessionStore {
  SessionStore({SecureStore? storage}) : _storage = storage ?? const FlutterSecureStore();

  final SecureStore _storage;

  static const _accessTokenKey = 'nivasaos.access_token';
  static const _refreshTokenKey = 'nivasaos.refresh_token';
  static const _userKey = 'nivasaos.user';
  static const _accessTokenExpiresAtKey = 'nivasaos.access_token_expires_at';

  Future<void> save(Session session) async {
    await _storage.write(_accessTokenKey, session.accessToken);
    await _storage.write(_refreshTokenKey, session.refreshToken);
    await _storage.write(_userKey, jsonEncode(session.user.toJson()));
    if (session.accessTokenExpiresAt != null) {
      await _storage.write(_accessTokenExpiresAtKey, session.accessTokenExpiresAt!.toIso8601String());
    } else {
      await _storage.delete(_accessTokenExpiresAtKey);
    }
  }

  Future<Session?> read() async {
    final accessToken = await _storage.read(_accessTokenKey);
    final refreshToken = await _storage.read(_refreshTokenKey);
    final userJson = await _storage.read(_userKey);
    if (accessToken == null || refreshToken == null || userJson == null) return null;
    final expiresAtRaw = await _storage.read(_accessTokenExpiresAtKey);
    return Session(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: TenantUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>),
      accessTokenExpiresAt: expiresAtRaw != null ? DateTime.parse(expiresAtRaw) : null,
    );
  }

  Future<void> clear() async {
    await _storage.delete(_accessTokenKey);
    await _storage.delete(_refreshTokenKey);
    await _storage.delete(_userKey);
    await _storage.delete(_accessTokenExpiresAtKey);
  }
}
