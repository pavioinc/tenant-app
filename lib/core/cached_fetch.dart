import 'dart:convert';
import 'api_client.dart';
import 'cache_store.dart';

/// [stale] means [data] came from [CacheStore], not the network, because the fresh fetch
/// failed for a connectivity reason (not a real API response). [lastSyncedAt] is when that
/// cached copy was originally written — null only when [stale] is false.
class CachedFetch<T> {
  const CachedFetch({required this.data, required this.stale, this.lastSyncedAt});

  final T data;
  final bool stale;
  final DateTime? lastSyncedAt;
}

/// Fetches from the network, caching the result on success; falls back to the last cached
/// value on a connectivity failure. An [ApiException] (a real non-2xx response from
/// api-gateway — see api_client.dart) is never masked by stale cache, since it's a
/// meaningful answer (e.g. a 404 "not connected to a property yet") rather than a sign the
/// device is offline.
Future<CachedFetch<T>> fetchWithCache<T>({
  required CacheStore cache,
  required String cacheKey,
  required Future<T> Function() fetchNetwork,
  required Object? Function(T) toJson,
  required T Function(dynamic) fromJson,
}) async {
  try {
    final data = await fetchNetwork();
    final now = DateTime.now();
    await cache.write(cacheKey, jsonEncode({'data': toJson(data), 'cached_at': now.toIso8601String()}));
    return CachedFetch(data: data, stale: false, lastSyncedAt: now);
  } on ApiException {
    rethrow;
  } catch (_) {
    final cached = await cache.read(cacheKey);
    if (cached == null) rethrow;
    final decoded = jsonDecode(cached) as Map<String, dynamic>;
    return CachedFetch(data: fromJson(decoded['data']), stale: true, lastSyncedAt: DateTime.parse(decoded['cached_at'] as String));
  }
}
