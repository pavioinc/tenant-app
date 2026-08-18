import '../../core/api_client.dart';
import '../../core/date_utils.dart';

const complaintCategories = ['Electrical', 'Plumbing', 'Cleaning', 'Internet', 'Furniture', 'Noise', 'Other'];

class Complaint {
  const Complaint({required this.category, required this.description, required this.status, required this.createdAt});

  final String category;
  final String description;
  final String status;
  final String createdAt;

  factory Complaint.fromJson(Map<String, dynamic> json) => Complaint(
    category: json['category'] as String,
    description: json['description'] as String,
    status: json['status'] as String,
    createdAt: shortDate(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {'category': category, 'description': description, 'status': status, 'created_at': createdAt};
}

/// tenant-service's `/tenant/me/complaints` — ownership-scoped, same pattern as
/// Profile/Rentals/Renewal.
class ComplaintsRepository {
  ComplaintsRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<Complaint>> list(String token) async {
    final body = await _api.get('/api/tenants/v1/tenant/me/complaints', token: token);
    final complaints = body['complaints'] as List;
    return complaints.map((c) => Complaint.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<Complaint> submit(String token, {required String category, required String description}) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/complaints', {'category': category, 'description': description}, token: token);
    return Complaint.fromJson(body);
  }
}
