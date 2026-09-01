import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivasaos_tenant_app/core/api_client.dart';
import 'package:nivasaos_tenant_app/core/session_store.dart';
import 'package:nivasaos_tenant_app/features/auth/auth_repository.dart';
import 'package:nivasaos_tenant_app/features/complaints/complaint_detail_screen.dart';
import 'package:nivasaos_tenant_app/features/complaints/complaints_repository.dart';
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

http.Response _json(Map<String, dynamic> body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Widget _wrap(Widget child) => MaterialApp(theme: NivasaTheme.light(), home: child);

const _complaint = Complaint(
  complaintId: 'complaint-1',
  category: 'Electrical',
  description: 'Fan not working',
  status: 'in_progress',
  createdAt: '2026-08-14',
);

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
  testWidgets('shows the complaint header and an empty thread', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async {
      expect(request.url.path, '/api/tenants/v1/tenant/me/complaints/complaint-1/notes');
      return _json({'notes': []}, 200);
    });

    await tester.pumpWidget(
      _wrap(
        ComplaintDetailScreen(
          complaint: _complaint,
          authRepository: auth,
          complaintsRepository: ComplaintsRepository(apiClient: ApiClient(httpClient: client)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Fan not working'), findsOneWidget);
    expect(find.textContaining('No updates yet'), findsOneWidget);
  });

  testWidgets('lists manager and tenant notes, manager notes show the author name', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient(
      (request) async => _json({
        'notes': [
          {
            'note_id': 'note-1',
            'complaint_id': 'complaint-1',
            'author_type': 'manager',
            'author_name': 'Asha Manager',
            'body': 'Sent an electrician over.',
            'created_at': '2026-08-14T01:00:00Z',
          },
          {
            'note_id': 'note-2',
            'complaint_id': 'complaint-1',
            'author_type': 'tenant',
            'author_name': 'Amit Kumar',
            'body': 'Thanks, still waiting.',
            'created_at': '2026-08-14T02:00:00Z',
          },
        ],
      }, 200),
    );

    await tester.pumpWidget(
      _wrap(
        ComplaintDetailScreen(
          complaint: _complaint,
          authRepository: auth,
          complaintsRepository: ComplaintsRepository(apiClient: ApiClient(httpClient: client)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Asha Manager'), findsOneWidget);
    expect(find.text('Sent an electrician over.'), findsOneWidget);
    expect(find.text('Thanks, still waiting.'), findsOneWidget);
  });

  testWidgets('sends a new note and appends it to the thread', (tester) async {
    final auth = await _connectedAuth();
    var posted = false;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posted = true;
        expect(jsonDecode(request.body), {'body': 'Still broken, please help'});
        return _json({
          'note_id': 'note-3',
          'complaint_id': 'complaint-1',
          'author_type': 'tenant',
          'author_name': 'Amit Kumar',
          'body': 'Still broken, please help',
          'created_at': '2026-08-14T03:00:00Z',
        }, 201);
      }
      return _json({'notes': []}, 200);
    });

    await tester.pumpWidget(
      _wrap(
        ComplaintDetailScreen(
          complaint: _complaint,
          authRepository: auth,
          complaintsRepository: ComplaintsRepository(apiClient: ApiClient(httpClient: client)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Still broken, please help');
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pumpAndSettle();

    expect(posted, isTrue);
    expect(find.text('Still broken, please help'), findsOneWidget);
  });

  testWidgets('shows an error state with retry when the thread fails to load', (tester) async {
    final auth = await _connectedAuth();
    final client = MockClient((request) async => _json({'error': 'not_found', 'message': 'complaint not found'}, 404));

    await tester.pumpWidget(
      _wrap(
        ComplaintDetailScreen(
          complaint: _complaint,
          authRepository: auth,
          complaintsRepository: ComplaintsRepository(apiClient: ApiClient(httpClient: client)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('complaint not found'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
