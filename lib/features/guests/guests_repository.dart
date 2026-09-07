import '../../core/api_client.dart';
import '../../core/date_utils.dart';

class ExpectedGuest {
  const ExpectedGuest({
    required this.guestId,
    required this.name,
    required this.visitDate,
    required this.status,
    this.phone,
    this.notes,
    this.arrivedAt,
    this.departedAt,
  });

  final String guestId;
  final String name;
  final String visitDate;
  final String? phone;
  final String? notes;
  // 'expected' | 'arrived' | 'denied' | 'departed' — set by the front desk from the
  // owner-dashboard side (CLO-231). Real data serializeGuest already returns; this
  // screen just never asked for it before.
  final String status;
  final String? arrivedAt;
  final String? departedAt;

  factory ExpectedGuest.fromJson(Map<String, dynamic> json) => ExpectedGuest(
    guestId: json['guest_id'] as String,
    name: json['name'] as String,
    visitDate: shortDate(json['visit_date'] as String),
    phone: json['phone'] as String?,
    notes: json['notes'] as String?,
    status: json['status'] as String? ?? 'expected',
    arrivedAt: json['arrived_at'] as String?,
    departedAt: json['departed_at'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'guest_id': guestId,
    'name': name,
    'visit_date': visitDate,
    'phone': ?phone,
    'notes': ?notes,
    'status': status,
    'arrived_at': ?arrivedAt,
    'departed_at': ?departedAt,
  };
}

/// tenant-service's `/tenant/me/guests` — tenant-owned expected-visitor recordkeeping.
/// No approval workflow (a tenant's own guest is auto-accepted), but the front desk's
/// arrival/departure status (CLO-231, owner-dashboard's Guests view) is real and shared.
class GuestsRepository {
  GuestsRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<ExpectedGuest>> list(String token) async {
    final body = await _api.get(
      '/api/tenants/v1/tenant/me/guests',
      token: token,
    );
    final guests = body['guests'] as List;
    return guests
        .map((g) => ExpectedGuest.fromJson(g as Map<String, dynamic>))
        .toList();
  }

  Future<ExpectedGuest> add(
    String token, {
    required String name,
    required String visitDate,
    String? phone,
    String? notes,
  }) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/guests', {
      'name': name,
      'visit_date': visitDate,
      'phone': ?phone,
      'notes': ?notes,
    }, token: token);
    return ExpectedGuest.fromJson(body);
  }

  Future<void> delete(String token, String guestId) async {
    await _api.delete(
      '/api/tenants/v1/tenant/me/guests/$guestId',
      token: token,
    );
  }
}
