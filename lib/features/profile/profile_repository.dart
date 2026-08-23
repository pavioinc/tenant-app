import '../../core/api_client.dart';

const supportedLanguages = ['en', 'ml', 'ta', 'hi', 'te'];

const languageLabels = {'en': 'English', 'ml': 'Malayalam', 'ta': 'Tamil', 'hi': 'Hindi', 'te': 'Telugu'};

/// Mirrors tenant-service's `TenantSelf` response shape exactly
/// (src/routes/tenantSelf.ts's `serializeSelf`).
class TenantProfile {
  const TenantProfile({
    required this.tenantId,
    required this.propertyId,
    required this.propertyName,
    required this.propertyAddress,
    required this.propertyCity,
    required this.name,
    required this.phone,
    required this.email,
    required this.language,
    required this.status,
    required this.permanentAddress,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.emergencyContactRelationship,
    required this.accountFullName,
    required this.accountEmail,
  });

  final String tenantId;
  final String propertyId;
  final String? propertyName;
  final String? propertyAddress;
  final String? propertyCity;
  final String name;
  final String phone;
  final String? email;
  final String language;
  final String status;
  final String? permanentAddress;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactRelationship;
  final String? accountFullName;
  final String? accountEmail;

  factory TenantProfile.fromJson(Map<String, dynamic> json) => TenantProfile(
    tenantId: json['tenant_id'] as String,
    propertyId: json['property_id'] as String,
    propertyName: json['property_name'] as String?,
    propertyAddress: json['property_address'] as String?,
    propertyCity: json['property_city'] as String?,
    name: json['name'] as String,
    phone: json['phone'] as String,
    email: json['email'] as String?,
    language: json['language'] as String,
    status: json['status'] as String,
    permanentAddress: json['permanent_address'] as String?,
    emergencyContactName: json['emergency_contact_name'] as String?,
    emergencyContactPhone: json['emergency_contact_phone'] as String?,
    emergencyContactRelationship: json['emergency_contact_relationship'] as String?,
    accountFullName: json['account_full_name'] as String?,
    accountEmail: json['account_email'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'tenant_id': tenantId,
    'property_id': propertyId,
    'property_name': ?propertyName,
    'property_address': ?propertyAddress,
    'property_city': ?propertyCity,
    'name': name,
    'phone': phone,
    'email': ?email,
    'language': language,
    'status': status,
    'permanent_address': ?permanentAddress,
    'emergency_contact_name': ?emergencyContactName,
    'emergency_contact_phone': ?emergencyContactPhone,
    'emergency_contact_relationship': ?emergencyContactRelationship,
    'account_full_name': ?accountFullName,
    'account_email': ?accountEmail,
  };
}

/// Talks to tenant-service's `/api/tenants/v1/tenant/me` via api-gateway. Every call needs
/// a bearer token explicitly — same "caller passes the token" shape as AuthRepository's own
/// ApiClient calls, no session ownership lives here.
class ProfileRepository {
  ProfileRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<TenantProfile> fetch(String token) async {
    final body = await _api.get('/api/tenants/v1/tenant/me', token: token);
    return TenantProfile.fromJson(body);
  }

  Future<TenantProfile> update(
    String token, {
    String? phone,
    String? language,
    String? permanentAddress,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelationship,
  }) async {
    final body = await _api.patch('/api/tenants/v1/tenant/me', {
      'phone': ?phone,
      'language': ?language,
      'permanent_address': ?permanentAddress,
      'emergency_contact_name': ?emergencyContactName,
      'emergency_contact_phone': ?emergencyContactPhone,
      'emergency_contact_relationship': ?emergencyContactRelationship,
    }, token: token);
    return TenantProfile.fromJson(body);
  }
}
