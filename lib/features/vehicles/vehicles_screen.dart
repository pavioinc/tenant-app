import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import 'vehicles_repository.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key, this.authRepository, this.vehiclesRepository, this.cacheStore});

  final AuthRepository? authRepository;
  final VehiclesRepository? vehiclesRepository;
  final CacheStore? cacheStore;

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final VehiclesRepository _vehicles = widget.vehiclesRepository ?? VehiclesRepository();
  late final CacheStore _cache = widget.cacheStore ?? const SharedPreferencesCacheStore();

  String? _token;
  List<Vehicle> _items = [];
  bool _loading = true;
  bool _stale = false;
  DateTime? _lastSyncedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await _auth.currentSession();
      if (session == null) throw StateError('no active session');
      _token = session.accessToken;
      final result = await fetchWithCache<List<Vehicle>>(
        cache: _cache,
        cacheKey: 'vehicles',
        fetchNetwork: () => _vehicles.list(_token!),
        toJson: (items) => items.map((v) => v.toJson()).toList(),
        fromJson: (json) => (json as List).map((v) => Vehicle.fromJson(v as Map<String, dynamic>)).toList(),
      );
      if (!mounted) return;
      setState(() {
        _items = result.data;
        _stale = result.stale;
        _lastSyncedAt = result.lastSyncedAt;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your vehicles — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Vehicle vehicle) async {
    if (_token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove vehicle?'),
        content: Text('"${vehicle.plateNumber}" will be permanently removed. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _vehicles.delete(_token!, vehicle.vehicleId);
      if (!mounted) return;
      setState(() => _items = _items.where((v) => v.vehicleId != vehicle.vehicleId).toList());
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove — try again')));
    }
  }

  Future<void> _openAddSheet() async {
    if (_token == null) return;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddVehicleSheet(token: _token!, vehiclesRepository: _vehicles),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicles')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _openAddSheet, label: const Text('Add vehicle'), icon: const Icon(Icons.add)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : Column(
                children: [
                  if (_stale)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(NivasaSpacing.s24, NivasaSpacing.s24, NivasaSpacing.s24, 0),
                      child: NivasaStaleBanner(lastSyncedAt: _lastSyncedAt, onRetry: _load),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _items.isEmpty
                          ? ListView(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(NivasaSpacing.s24),
                                  child: Text(
                                    'No vehicles yet — tap "Add vehicle" to add one.',
                                    style: NivasaText.body.copyWith(color: NivasaColors.ink500),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(NivasaSpacing.s24),
                              itemCount: _items.length,
                              separatorBuilder: (_, _) => const SizedBox(height: NivasaSpacing.s12),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return Container(
                                  padding: const EdgeInsets.all(NivasaSpacing.s16),
                                  decoration: BoxDecoration(
                                    color: NivasaColors.white,
                                    border: Border.all(color: NivasaColors.line),
                                    borderRadius: BorderRadius.circular(NivasaRadius.card),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item.plateNumber, style: NivasaText.h3),
                                            const SizedBox(height: NivasaSpacing.s4),
                                            Text(
                                              [vehicleTypeLabel(item.vehicleType), if (item.color != null) item.color!].join(' · '),
                                              style: NivasaText.bodySmall.copyWith(color: NivasaColors.ink500),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline, color: NivasaColors.negativeFg),
                                        tooltip: 'Delete',
                                        onPressed: () => _delete(item),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AddVehicleSheet extends StatefulWidget {
  const _AddVehicleSheet({required this.token, required this.vehiclesRepository});

  final String token;
  final VehiclesRepository vehiclesRepository;

  @override
  State<_AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<_AddVehicleSheet> {
  String _vehicleType = vehicleTypes.first;
  final _plateController = TextEditingController();
  final _colorController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _plateController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_plateController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a plate number');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.vehiclesRepository.add(
        widget.token,
        plateNumber: _plateController.text.trim(),
        vehicleType: _vehicleType,
        color: _colorController.text.trim().isEmpty ? null : _colorController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not add — try again');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(NivasaSpacing.s24),
        decoration: const BoxDecoration(color: NivasaColors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(NivasaRadius.bottomSheetTop))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: NivasaSpacing.s16), color: NivasaColors.line),
            ),
            Text('Add vehicle', style: NivasaText.h2),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Plate number', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            TextField(controller: _plateController, style: NivasaText.body, textCapitalization: TextCapitalization.characters),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Type', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            DropdownButtonFormField<String>(
              initialValue: _vehicleType,
              items: [for (final t in vehicleTypes) DropdownMenuItem(value: t, child: Text(vehicleTypeLabel(t)))],
              onChanged: (value) => setState(() => _vehicleType = value ?? _vehicleType),
            ),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Color (optional)', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            TextField(controller: _colorController, style: NivasaText.body, decoration: InputDecoration(errorText: _error)),
            const SizedBox(height: NivasaSpacing.s24),
            NivasaPrimaryButton(label: 'Add', loading: _submitting, loadingLabel: 'Adding…', onPressed: _submit),
            const SizedBox(height: NivasaSpacing.s8),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NivasaSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: NivasaText.body.copyWith(color: NivasaColors.ink500), textAlign: TextAlign.center),
            const SizedBox(height: NivasaSpacing.s16),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
