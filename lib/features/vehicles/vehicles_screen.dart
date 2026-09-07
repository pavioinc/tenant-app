import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../../widgets/nivasa_skeleton.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import 'vehicles_repository.dart';

const _vehicleTypeIcons = {
  'bike': Icons.two_wheeler,
  'car': Icons.directions_car,
};

IconData _vehicleIcon(String type) => _vehicleTypeIcons[type] ?? Icons.commute;

/// Redesigned (doc option "1h") — plates move from `h3` proportional text into
/// `NivasaText.mono` (the "scanned digit-by-digit" case its own doc comment names,
/// never actually used here before this pass), each row gets a type icon and an
/// overflow menu instead of a bare red delete icon, and — since this list is
/// realistically one or two rows — "Add a vehicle" becomes an inline dashed row in the
/// content flow rather than a FAB floating over content that short.
class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({
    super.key,
    this.authRepository,
    this.vehiclesRepository,
    this.cacheStore,
  });

  final AuthRepository? authRepository;
  final VehiclesRepository? vehiclesRepository;
  final CacheStore? cacheStore;

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final VehiclesRepository _vehicles =
      widget.vehiclesRepository ?? VehiclesRepository();
  late final CacheStore _cache =
      widget.cacheStore ?? const SharedPreferencesCacheStore();

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
        fromJson: (json) => (json as List)
            .map((v) => Vehicle.fromJson(v as Map<String, dynamic>))
            .toList(),
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
        content: Text(
          '"${vehicle.plateNumber}" will be permanently removed. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _vehicles.delete(_token!, vehicle.vehicleId);
      if (!mounted) return;
      setState(
        () => _items = _items
            .where((v) => v.vehicleId != vehicle.vehicleId)
            .toList(),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove — try again')),
      );
    }
  }

  Future<void> _openAddSheet() async {
    if (_token == null) return;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AddVehicleSheet(token: _token!, vehiclesRepository: _vehicles),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicles')),
      body: SafeArea(
        child: _loading
            ? const NivasaSkeletonList()
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : Column(
                children: [
                  if (_stale)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        NivasaSpacing.s24,
                        NivasaSpacing.s24,
                        NivasaSpacing.s24,
                        0,
                      ),
                      child: NivasaStaleBanner(
                        lastSyncedAt: _lastSyncedAt,
                        onRetry: _load,
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(NivasaSpacing.s24),
                        children: [
                          if (_items.isEmpty)
                            Text(
                              'No vehicles yet — tap "Add a vehicle" below to add one.',
                              style: NivasaText.body.copyWith(
                                color: NivasaColors.ink500,
                              ),
                            )
                          else ...[
                            Container(
                              decoration: BoxDecoration(
                                color: NivasaColors.white,
                                border: Border.all(color: NivasaColors.line),
                                borderRadius: BorderRadius.circular(
                                  NivasaRadius.card,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (var i = 0; i < _items.length; i++) ...[
                                    _VehicleRow(
                                      vehicle: _items[i],
                                      onDelete: () => _delete(_items[i]),
                                    ),
                                    if (i != _items.length - 1)
                                      const Divider(
                                        height: 1,
                                        indent: 70,
                                        color: NivasaColors.line,
                                      ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: NivasaSpacing.s16),
                          ],
                          _AddVehicleDashedRow(onTap: _openAddSheet),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({required this.vehicle, required this.onDelete});

  final Vehicle vehicle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: NivasaColors.primary50,
              borderRadius: BorderRadius.circular(NivasaRadius.md),
            ),
            child: Icon(
              _vehicleIcon(vehicle.vehicleType),
              size: 21,
              color: NivasaColors.primary700,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vehicle.plateNumber,
                  style: NivasaText.mono.copyWith(
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    vehicleTypeLabel(vehicle.vehicleType),
                    if (vehicle.color != null) vehicle.color!,
                  ].join(' · '),
                  style: NivasaText.caption,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: NivasaColors.ink500),
            color: NivasaColors.ink900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NivasaRadius.lg),
            ),
            onSelected: (_) => onDelete(),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'delete',
                height: 46,
                child: Row(
                  children: [
                    const Icon(
                      Icons.delete_outline,
                      size: 19,
                      color: NivasaColors.negativeTintBorder,
                    ),
                    const SizedBox(width: NivasaSpacing.s12),
                    Text(
                      'Delete…',
                      style: NivasaText.body.copyWith(
                        color: NivasaColors.negativeTintBorder,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hand-rolled rather than a `dotted_border` dependency — one dashed rounded-rect
/// stroke is little enough code to not be worth a new package for it. Stroke width,
/// radius, and dash pattern are fixed to this one call site's needs rather than
/// exposed as parameters nothing here varies.
class _DashedRRectBorderPainter extends CustomPainter {
  const _DashedRRectBorderPainter({required this.color});

  final Color color;

  static const _strokeWidth = 1.5;
  static const _dashWidth = 5.0;
  static const _gapWidth = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _strokeWidth / 2,
        _strokeWidth / 2,
        size.width - _strokeWidth,
        size.height - _strokeWidth,
      ),
      const Radius.circular(NivasaRadius.button),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _AddVehicleDashedRow extends StatelessWidget {
  const _AddVehicleDashedRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedRRectBorderPainter(color: NivasaColors.ink300),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NivasaRadius.button),
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, size: 19, color: NivasaColors.primary700),
                const SizedBox(width: NivasaSpacing.s8),
                Text(
                  'Add a vehicle',
                  style: NivasaText.body.copyWith(
                    color: NivasaColors.primary700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddVehicleSheet extends StatefulWidget {
  const _AddVehicleSheet({
    required this.token,
    required this.vehiclesRepository,
  });

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
        color: _colorController.text.trim().isEmpty
            ? null
            : _colorController.text.trim(),
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(NivasaSpacing.s24),
        decoration: const BoxDecoration(
          color: NivasaColors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(NivasaRadius.bottomSheetTop),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: NivasaSpacing.s16),
                color: NivasaColors.line,
              ),
            ),
            Text('Add vehicle', style: NivasaText.h2),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Plate number', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            TextField(
              controller: _plateController,
              style: NivasaText.body,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Type', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            DropdownButtonFormField<String>(
              initialValue: _vehicleType,
              items: [
                for (final t in vehicleTypes)
                  DropdownMenuItem(value: t, child: Text(vehicleTypeLabel(t))),
              ],
              onChanged: (value) =>
                  setState(() => _vehicleType = value ?? _vehicleType),
            ),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Color (optional)', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            TextField(
              controller: _colorController,
              style: NivasaText.body,
              decoration: InputDecoration(errorText: _error),
            ),
            const SizedBox(height: NivasaSpacing.s24),
            NivasaPrimaryButton(
              label: 'Add',
              loading: _submitting,
              loadingLabel: 'Adding…',
              onPressed: _submit,
            ),
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
            Text(
              message,
              style: NivasaText.body.copyWith(color: NivasaColors.ink500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NivasaSpacing.s16),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
