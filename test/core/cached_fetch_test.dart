import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavio_tenant_app/core/api_client.dart';
import 'package:pavio_tenant_app/core/cache_store.dart';
import 'package:pavio_tenant_app/core/cached_fetch.dart';

class _InMemoryCacheStore implements CacheStore {
  final _values = <String, String>{};

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class _Thing {
  const _Thing(this.value);
  final String value;

  Map<String, dynamic> toJson() => {'value': value};
  factory _Thing.fromJson(Map<String, dynamic> json) => _Thing(json['value'] as String);
}

void main() {
  group('fetchWithCache', () {
    test('success path caches and returns fresh data', () async {
      final cache = _InMemoryCacheStore();
      final result = await fetchWithCache<_Thing>(
        cache: cache,
        cacheKey: 'thing',
        fetchNetwork: () async => const _Thing('fresh'),
        toJson: (t) => t.toJson(),
        fromJson: (json) => _Thing.fromJson(json as Map<String, dynamic>),
      );

      expect(result.data.value, 'fresh');
      expect(result.stale, isFalse);
      expect(result.lastSyncedAt, isNotNull);

      final cached = jsonDecode((await cache.read('thing'))!) as Map<String, dynamic>;
      expect((cached['data'] as Map<String, dynamic>)['value'], 'fresh');
    });

    test('an ApiException propagates untouched even when a cache entry exists', () async {
      final cache = _InMemoryCacheStore();
      await cache.write('thing', jsonEncode({'data': {'value': 'old'}, 'cached_at': DateTime(2026, 1, 1).toIso8601String()}));

      expect(
        () => fetchWithCache<_Thing>(
          cache: cache,
          cacheKey: 'thing',
          fetchNetwork: () async => throw ApiException(404, 'not_found', 'not connected to a property yet'),
          toJson: (t) => t.toJson(),
          fromJson: (json) => _Thing.fromJson(json as Map<String, dynamic>),
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('a network-level failure with a cache present returns stale data and the right timestamp', () async {
      final cache = _InMemoryCacheStore();
      final cachedAt = DateTime(2026, 8, 1, 10, 30);
      await cache.write('thing', jsonEncode({'data': {'value': 'old'}, 'cached_at': cachedAt.toIso8601String()}));

      final result = await fetchWithCache<_Thing>(
        cache: cache,
        cacheKey: 'thing',
        fetchNetwork: () async => throw const SocketException('no route to host'),
        toJson: (t) => t.toJson(),
        fromJson: (json) => _Thing.fromJson(json as Map<String, dynamic>),
      );

      expect(result.data.value, 'old');
      expect(result.stale, isTrue);
      expect(result.lastSyncedAt, cachedAt);
    });

    test('a network-level failure with no cache present rethrows the original error', () async {
      final cache = _InMemoryCacheStore();

      expect(
        () => fetchWithCache<_Thing>(
          cache: cache,
          cacheKey: 'thing',
          fetchNetwork: () async => throw const SocketException('no route to host'),
          toJson: (t) => t.toJson(),
          fromJson: (json) => _Thing.fromJson(json as Map<String, dynamic>),
        ),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
