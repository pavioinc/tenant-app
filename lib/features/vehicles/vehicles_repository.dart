import '../../core/api_client.dart';

const vehicleTypes = ['car', 'bike', 'other'];

const _vehicleTypeLabels = {'car': 'Car', 'bike': 'Bike', 'other': 'Other'};

String vehicleTypeLabel(String type) => _vehicleTypeLabels[type] ?? type;

class Vehicle {
  const Vehicle({required this.vehicleId, required this.plateNumber, required this.vehicleType, this.color});

  final String vehicleId;
  final String plateNumber;
  final String vehicleType;
  final String? color;

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
    vehicleId: json['vehicle_id'] as String,
    plateNumber: json['plate_number'] as String,
    vehicleType: json['vehicle_type'] as String,
    color: json['color'] as String?,
  );

  Map<String, dynamic> toJson() => {'vehicle_id': vehicleId, 'plate_number': plateNumber, 'vehicle_type': vehicleType, 'color': ?color};
}

/// tenant-service's `/tenant/me/vehicles` — tenant-owned CRUD, no manager-facing view.
class VehiclesRepository {
  VehiclesRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<Vehicle>> list(String token) async {
    final body = await _api.get('/api/tenants/v1/tenant/me/vehicles', token: token);
    final vehicles = body['vehicles'] as List;
    return vehicles.map((v) => Vehicle.fromJson(v as Map<String, dynamic>)).toList();
  }

  Future<Vehicle> add(String token, {required String plateNumber, required String vehicleType, String? color}) async {
    final body = await _api.post('/api/tenants/v1/tenant/me/vehicles', {
      'plate_number': plateNumber,
      'vehicle_type': vehicleType,
      'color': ?color,
    }, token: token);
    return Vehicle.fromJson(body);
  }

  Future<void> delete(String token, String vehicleId) async {
    await _api.delete('/api/tenants/v1/tenant/me/vehicles/$vehicleId', token: token);
  }
}
