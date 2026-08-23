import '../../core/api_client.dart';

/// Mirrors tenant-service's KycStatus response shape exactly (src/routes/tenants.ts's
/// GET /:id/kyc and src/routes/tenantSelf.ts's GET /kyc/status use the same shape).
class KycStatus {
  const KycStatus({required this.status, this.aadhaarLast4, this.verifiedAt});

  final String status; // not_started | pending | verified | failed | expired
  final String? aadhaarLast4;
  final DateTime? verifiedAt;

  bool get isVerified => status == 'verified';

  factory KycStatus.fromJson(Map<String, dynamic> json) => KycStatus(
    status: json['status'] as String,
    aadhaarLast4: json['aadhaar_last4'] as String?,
    verifiedAt: json['verified_at'] != null ? DateTime.parse(json['verified_at'] as String) : null,
  );
}

/// Talks to tenant-service's `/api/tenants/v1/tenant/me/kyc/*` via api-gateway. No real
/// UIDAI Aadhaar Bridge sandbox access exists in this environment — the backend's mock
/// provider makes this flow genuinely exercisable end to end regardless (see
/// tenant-service/src/kyc/provider.ts).
class KycRepository {
  KycRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<KycStatus> status(String token) async {
    final body = await _api.get('/api/tenants/v1/tenant/me/kyc/status', token: token);
    return KycStatus.fromJson(body);
  }

  /// Returns how many seconds the OTP is valid for.
  Future<int> requestOtp(String token, {required String aadhaarNumber}) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/kyc/request-otp', {'aadhaar_number': aadhaarNumber}, token: token);
    return body['expires_in_seconds'] as int;
  }

  Future<KycStatus> verifyOtp(String token, {required String code}) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/kyc/verify-otp', {'code': code}, token: token);
    return KycStatus.fromJson(body);
  }
}
