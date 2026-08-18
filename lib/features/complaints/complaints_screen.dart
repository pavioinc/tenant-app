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
import 'complaints_repository.dart';

const _statusLabels = {
  'open': 'Open',
  'in_progress': 'In progress',
  'resolved': 'Resolved',
};

(Color, Color) _statusColors(String status) => switch (status) {
  'resolved' => (NivasaColors.positiveTint, NivasaColors.positiveTextOnTint),
  'in_progress' => (NivasaColors.infoTint, NivasaColors.infoTextOnTint),
  _ => (NivasaColors.warningTint, NivasaColors.warningTextOnTint),
};

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({
    super.key,
    this.authRepository,
    this.complaintsRepository,
    this.cacheStore,
  });

  final AuthRepository? authRepository;
  final ComplaintsRepository? complaintsRepository;
  final CacheStore? cacheStore;

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final ComplaintsRepository _complaints =
      widget.complaintsRepository ?? ComplaintsRepository();
  late final CacheStore _cache =
      widget.cacheStore ?? const SharedPreferencesCacheStore();

  String? _token;
  List<Complaint> _items = [];
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
      final result = await fetchWithCache<List<Complaint>>(
        cache: _cache,
        cacheKey: 'complaints',
        fetchNetwork: () => _complaints.list(_token!),
        toJson: (items) => items.map((c) => c.toJson()).toList(),
        fromJson: (json) => (json as List)
            .map((c) => Complaint.fromJson(c as Map<String, dynamic>))
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
      setState(() => _error = 'Could not load your complaints — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNewComplaintSheet() async {
    if (_token == null) return;
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _NewComplaintSheet(token: _token!, complaintsRepository: _complaints),
    );
    if (submitted == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complaints')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewComplaintSheet,
        label: const Text('New complaint'),
        icon: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(NivasaSpacing.s24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        style: NivasaText.body.copyWith(
                          color: NivasaColors.ink500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: NivasaSpacing.s16),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              )
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
                      child: NivasaStaleBanner(lastSyncedAt: _lastSyncedAt),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _items.isEmpty
                          ? ListView(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(
                                    NivasaSpacing.s24,
                                  ),
                                  child: Text(
                                    'No complaints yet — tap "New complaint" to raise one.',
                                    style: NivasaText.body.copyWith(
                                      color: NivasaColors.ink500,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(NivasaSpacing.s24),
                              itemCount: _items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: NivasaSpacing.s12),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                final (bg, fg) = _statusColors(item.status);
                                return Container(
                                  padding: const EdgeInsets.all(
                                    NivasaSpacing.s16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: NivasaColors.white,
                                    border: Border.all(
                                      color: NivasaColors.line,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.category,
                                              style: NivasaText.h3,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: bg,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              _statusLabels[item.status] ??
                                                  item.status,
                                              style: NivasaText.body.copyWith(
                                                color: fg,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: NivasaSpacing.s8),
                                      Text(
                                        item.description,
                                        style: NivasaText.body,
                                      ),
                                      const SizedBox(height: NivasaSpacing.s4),
                                      Text(
                                        item.createdAt,
                                        style: NivasaText.body.copyWith(
                                          color: NivasaColors.ink500,
                                          fontSize: 12,
                                        ),
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

class _NewComplaintSheet extends StatefulWidget {
  const _NewComplaintSheet({
    required this.token,
    required this.complaintsRepository,
  });

  final String token;
  final ComplaintsRepository complaintsRepository;

  @override
  State<_NewComplaintSheet> createState() => _NewComplaintSheetState();
}

class _NewComplaintSheetState extends State<_NewComplaintSheet> {
  String _category = complaintCategories.first;
  final _descriptionController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _error = 'Describe the issue');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.complaintsRepository.submit(
        widget.token,
        category: _category,
        description: _descriptionController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not submit — try again');
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
            Text('New complaint', style: NivasaText.h2),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Category', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              items: [
                for (final c in complaintCategories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: NivasaSpacing.s16),
            Text('Description', style: NivasaText.label),
            const SizedBox(height: NivasaSpacing.s8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              style: NivasaText.body,
              decoration: InputDecoration(
                hintText: 'Describe the issue',
                errorText: _error,
              ),
            ),
            const SizedBox(height: NivasaSpacing.s24),
            NivasaPrimaryButton(
              label: 'Submit',
              loading: _submitting,
              loadingLabel: 'Submitting…',
              onPressed: _submit,
            ),
            const SizedBox(height: NivasaSpacing.s8),
          ],
        ),
      ),
    );
  }
}
