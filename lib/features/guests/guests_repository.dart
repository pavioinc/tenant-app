import '../../core/api_client.dart';
import '../../core/date_utils.dart';

class ExpectedGuest {
  const ExpectedGuest({required this.guestId, required this.name, required this.visitDate, this.phone, this.notes});

  final String guestId;
  final String name;
  final String visitDate;
  final String? phone;
  final String? notes;

  factory ExpectedGuest.fromJson(Map<String, dynamic> json) => ExpectedGuest(
    guestId: json['guest_id'] as String,
    name: json['name'] as String,
    visitDate: shortDate(json['visit_date'] as String),
    phone: json['phone'] as String?,
    notes: json['notes'] as String?,
  );

  Map<String, dynamic> toJson() => {'guest_id': guestId, 'name': name, 'visit_date': visitDate, 'phone': ?phone, 'notes': ?notes};
}

/// tenant-service's `/tenant/me/guests` — tenant-owned expected-visitor recordkeeping,
/// no manager-facing view or approval workflow.
class GuestsRepository {
  GuestsRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<ExpectedGuest>> list(String token) async {
    final body = await _api.get('/api/tenants/v1/tenant/me/guests', token: token);
    final guests = body['guests'] as List;
    return guests.map((g) => ExpectedGuest.fromJson(g as Map<String, dynamic>)).toList();
  }

  Future<ExpectedGuest> add(String token, {required String name, required String visitDate, String? phone, String? notes}) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/guests', {
      'name': name,
      'visit_date': visitDate,
      'phone': ?phone,
      'notes': ?notes,
    }, token: token);
    return ExpectedGuest.fromJson(body);
  }

  Future<void> delete(String token, String guestId) async {
    await _api.delete('/api/tenants/v1/tenant/me/guests/$guestId', token: token);
  }
}
