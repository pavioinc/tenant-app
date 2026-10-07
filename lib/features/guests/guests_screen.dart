import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../core/date_utils.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_elevation.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_button.dart';
import '../../widgets/pavio_empty_state.dart';
import '../../widgets/pavio_skeleton.dart';
import '../../widgets/pavio_stale_banner.dart';
import '../auth/auth_repository.dart';
import 'guests_repository.dart';

/// "2026-08-24T14:05:00Z" → "2:05 PM", device-local time — matches the format
/// owner-dashboard's own Guests view (CLO-231) uses for "Inside since {time}".
String _formatTime(String isoDateTime) {
  final dt = DateTime.tryParse(isoDateTime)?.toLocal();
  if (dt == null) return isoDateTime;
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$hour12:$minute ${dt.hour < 12 ? 'AM' : 'PM'}';
}

(Color bg, Color fg, String label) _guestStatusVisual(ExpectedGuest guest) {
  return switch (guest.status) {
    'arrived' => (
      PavioColors.positiveTint,
      PavioColors.positiveTextOnTint,
      guest.arrivedAt != null
          ? 'Inside since ${_formatTime(guest.arrivedAt!)}'
          : 'Inside',
    ),
    'departed' => (
      PavioColors.offlineTint,
      PavioColors.offlineTextOnTint,
      guest.departedAt != null
          ? 'Departed ${_formatTime(guest.departedAt!)}'
          : 'Departed',
    ),
    'denied' => (
      PavioColors.negativeTint,
      PavioColors.negativeTextOnTint,
      'Denied entry',
    ),
    _ => (
      PavioColors.offlineTint,
      PavioColors.offlineTextOnTint,
      'Not arrived yet',
    ),
  };
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

/// Redesigned (doc option "1g") — the empty state becomes a first screen: centred icon,
/// a headline that says what the feature is for, one sentence on who can see it, and the
/// action under the thumb instead of a corner FAB a top-left grey sentence quotes
/// (finding ST-3, shared identically across all six list screens; PavioEmptyState is
/// the reusable piece that fix implies). The populated list gets the same bottom-bar
/// treatment as this session's other redesigns, plus the guest's real arrival/departure
/// status (CLO-231) — a tenant asking "did my guest get let in" is exactly what the
/// front desk's own Guests view already answers for a manager.
class GuestsScreen extends StatefulWidget {
  const GuestsScreen({
    super.key,
    this.authRepository,
    this.guestsRepository,
    this.cacheStore,
  });

  final AuthRepository? authRepository;
  final GuestsRepository? guestsRepository;
  final CacheStore? cacheStore;

  @override
  State<GuestsScreen> createState() => _GuestsScreenState();
}

class _GuestsScreenState extends State<GuestsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final GuestsRepository _guests =
      widget.guestsRepository ?? GuestsRepository();
  late final CacheStore _cache =
      widget.cacheStore ?? const SharedPreferencesCacheStore();

  String? _token;
  List<ExpectedGuest> _items = [];
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
      final result = await fetchWithCache<List<ExpectedGuest>>(
        cache: _cache,
        cacheKey: 'guests',
        fetchNetwork: () => _guests.list(_token!),
        toJson: (items) => items.map((g) => g.toJson()).toList(),
        fromJson: (json) => (json as List)
            .map((g) => ExpectedGuest.fromJson(g as Map<String, dynamic>))
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
      setState(() => _error = 'Could not load your guests — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(ExpectedGuest guest) async {
    if (_token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove guest?'),
        content: Text(
          '"${guest.name}" will be removed from your guest list. This can\'t be undone.',
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
      await _guests.delete(_token!, guest.guestId);
      if (!mounted) return;
      setState(
        () => _items = _items.where((g) => g.guestId != guest.guestId).toList(),
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
      builder: (_) => _AddGuestSheet(token: _token!, guestsRepository: _guests),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guests')),
      body: SafeArea(
        child: _loading
            ? const PavioSkeletonList()
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : Column(
                children: [
                  if (_stale)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        PavioSpacing.s24,
                        PavioSpacing.s24,
                        PavioSpacing.s24,
                        0,
                      ),
                      child: PavioStaleBanner(
                        lastSyncedAt: _lastSyncedAt,
                        onRetry: _load,
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _items.isEmpty
                          ? LayoutBuilder(
                              builder: (context, constraints) => ListView(
                                children: [
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight,
                                    ),
                                    child: PavioEmptyState(
                                      icon: Icons.person_add_alt,
                                      title: 'Expecting someone?',
                                      message:
                                          "Add your visitor here and the front desk will know they're coming. Only you and your property manager can see this list.",
                                      actionIcon: Icons.add,
                                      actionLabel: 'Add a guest',
                                      onAction: _openAddSheet,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(PavioSpacing.s24),
                              itemCount: _items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: PavioSpacing.s12),
                              itemBuilder: (context, index) => _GuestCard(
                                guest: _items[index],
                                onDelete: () => _delete(_items[index]),
                              ),
                            ),
                    ),
                  ),
                  if (_items.isNotEmpty) _AddGuestBar(onPressed: _openAddSheet),
                ],
              ),
      ),
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard({required this.guest, required this.onDelete});

  final ExpectedGuest guest;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final (badgeBg, badgeFg, statusLabel) = _guestStatusVisual(guest);
    return Container(
      padding: const EdgeInsets.all(PavioSpacing.s16),
      decoration: BoxDecoration(
        color: PavioColors.white,
        border: Border.all(color: PavioColors.line),
        borderRadius: BorderRadius.circular(PavioRadius.card),
        boxShadow: PavioElevation.e1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: PavioColors.primary50,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _initials(guest.name),
                style: PavioText.badge.copyWith(
                  color: PavioColors.primary700,
                ),
              ),
            ),
          ),
          const SizedBox(width: PavioSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guest.name,
                  style: PavioText.h3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: PavioSpacing.s4),
                Text(
                  [
                    formatDisplayDate(guest.visitDate),
                    if (guest.phone != null) guest.phone!,
                  ].join(' · '),
                  style: PavioText.bodySmall.copyWith(
                    color: PavioColors.ink500,
                  ),
                ),
                const SizedBox(height: PavioSpacing.s8),
                // A badge next to the name overflows once its text is "Inside since
                // 9:05 AM" rather than a single word like "Open" — its own row, so
                // length here never fights the name for space.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(PavioRadius.pill),
                    ),
                    child: Text(
                      statusLabel,
                      style: PavioText.badge.copyWith(color: badgeFg),
                    ),
                  ),
                ),
                if (guest.notes != null) ...[
                  const SizedBox(height: PavioSpacing.s8),
                  Text(guest.notes!, style: PavioText.body),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: PavioColors.negativeFg),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Pinned in the thumb zone instead of a floating FAB — same Column+Expanded footer
/// pattern as this session's other redesigns (Payments/Maintenance/Documents).
class _AddGuestBar extends StatelessWidget {
  const _AddGuestBar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        PavioSpacing.s24,
        PavioSpacing.s12,
        PavioSpacing.s24,
        PavioSpacing.s24,
      ),
      decoration: const BoxDecoration(
        color: PavioColors.white,
        border: Border(top: BorderSide(color: PavioColors.line)),
      ),
      child: SizedBox(
        height: 52,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add a guest'),
        ),
      ),
    );
  }
}

class _AddGuestSheet extends StatefulWidget {
  const _AddGuestSheet({required this.token, required this.guestsRepository});

  final String token;
  final GuestsRepository guestsRepository;

  @override
  State<_AddGuestSheet> createState() => _AddGuestSheetState();
}

class _AddGuestSheetState extends State<_AddGuestSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _visitDate;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickVisitDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _visitDate = picked);
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    if (_visitDate == null) {
      setState(() => _error = 'Pick a visit date');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final visitDate =
          '${_visitDate!.year.toString().padLeft(4, '0')}-${_visitDate!.month.toString().padLeft(2, '0')}-${_visitDate!.day.toString().padLeft(2, '0')}';
      await widget.guestsRepository.add(
        widget.token,
        name: _nameController.text.trim(),
        visitDate: visitDate,
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
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
        padding: const EdgeInsets.all(PavioSpacing.s24),
        decoration: const BoxDecoration(
          color: PavioColors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(PavioRadius.bottomSheetTop),
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
                margin: const EdgeInsets.only(bottom: PavioSpacing.s16),
                color: PavioColors.line,
              ),
            ),
            Text('Add guest', style: PavioText.h2),
            const SizedBox(height: PavioSpacing.s16),
            Text('Name', style: PavioText.label),
            const SizedBox(height: PavioSpacing.s8),
            TextField(controller: _nameController, style: PavioText.body),
            const SizedBox(height: PavioSpacing.s16),
            Text('Phone (optional)', style: PavioText.label),
            const SizedBox(height: PavioSpacing.s8),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: PavioText.body,
            ),
            const SizedBox(height: PavioSpacing.s16),
            TextButton(
              onPressed: _submitting ? null : _pickVisitDate,
              child: Text(
                _visitDate == null
                    ? 'Pick a visit date'
                    : 'Visit date: ${formatDisplayDate('${_visitDate!.year}-${_visitDate!.month.toString().padLeft(2, '0')}-${_visitDate!.day.toString().padLeft(2, '0')}')}',
              ),
            ),
            const SizedBox(height: PavioSpacing.s8),
            Text('Notes (optional)', style: PavioText.label),
            const SizedBox(height: PavioSpacing.s8),
            TextField(
              controller: _notesController,
              maxLines: 2,
              style: PavioText.body,
              decoration: InputDecoration(errorText: _error),
            ),
            const SizedBox(height: PavioSpacing.s24),
            PavioPrimaryButton(
              label: 'Add',
              loading: _submitting,
              loadingLabel: 'Adding…',
              onPressed: _submit,
            ),
            const SizedBox(height: PavioSpacing.s8),
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
        padding: const EdgeInsets.all(PavioSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: PavioText.body.copyWith(color: PavioColors.ink500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: PavioSpacing.s16),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
