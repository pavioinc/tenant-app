import '../../core/api_client.dart';
import '../../core/date_utils.dart';

class RenewalRequest {
  const RenewalRequest({required this.status, required this.createdAt, this.requestedEndDate});

  final String status;
  final String createdAt;
  final String? requestedEndDate;

  factory RenewalRequest.fromJson(Map<String, dynamic> json) => RenewalRequest(
    status: json['status'] as String,
    createdAt: shortDate(json['created_at'] as String),
    requestedEndDate: json['requested_end_date'] != null ? shortDate(json['requested_end_date'] as String) : null,
  );

  Map<String, dynamic> toJson() => {'status': status, 'created_at': createdAt, 'requested_end_date': ?requestedEndDate};
}

/// tenant-service's `/tenant/me/renewal-requests` — a lightweight request-and-notify
/// record, not an auto-drafted agreement (see tenant-service/README.md's "Tenant
/// self-service" section for why).
class RenewalRepository {
  RenewalRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<RenewalRequest>> list(String token) async {
    final body = await _api.get('/api/tenants/v1/tenant/me/renewal-requests', token: token);
    final requests = body['renewal_requests'] as List;
    return requests.map((r) => RenewalRequest.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<RenewalRequest> request(String token, {String? requestedEndDate}) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/renewal-requests', {
      'requested_end_date': ?requestedEndDate,
    }, token: token);
    return RenewalRequest.fromJson(body);
  }
}
