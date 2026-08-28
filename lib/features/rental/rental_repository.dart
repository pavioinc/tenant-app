import '../../core/api_client.dart';
import '../../core/date_utils.dart';

class BedInfo {
  const BedInfo({required this.label, required this.roomName, required this.floorName});

  final String label;
  final String roomName;
  final String floorName;

  factory BedInfo.fromJson(Map<String, dynamic> json) =>
      BedInfo(label: json['label'] as String, roomName: json['room_name'] as String, floorName: json['floor_name'] as String);

  Map<String, dynamic> toJson() => {'label': label, 'room_name': roomName, 'floor_name': floorName};
}

class Allocation {
  const Allocation({required this.checkInDate});
  final String checkInDate;

  factory Allocation.fromJson(Map<String, dynamic> json) => Allocation(checkInDate: shortDate(json['check_in_date'] as String));

  Map<String, dynamic> toJson() => {'check_in_date': checkInDate};
}

/// Mirrors tenant-service's `Agreement` schema. `GET /tenant/me/rental` returns the raw
/// `rent_agreements` row (see tenantSelf.ts), so agreementId/terms are always present
/// even though the manager-facing serializeAgreement's DTO isn't what's used here.
class Agreement {
  const Agreement({
    required this.agreementId,
    required this.status,
    required this.monthlyRent,
    required this.securityDeposit,
    required this.startDate,
    required this.endDate,
    required this.terms,
  });

  final String agreementId;
  final String status;
  final int monthlyRent;
  final int securityDeposit;
  final String startDate;
  final String? endDate;
  final String terms;

  factory Agreement.fromJson(Map<String, dynamic> json) => Agreement(
    agreementId: json['agreement_id'] as String,
    status: json['status'] as String,
    monthlyRent: json['monthly_rent'] as int,
    securityDeposit: json['security_deposit'] as int,
    startDate: shortDate(json['start_date'] as String),
    endDate: json['end_date'] != null ? shortDate(json['end_date'] as String) : null,
    terms: json['terms'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'agreement_id': agreementId,
    'status': status,
    'monthly_rent': monthlyRent,
    'security_deposit': securityDeposit,
    'start_date': startDate,
    'end_date': ?endDate,
    'terms': terms,
  };
}

class BillingProfile {
  const BillingProfile({required this.amount, required this.cycleType});
  final int amount;
  final String cycleType;

  factory BillingProfile.fromJson(Map<String, dynamic> json) =>
      BillingProfile(amount: json['amount'] as int, cycleType: json['cycle_type'] as String);

  Map<String, dynamic> toJson() => {'amount': amount, 'cycle_type': cycleType};
}

class RentalInfo {
  const RentalInfo({this.allocation, this.bed, this.agreement, this.billingProfile});

  final Allocation? allocation;
  final BedInfo? bed;
  final Agreement? agreement;
  final BillingProfile? billingProfile;

  factory RentalInfo.fromJson(Map<String, dynamic> json) => RentalInfo(
    allocation: json['allocation'] != null ? Allocation.fromJson(json['allocation'] as Map<String, dynamic>) : null,
    bed: json['bed'] != null ? BedInfo.fromJson(json['bed'] as Map<String, dynamic>) : null,
    agreement: json['agreement'] != null ? Agreement.fromJson(json['agreement'] as Map<String, dynamic>) : null,
    billingProfile: json['billing_profile'] != null ? BillingProfile.fromJson(json['billing_profile'] as Map<String, dynamic>) : null,
  );

  Map<String, dynamic> toJson() => {
    'allocation': allocation?.toJson(),
    'bed': bed?.toJson(),
    'agreement': agreement?.toJson(),
    'billing_profile': billingProfile?.toJson(),
  };
}

/// Combines tenant-service's `/tenant/me/rental` (allocation/bed/agreement) with
/// billing-service's `/tenant/me/billing-profile` — two services, two calls, same shape
/// AddTenantModal-style screens on the owner-dashboard side already fan out to several
/// services in parallel.
class RentalRepository {
  RentalRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<RentalInfo> fetch(String token) async {
    final results = await Future.wait([
      _api.get('/api/tenants/v1/tenant/me/rental', token: token),
      _api.get('/api/billing/v1/tenant/me/billing-profile', token: token),
    ]);
    final rental = results[0];
    final billing = results[1];

    final allocationJson = rental['allocation'] as Map<String, dynamic>?;
    final bedJson = rental['bed'] as Map<String, dynamic>?;
    final agreementJson = rental['agreement'] as Map<String, dynamic>?;
    final billingProfileJson = billing['billing_profile'] as Map<String, dynamic>?;

    return RentalInfo(
      allocation: allocationJson != null ? Allocation.fromJson(allocationJson) : null,
      bed: bedJson != null ? BedInfo.fromJson(bedJson) : null,
      agreement: agreementJson != null ? Agreement.fromJson(agreementJson) : null,
      billingProfile: billingProfileJson != null ? BillingProfile.fromJson(billingProfileJson) : null,
    );
  }

  /// The tenant-initiated e-sign path (tenant-service's POST /tenant/me/agreements/:id/
  /// sign) — typed name + explicit consent, no document upload. Returns the updated
  /// Agreement so the caller can refresh its view without a second round trip.
  Future<Agreement> signAgreement(String token, {required String agreementId, required String signedByName}) async {
    final result = await _api.post(
      '/api/tenants/v1/tenant/me/agreements/$agreementId/sign',
      {'signed_by_name': signedByName, 'accepted': true},
      token: token,
    );
    return Agreement.fromJson(result);
  }
}
