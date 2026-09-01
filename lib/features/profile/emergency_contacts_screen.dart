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
import 'emergency_contacts_repository.dart';

/// UserScreen's "Emergency Contacts" row (2026-08-27 redesign) — a real add/update/delete
/// list backed by tenant-service's `/tenant/me/emergency-contacts`, replacing the old
/// single-contact form built against tenants.emergency_contact_*. Same list/add/delete
/// shape as VehiclesScreen, plus an edit path the vehicle screen doesn't need.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key, this.authRepository, this.emergencyContactsRepository, this.cacheStore});

  final AuthRepository? authRepository;
  final EmergencyContactsRepository? emergencyContactsRepository;
  final CacheStore? cacheStore;

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final EmergencyContactsRepository _contacts = widget.emergencyContactsRepository ?? EmergencyContactsRepository();
  // Secure, not SharedPreferences — same PII reasoning as the old single-contact cache
  // entry this replaces (see cache_store.dart's SecureCacheStore doc).
  late final CacheStore _cache = widget.cacheStore ?? const SecureCacheStore();

  String? _token;
  List<EmergencyContact> _items = [];
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
      final result = await fetchWithCache<List<EmergencyContact>>(
        cache: _cache,
        cacheKey: 'emergency_contacts',
        fetchNetwork: () => _contacts.list(_token!),
        toJson: (items) => items.map((c) => c.toJson()).toList(),
        fromJson: (json) => (json as List).map((c) => EmergencyContact.fromJson(c as Map<String, dynamic>)).toList(),
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
      setState(() => _error = 'Could not load your emergency contacts — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(EmergencyContact contact) async {
    if (_token == null) return;
    try {
      await _contacts.delete(_token!, contact.contactId);
      if (!mounted) return;
      setState(() => _items = _items.where((c) => c.contactId != contact.contactId).toList());
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove — try again')));
    }
  }

  /// Reloads the whole list on success rather than patching [_items] locally — setting a
  /// new primary also clears whichever contact was primary before, and re-fetching is the
  /// simplest way to reflect that server-side side effect correctly.
  Future<void> _setPrimary(EmergencyContact contact) async {
    if (_token == null) return;
    try {
      await _contacts.setPrimary(_token!, contact.contactId);
      if (!mounted) return;
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update — try again')));
    }
  }

  Future<void> _openAddSheet() async {
    if (_token == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactSheet(token: _token!, repository: _contacts),
    );
    if (saved == true) _load();
  }

  Future<void> _openEditSheet(EmergencyContact contact) async {
    if (_token == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactSheet(token: _token!, repository: _contacts, existing: contact),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Contacts')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _openAddSheet, label: const Text('Add contact'), icon: const Icon(Icons.add)),
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
                                    'No emergency contacts yet — tap "Add contact" to add one.',
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
                                return InkWell(
                                  onTap: () => _openEditSheet(item),
                                  borderRadius: BorderRadius.circular(NivasaRadius.card),
                                  child: Container(
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
                                              Row(
                                                children: [
                                                  Flexible(child: Text(item.name, style: NivasaText.h3, overflow: TextOverflow.ellipsis)),
                                                  if (item.isPrimary) ...[
                                                    const SizedBox(width: NivasaSpacing.s8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(color: NivasaColors.primary50, borderRadius: BorderRadius.circular(NivasaRadius.pill)),
                                                      child: Text(
                                                        'Primary',
                                                        style: NivasaText.badge.copyWith(color: NivasaColors.primary700),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: NivasaSpacing.s4),
                                              Text(
                                                [item.phone, if (item.relationship != null) item.relationship!].join(' · '),
                                                style: NivasaText.bodySmall.copyWith(color: NivasaColors.ink500),
                                              ),
                                              if (!item.isPrimary) ...[
                                                const SizedBox(height: NivasaSpacing.s8),
                                                Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: TextButton(
                                                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                                    onPressed: () => _setPrimary(item),
                                                    child: const Text('Set as primary'),
                                                  ),
                                                ),
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

class _ContactSheet extends StatefulWidget {
  const _ContactSheet({required this.token, required this.repository, this.existing});

  final String token;
  final EmergencyContactsRepository repository;
  final EmergencyContact? existing;

  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _phoneController = TextEditingController(text: widget.existing?.phone ?? '');
  late final _relationshipController = TextEditingController(text: widget.existing?.relationship ?? '');
  bool _submitting = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Name and phone are required');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final relationship = _relationshipController.text.trim().isEmpty ? null : _relationshipController.text.trim();
    try {
      if (_isEditing) {
        await widget.repository.update(widget.token, widget.existing!.contactId, name: name, phone: phone, relationship: relationship);
      } else {
        await widget.repository.add(widget.token, name: name, phone: phone, relationship: relationship);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save — try again');
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
            Text(_isEditing ? 'Edit contact' : 'Add contact', style: NivasaText.h2),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Name', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            TextField(controller: _nameController, style: NivasaText.body),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Phone', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            TextField(controller: _phoneController, keyboardType: TextInputType.phone, style: NivasaText.body),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Relationship (optional)', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            TextField(
              controller: _relationshipController,
              style: NivasaText.body,
              decoration: InputDecoration(hintText: 'e.g. Parent, Spouse, Sibling', errorText: _error),
            ),
            const SizedBox(height: NivasaSpacing.s24),
            NivasaPrimaryButton(
              label: _isEditing ? 'Save' : 'Add',
              loading: _submitting,
              loadingLabel: _isEditing ? 'Saving…' : 'Adding…',
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
            Text(message, style: NivasaText.body.copyWith(color: NivasaColors.ink500), textAlign: TextAlign.center),
            const SizedBox(height: NivasaSpacing.s16),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
