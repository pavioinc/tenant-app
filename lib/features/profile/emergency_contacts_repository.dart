import '../../core/api_client.dart';

class EmergencyContact {
  const EmergencyContact({required this.contactId, required this.name, required this.phone, this.relationship, this.isPrimary = false});

  final String contactId;
  final String name;
  final String phone;
  final String? relationship;
  final bool isPrimary;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) => EmergencyContact(
    contactId: json['contact_id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String,
    relationship: json['relationship'] as String?,
    isPrimary: json['is_primary'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'contact_id': contactId,
    'name': name,
    'phone': phone,
    'relationship': ?relationship,
    'is_primary': isPrimary,
  };
}

/// tenant-service's `/tenant/me/emergency-contacts` (2026-08-27) — a real add/update/delete
/// list, replacing the single name/phone/relationship fields that used to live on
/// TenantProfile/ProfileRepository. Tenant-owned CRUD, no manager-facing view, same shape
/// as VehiclesRepository/vehicles.dart.
class EmergencyContactsRepository {
  EmergencyContactsRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<EmergencyContact>> list(String token) async {
    final body = await _api.get('/api/tenants/v1/tenant/me/emergency-contacts', token: token);
    final contacts = body['emergency_contacts'] as List;
    return contacts.map((c) => EmergencyContact.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<EmergencyContact> add(String token, {required String name, required String phone, String? relationship}) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/emergency-contacts', {
      'name': name,
      'phone': phone,
      'relationship': ?relationship,
    }, token: token);
    return EmergencyContact.fromJson(body);
  }

  Future<EmergencyContact> update(
    String token,
    String contactId, {
    required String name,
    required String phone,
    String? relationship,
  }) async {
    final body = await _api.patch('/api/tenants/v1/tenant/me/emergency-contacts/$contactId', {
      'name': name,
      'phone': phone,
      'relationship': relationship,
    }, token: token);
    return EmergencyContact.fromJson(body);
  }

  Future<void> delete(String token, String contactId) async {
    await _api.delete('/api/tenants/v1/tenant/me/emergency-contacts/$contactId', token: token);
  }

  Future<EmergencyContact> setPrimary(String token, String contactId) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/emergency-contacts/$contactId/primary', {}, token: token);
    return EmergencyContact.fromJson(body);
  }
}
