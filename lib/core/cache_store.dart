import 'package:shared_preferences/shared_preferences.dart';

/// Thin seam over SharedPreferences, same shape as `SecureStore` (session_store.dart),
/// so widget tests can inject an in-memory fake instead of hitting a platform channel.
/// Non-secret last-known-good API responses only — tokens stay in `SecureStore`.
abstract class CacheStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class SharedPreferencesCacheStore implements CacheStore {
  const SharedPreferencesCacheStore();

  static const _prefix = 'nivasaos.cache.';

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
