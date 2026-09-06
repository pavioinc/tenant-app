import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivasaos_tenant_app/core/api_client.dart';
import 'package:nivasaos_tenant_app/core/cache_store.dart';
import 'package:nivasaos_tenant_app/core/file_picker_service.dart';
import 'package:nivasaos_tenant_app/core/session_store.dart';
import 'package:nivasaos_tenant_app/core/share_service.dart';
import 'package:nivasaos_tenant_app/core/url_opener.dart';
import 'package:nivasaos_tenant_app/features/auth/auth_repository.dart';
import 'package:nivasaos_tenant_app/features/documents/documents_repository.dart';
import 'package:nivasaos_tenant_app/features/documents/documents_screen.dart';
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

class _FakeFilePicker implements FilePickerService {
  _FakeFilePicker(this.result);
  final PickedFile? result;

  @override
  Future<PickedFile?> pickDocument() async => result;
}

class _FakeUrlOpener implements UrlOpener {
  String? openedUrl;

  @override
  Future<bool> open(String url) async {
    openedUrl = url;
    return true;
  }
}

class _FakeShareService implements ShareService {
  String? sharedUrl;

  @override
  Future<void> shareUrl(String url) async {
    sharedUrl = url;
  }
}

http.Response _json(Map<String, dynamic> body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Widget _wrap(Widget child) =>
    MaterialApp(theme: NivasaTheme.light(), home: child);

Future<AuthRepository> _connectedAuth() async {
  final store = _InMemorySecureStore();
  await store.write('nivasaos.access_token', 'access-token');
  await store.write('nivasaos.refresh_token', 'refresh-token');
  await store.write(
    'nivasaos.access_token_expires_at',
    DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
  );
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

/// Taps the overflow menu on the (only, in these tests) document row and then the named
/// menu item inside the popup that opens.
Future<void> _tapMenuAction(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state with no documents', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'documents': []}, 200));

    await tester.pumpWidget(
      _wrap(
        DocumentsScreen(
          authRepository: auth,
          documentsRepository: DocumentsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No documents yet'), findsOneWidget);
  });

  testWidgets('lists a document with type, size, and date (1f mock)', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async => _json({
        'documents': [
          {
            'document_id': 'document-1',
            'label': 'Aadhaar — front',
            'content_type': 'application/pdf',
            'uploaded_at': '2026-03-04T00:00:00Z',
            'status': 'not_reviewed',
            'file_size_bytes': 245760,
          },
        ],
      }, 200),
    );

    await tester.pumpWidget(
      _wrap(
        DocumentsScreen(
          authRepository: auth,
          documentsRepository: DocumentsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aadhaar — front'), findsOneWidget);
    expect(find.text('PDF · 240 KB · 4 Mar 2026'), findsOneWidget);
  });

  testWidgets(
    'shows a verified document with the green check treatment and no size when unknown',
    (tester) async {
      final auth = await _connectedAuth();
      final client = MockClient(
        (request) async => _json({
          'documents': [
            {
              'document_id': 'document-1',
              'label': 'Rent agreement (signed)',
              'content_type': 'application/pdf',
              'uploaded_at': '2026-03-01T00:00:00Z',
              'status': 'verified',
              'file_size_bytes': null,
            },
          ],
        }, 200),
      );

      await tester.pumpWidget(
        _wrap(
          DocumentsScreen(
            authRepository: auth,
            documentsRepository: DocumentsRepository(
              apiClient: ApiClient(httpClient: client),
            ),
            cacheStore: _InMemoryCacheStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.verified), findsOneWidget);
      // No size known for this row — subtitle skips straight from type to date.
      expect(find.text('PDF · 1 Mar 2026'), findsOneWidget);
    },
  );

  testWidgets('shows the rejection reason for a rejected document', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async => _json({
        'documents': [
          {
            'document_id': 'document-1',
            'label': 'Aadhaar — back',
            'content_type': 'image/jpeg',
            'uploaded_at': '2026-03-04T00:00:00Z',
            'status': 'rejected',
            'review_note': 'Photo is blurry, please re-upload',
          },
        ],
      }, 200),
    );

    await tester.pumpWidget(
      _wrap(
        DocumentsScreen(
          authRepository: auth,
          documentsRepository: DocumentsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Rejected — Photo is blurry, please re-upload'),
      findsOneWidget,
    );
  });

  testWidgets('uploads a picked document and reloads the list', (tester) async {
    final auth = await _connectedAuth();
    var posted = false;
    var listCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posted = true;
        return _json({
          'document_id': 'document-1',
          'label': 'aadhaar.pdf',
          'content_type': 'application/pdf',
          'uploaded_at': '2026-08-18T00:00:00Z',
          'status': 'not_reviewed',
        }, 201);
      }
      listCount += 1;
      if (listCount == 1) return _json({'documents': []}, 200);
      return _json({
        'documents': [
          {
            'document_id': 'document-1',
            'label': 'aadhaar.pdf',
            'content_type': 'application/pdf',
            'uploaded_at': '2026-08-18T00:00:00Z',
            'status': 'not_reviewed',
          },
        ],
      }, 200);
    });

    await tester.pumpWidget(
      _wrap(
        DocumentsScreen(
          authRepository: auth,
          documentsRepository: DocumentsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
          filePicker: _FakeFilePicker(
            PickedFile(
              bytes: Uint8List.fromList([1, 2, 3]),
              name: 'aadhaar.pdf',
              contentType: 'application/pdf',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload a document'));
    await tester.pumpAndSettle();

    expect(posted, isTrue);
    expect(find.text('aadhaar.pdf'), findsOneWidget);
  });

  testWidgets('does nothing when the file picker returns no selection', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'documents': []}, 200));

    await tester.pumpWidget(
      _wrap(
        DocumentsScreen(
          authRepository: auth,
          documentsRepository: DocumentsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
          filePicker: _FakeFilePicker(null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upload a document'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No documents yet'), findsOneWidget);
  });

  testWidgets('Download in the overflow menu opens the presigned URL', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/download')) {
        return _json({
          'download_url': 'https://s3.example.com/presigned-download',
        }, 200);
      }
      return _json({
        'documents': [
          {
            'document_id': 'document-1',
            'label': 'Aadhaar card',
            'content_type': 'application/pdf',
            'uploaded_at': '2026-08-18T00:00:00Z',
            'status': 'not_reviewed',
          },
        ],
      }, 200);
    });
    final urlOpener = _FakeUrlOpener();

    await tester.pumpWidget(
      _wrap(
        DocumentsScreen(
          authRepository: auth,
          documentsRepository: DocumentsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
          urlOpener: urlOpener,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapMenuAction(tester, 'Download');

    expect(urlOpener.openedUrl, 'https://s3.example.com/presigned-download');
  });

  testWidgets('Share in the overflow menu shares the presigned URL', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/download')) {
        return _json({
          'download_url': 'https://s3.example.com/presigned-download',
        }, 200);
      }
      return _json({
        'documents': [
          {
            'document_id': 'document-1',
            'label': 'Aadhaar card',
            'content_type': 'application/pdf',
            'uploaded_at': '2026-08-18T00:00:00Z',
            'status': 'not_reviewed',
          },
        ],
      }, 200);
    });
    final shareService = _FakeShareService();

    await tester.pumpWidget(
      _wrap(
        DocumentsScreen(
          authRepository: auth,
          documentsRepository: DocumentsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: _InMemoryCacheStore(),
          shareService: shareService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapMenuAction(tester, 'Share');

    expect(shareService.sharedUrl, 'https://s3.example.com/presigned-download');
  });

  testWidgets(
    'Delete… in the overflow menu still asks for confirmation first',
    (tester) async {
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
            'documents': [
              {
                'document_id': 'document-1',
                'label': 'Aadhaar card',
                'content_type': 'application/pdf',
                'uploaded_at': '2026-08-18T00:00:00Z',
                'status': 'not_reviewed',
              },
            ],
          }, 200);
        }
        return _json({'documents': []}, 200);
      });

      await tester.pumpWidget(
        _wrap(
          DocumentsScreen(
            authRepository: auth,
            documentsRepository: DocumentsRepository(
              apiClient: ApiClient(httpClient: client),
            ),
            cacheStore: _InMemoryCacheStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapMenuAction(tester, 'Delete…');
      expect(deleted, isFalse);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
      expect(find.text('Aadhaar card'), findsNothing);
    },
  );

  testWidgets('shows cached data with a stale banner when offline', (
    tester,
  ) async {
    final auth = await _connectedAuth();
    final cache = _InMemoryCacheStore();
    await cache.write(
      'documents',
      jsonEncode({
        'data': [
          {
            'document_id': 'document-1',
            'label': 'Aadhaar card',
            'content_type': 'application/pdf',
            'uploaded_at': '2026-08-18T00:00:00Z',
            'status': 'not_reviewed',
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
        DocumentsScreen(
          authRepository: auth,
          documentsRepository: DocumentsRepository(
            apiClient: ApiClient(httpClient: client),
          ),
          cacheStore: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aadhaar card'), findsOneWidget);
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });
}
