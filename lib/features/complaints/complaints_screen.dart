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
import '../../widgets/pavio_skeleton.dart';
import '../../widgets/pavio_stale_banner.dart';
import '../auth/auth_repository.dart';
import '../rental/rental_repository.dart';
import 'complaint_detail_screen.dart';
import 'complaints_repository.dart';

const _cardTitleStyle = TextStyle(
  fontFamily: 'Noto Sans',
  fontSize: 16,
  fontWeight: FontWeight.w600,
  height: 1.35,
  color: PavioColors.ink900,
);
const _cardSubtitleStyle = TextStyle(
  fontFamily: 'Noto Sans',
  fontSize: 14,
  fontWeight: FontWeight.w400,
  height: 1.5,
  color: PavioColors.ink700,
);

enum _WhenFilter { open, resolved }

/// Which coloured spine a card gets — a second signal beyond the pill (1e's own reasoning:
/// "the badge isn't the only signal").
Color _spineColor(String status) => switch (status) {
  'resolved' => PavioColors.positiveFg,
  'in_progress' => PavioColors.infoFg,
  _ => PavioColors.warningFg,
};

/// Redesigned (doc option "1e") from an unfiltered list of bordered cards into: an Open/
/// Resolved segmented filter, each card a coloured-spine "door" (not just a badge) whose
/// footer previews the latest reply inline (or "No reply yet") and a chevron into the
/// thread already built for IA-9, and the FAB replaced with a bottom bar that can't cover
/// the last row (TT-3). Dates were already relative-formatted before this pass
/// ([formatRelativeDate] added here) and cards were already tappable (IA-9, complaint_
/// notes migration 036) — this redesign is the visual language the data was waiting on.
class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({
    super.key,
    this.authRepository,
    this.complaintsRepository,
    this.rentalRepository,
    this.cacheStore,
  });

  final AuthRepository? authRepository;
  final ComplaintsRepository? complaintsRepository;
  final RentalRepository? rentalRepository;
  final CacheStore? cacheStore;

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final ComplaintsRepository _complaints =
      widget.complaintsRepository ?? ComplaintsRepository();
  late final RentalRepository _rentals =
      widget.rentalRepository ?? RentalRepository();
  late final CacheStore _cache =
      widget.cacheStore ?? const SharedPreferencesCacheStore();

  String? _token;
  List<Complaint> _items = [];
  String? _roomName;
  bool _loading = true;
  bool _stale = false;
  DateTime? _lastSyncedAt;
  String? _error;
  _WhenFilter _filter = _WhenFilter.open;

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
      await _loadRoomName();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(
        () => _error = 'Could not load your maintenance requests — try again',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Best-effort, same "don't take down the part of the screen that matters" reasoning as
  // PaymentsScreen's _loadTransactions — a room name is decoration on the card subtitle,
  // not something worth an error state of its own. Shares Lease's own 'rental_info' cache
  // key: both screens cache the exact same RentalInfo shape for the exact same tenant.
  Future<void> _loadRoomName() async {
    try {
      final result = await fetchWithCache<RentalInfo>(
        cache: _cache,
        cacheKey: 'rental_info',
        fetchNetwork: () => _rentals.fetch(_token!),
        toJson: (r) => r.toJson(),
        fromJson: (json) => RentalInfo.fromJson(json as Map<String, dynamic>),
      );
      if (!mounted) return;
      setState(() => _roomName = result.data.bed?.roomName);
    } catch (_) {
      // Subtitle just omits the room; see comment above.
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
    final openItems = _items.where((c) => c.status != 'resolved').toList();
    final resolvedItems = _items.where((c) => c.status == 'resolved').toList();
    final visibleItems = _filter == _WhenFilter.open
        ? openItems
        : resolvedItems;

    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance')),
      body: SafeArea(
        child: _loading
            ? const PavioSkeletonList()
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(PavioSpacing.s24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        style: PavioText.body.copyWith(
                          color: PavioColors.ink500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: PavioSpacing.s16),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PavioSpacing.s24,
                      PavioSpacing.s16,
                      PavioSpacing.s24,
                      0,
                    ),
                    child: _WhenSegmentedControl(
                      filter: _filter,
                      openCount: openItems.length,
                      resolvedCount: resolvedItems.length,
                      onChanged: (f) => setState(() => _filter = f),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: visibleItems.isEmpty
                          ? ListView(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(
                                    PavioSpacing.s24,
                                  ),
                                  child: Text(
                                    _filter == _WhenFilter.open
                                        ? 'No open requests — tap "New request" to raise one.'
                                        : 'No resolved requests yet.',
                                    style: PavioText.body.copyWith(
                                      color: PavioColors.ink500,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                PavioSpacing.s24,
                                PavioSpacing.s20,
                                PavioSpacing.s24,
                                PavioSpacing.s24,
                              ),
                              itemCount: visibleItems.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: PavioSpacing.s12),
                              itemBuilder: (context, index) {
                                final item = visibleItems[index];
                                return _ComplaintCard(
                                  complaint: item,
                                  roomName: _roomName,
                                  onTap: () => Navigator.of(context)
                                      .push(
                                        MaterialPageRoute(
                                          builder: (_) => ComplaintDetailScreen(
                                            complaint: item,
                                            authRepository: _auth,
                                            complaintsRepository: _complaints,
                                          ),
                                        ),
                                      )
                                      .then((_) => _load()),
                                );
                              },
                            ),
                    ),
                  ),
                  _NewRequestBar(onPressed: _openNewComplaintSheet),
                ],
              ),
      ),
    );
  }
}

class _WhenSegmentedControl extends StatelessWidget {
  const _WhenSegmentedControl({
    required this.filter,
    required this.openCount,
    required this.resolvedCount,
    required this.onChanged,
  });

  final _WhenFilter filter;
  final int openCount;
  final int resolvedCount;
  final ValueChanged<_WhenFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: PavioColors.canvas,
        borderRadius: BorderRadius.circular(PavioRadius.button),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(context, 'Open · $openCount', _WhenFilter.open),
          ),
          Expanded(
            child: _segment(
              context,
              'Resolved · $resolvedCount',
              _WhenFilter.resolved,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, _WhenFilter value) {
    final active = filter == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? PavioColors.white : null,
          borderRadius: BorderRadius.circular(7),
          boxShadow: active ? PavioElevation.e1 : null,
        ),
        child: Text(
          label,
          style: PavioText.body.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: active ? PavioColors.ink900 : PavioColors.ink500,
          ),
        ),
      ),
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({
    required this.complaint,
    required this.roomName,
    required this.onTap,
  });

  final Complaint complaint;
  final String? roomName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (badgeBg, badgeFg) = complaintStatusColors(complaint.status);
    final latestNote = complaint.latestNote;
    return InkWell(
      borderRadius: BorderRadius.circular(PavioRadius.card),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: PavioColors.white,
          border: Border.all(color: PavioColors.line),
          borderRadius: BorderRadius.circular(PavioRadius.card),
          boxShadow: PavioElevation.e1,
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: _spineColor(complaint.status)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(PavioSpacing.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(
                                PavioRadius.pill,
                              ),
                            ),
                            child: Text(
                              complaintStatusLabels[complaint.status] ??
                                  complaint.status,
                              style: PavioText.badge.copyWith(color: badgeFg),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            formatRelativeDate(complaint.createdAt),
                            style: PavioText.caption,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        complaint.description,
                        style: _cardTitleStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        roomName != null
                            ? '${complaint.category} · Room $roomName'
                            : complaint.category,
                        style: _cardSubtitleStyle,
                      ),
                      const SizedBox(height: PavioSpacing.s12),
                      if (latestNote != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: PavioColors.surface,
                            borderRadius: BorderRadius.circular(
                              PavioRadius.md,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.chat_outlined,
                                size: 16,
                                color: PavioColors.ink500,
                              ),
                              const SizedBox(width: PavioSpacing.s8),
                              Expanded(
                                child: Text(
                                  '${latestNote.authorName ?? (latestNote.authorType == 'manager' ? 'Property manager' : 'You')}: ${latestNote.body}',
                                  style: PavioText.bodySmall.copyWith(
                                    color: PavioColors.ink700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: PavioColors.ink400,
                              ),
                            ],
                          ),
                        )
                      else
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule,
                              size: 16,
                              color: PavioColors.ink400,
                            ),
                            const SizedBox(width: PavioSpacing.s8),
                            Expanded(
                              child: Text(
                                'No reply yet',
                                style: PavioText.bodySmall.copyWith(
                                  color: PavioColors.ink500,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: PavioColors.ink400,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinned in the thumb zone instead of a floating FAB that could sit on top of the last
/// card in the list (TT-3) — same Column+Expanded footer pattern as Payments' _PayBar.
class _NewRequestBar extends StatelessWidget {
  const _NewRequestBar({required this.onPressed});

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
          label: const Text('New request'),
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
            Text('New request', style: PavioText.h2),
            const SizedBox(height: PavioSpacing.s16),
            Text('Category', style: PavioText.label),
            const SizedBox(height: PavioSpacing.s8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              items: [
                for (final c in complaintCategories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: PavioSpacing.s16),
            Text('Description', style: PavioText.label),
            const SizedBox(height: PavioSpacing.s8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              style: PavioText.body,
              decoration: InputDecoration(
                hintText: 'Describe the issue',
                errorText: _error,
              ),
            ),
            const SizedBox(height: PavioSpacing.s24),
            PavioPrimaryButton(
              label: 'Submit',
              loading: _submitting,
              loadingLabel: 'Submitting…',
              onPressed: _submit,
            ),
            const SizedBox(height: PavioSpacing.s8),
          ],
        ),
      ),
    );
  }
}
