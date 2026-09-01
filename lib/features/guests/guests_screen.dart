import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../core/date_utils.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import 'guests_repository.dart';

class GuestsScreen extends StatefulWidget {
  const GuestsScreen({super.key, this.authRepository, this.guestsRepository, this.cacheStore});

  final AuthRepository? authRepository;
  final GuestsRepository? guestsRepository;
  final CacheStore? cacheStore;

  @override
  State<GuestsScreen> createState() => _GuestsScreenState();
}

class _GuestsScreenState extends State<GuestsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final GuestsRepository _guests = widget.guestsRepository ?? GuestsRepository();
  late final CacheStore _cache = widget.cacheStore ?? const SharedPreferencesCacheStore();

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
        fromJson: (json) => (json as List).map((g) => ExpectedGuest.fromJson(g as Map<String, dynamic>)).toList(),
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
        content: Text('"${guest.name}" will be removed from your guest list. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _guests.delete(_token!, guest.guestId);
      if (!mounted) return;
      setState(() => _items = _items.where((g) => g.guestId != guest.guestId).toList());
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
      builder: (_) => _AddGuestSheet(token: _token!, guestsRepository: _guests),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guest Manager')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _openAddSheet, label: const Text('Add guest'), icon: const Icon(Icons.add)),
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
                                    'No expected guests yet — tap "Add guest" to add one.',
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
                                            Text(item.name, style: NivasaText.h3),
                                            const SizedBox(height: NivasaSpacing.s4),
                                            Text(
                                              [formatDisplayDate(item.visitDate), if (item.phone != null) item.phone!].join(' · '),
                                              style: NivasaText.bodySmall.copyWith(color: NivasaColors.ink500),
                                            ),
                                            if (item.notes != null) ...[
                                              const SizedBox(height: NivasaSpacing.s4),
                                              Text(item.notes!, style: NivasaText.body),
                                            ],
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
    final picked = await showDatePicker(context: context, initialDate: _visitDate ?? now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
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
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
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
            Text('Add guest', style: NivasaText.h2),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Name', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            TextField(controller: _nameController, style: NivasaText.body),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Phone (optional)', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            TextField(controller: _phoneController, keyboardType: TextInputType.phone, style: NivasaText.body),
            const SizedBox(height: NivasaSpacing.s16),
            TextButton(
              onPressed: _submitting ? null : _pickVisitDate,
              child: Text(
                _visitDate == null
                    ? 'Pick a visit date'
                    : 'Visit date: ${formatDisplayDate('${_visitDate!.year}-${_visitDate!.month.toString().padLeft(2, '0')}-${_visitDate!.day.toString().padLeft(2, '0')}')}',
              ),
            ),
            const SizedBox(height: NivasaSpacing.s8),
            Text('Notes (optional)', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            TextField(controller: _notesController, maxLines: 2, style: NivasaText.body, decoration: InputDecoration(errorText: _error)),
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
