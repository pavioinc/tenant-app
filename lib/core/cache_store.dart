import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin seam over SharedPreferences, same shape as `SecureStore` (session_store.dart),
/// so widget tests can inject an in-memory fake instead of hitting a platform channel.
/// Non-secret last-known-good API responses only — tokens stay in `SecureStore`, and
/// anything containing PII (see `SecureCacheStore` below) stays out of this one, since
/// SharedPreferences is plain-text, world-readable-on-a-rooted-device, and included in
/// Android's default `adb backup`/auto-backup unless explicitly excluded.
abstract class CacheStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class SharedPreferencesCacheStore implements CacheStore {
  const SharedPreferencesCacheStore();

  static const _prefix = 'pavio.cache.';

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', value);
  }

  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }
}

/// Same offline-cache contract as [SharedPreferencesCacheStore], backed by the platform
/// keystore/keychain instead of plain-text SharedPreferences — for a cached API response
/// that itself contains PII (e.g. AccountDetailsScreen's home address and emergency contact),
/// where the whole point of `fetchWithCache`'s offline fallback doesn't hold up if the
/// cache itself is the weaker link. See the 2026-08-26 security review.
class SecureCacheStore implements CacheStore {
  const SecureCacheStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  static const _prefix = 'pavio.cache.';

  @override
  Future<void> write(String key, String value) => _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: '$_prefix$key');

  @override
  Future<void> delete(String key) => _storage.delete(key: '$_prefix$key');
}
