import '../../core/api_client.dart';

const _roleLabels = {'owner': 'Owner', 'manager': 'Property manager'};

String contactRoleLabel(String role) => _roleLabels[role] ?? role;

class Contact {
  const Contact({
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
  });

  final String name;
  final String? email;
  final String? phone;
  final String role;

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
    name: json['name'] as String,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    role: json['role'] as String,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': ?email,
    'phone': ?phone,
    'role': role,
  };
}

/// tenant-service's `/tenant/me/contacts` — the org's own managers/owners, read from
/// `users` directly (not a tenant-owned record, so no per-tenant scoping beyond org).
class ContactsRepository {
  ContactsRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<Contact>> list(String token) async {
    final body = await _api.get(
      '/api/tenants/v1/tenant/me/contacts',
      token: token,
    );
    final contacts = body['contacts'] as List;
    return contacts
        .map((c) => Contact.fromJson(c as Map<String, dynamic>))
        .toList();
  }
}
