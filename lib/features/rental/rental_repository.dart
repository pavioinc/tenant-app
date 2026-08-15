import '../../core/api_client.dart';
import '../../core/date_utils.dart';

class BedInfo {
  const BedInfo({required this.label, required this.roomName, required this.floorName});

  final String label;
  final String roomName;
  final String floorName;

  factory BedInfo.fromJson(Map<String, dynamic> json) =>
      BedInfo(label: json['label'] as String, roomName: json['room_name'] as String, floorName: json['floor_name'] as String);
}

class Allocation {
  const Allocation({required this.checkInDate});
  final String checkInDate;

  factory Allocation.fromJson(Map<String, dynamic> json) => Allocation(checkInDate: shortDate(json['check_in_date'] as String));
}

/// Mirrors tenant-service's `Agreement` schema (src/routes/agreements.ts's serializeAgreement).
class Agreement {
  const Agreement({
    required this.status,
    required this.monthlyRent,
    required this.securityDeposit,
    required this.startDate,
    required this.endDate,
  });

  final String status;
  final int monthlyRent;
  final int securityDeposit;
  final String startDate;
  final String? endDate;

  factory Agreement.fromJson(Map<String, dynamic> json) => Agreement(
    status: json['status'] as String,
    monthlyRent: json['monthly_rent'] as int,
    securityDeposit: json['security_deposit'] as int,
    startDate: shortDate(json['start_date'] as String),
    endDate: json['end_date'] != null ? shortDate(json['end_date'] as String) : null,
  );
}

class BillingProfile {
  const BillingProfile({required this.amount, required this.cycleType});
  final int amount;
  final String cycleType;

  factory BillingProfile.fromJson(Map<String, dynamic> json) =>
      BillingProfile(amount: json['amount'] as int, cycleType: json['cycle_type'] as String);
}

class RentalInfo {
  const RentalInfo({this.allocation, this.bed, this.agreement, this.billingProfile});

  final Allocation? allocation;
  final BedInfo? bed;
  final Agreement? agreement;
  final BillingProfile? billingProfile;
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
}
