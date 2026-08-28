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
import '../rental/agreement_sign_screen.dart';
import '../rental/rental_repository.dart';
import '../renewal/renewal_repository.dart';

const _cycleLabels = {'monthly': '/month', 'weekly': '/week', 'daily': '/day'};

String _formatInr(int amountMinor) => '₹${(amountMinor / 100).toStringAsFixed(0)}';

/// Combines the former My rental + Renewal screens into one "Lease" tile (2026-08-18
/// Resident Hub redesign) — same two repositories, unchanged, just one screen instead of
/// two. "Rental offers" has no backing feature yet — shown as a coming-soon section
/// rather than silently dropped, since the user's description of this tile named it
/// explicitly.
class LeaseScreen extends StatefulWidget {
  const LeaseScreen({super.key, this.authRepository, this.rentalRepository, this.renewalRepository, this.cacheStore});

  final AuthRepository? authRepository;
  final RentalRepository? rentalRepository;
  final RenewalRepository? renewalRepository;
  final CacheStore? cacheStore;

  @override
  State<LeaseScreen> createState() => _LeaseScreenState();
}

class _LeaseScreenState extends State<LeaseScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final RentalRepository _rentals = widget.rentalRepository ?? RentalRepository();
  late final RenewalRepository _renewals = widget.renewalRepository ?? RenewalRepository();
  late final CacheStore _cache = widget.cacheStore ?? const SharedPreferencesCacheStore();

  String? _token;
  RentalInfo? _rental;
  List<RenewalRequest> _requests = [];
  DateTime? _preferredEndDate;
  bool _loading = true;
  bool _requesting = false;
  bool _stale = false;
  DateTime? _lastSyncedAt;
  String? _error;

  bool get _hasPending => _requests.any((r) => r.status == 'pending');

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
      final results = await Future.wait([
        fetchWithCache<RentalInfo>(
          cache: _cache,
          cacheKey: 'rental_info',
          fetchNetwork: () => _rentals.fetch(_token!),
          toJson: (r) => r.toJson(),
          fromJson: (json) => RentalInfo.fromJson(json as Map<String, dynamic>),
        ),
        fetchWithCache<List<RenewalRequest>>(
          cache: _cache,
          cacheKey: 'renewal_requests',
          fetchNetwork: () => _renewals.list(_token!),
          toJson: (items) => items.map((r) => r.toJson()).toList(),
          fromJson: (json) => (json as List).map((r) => RenewalRequest.fromJson(r as Map<String, dynamic>)).toList(),
        ),
      ]);
      if (!mounted) return;
      final rentalResult = results[0] as CachedFetch<RentalInfo>;
      final renewalResult = results[1] as CachedFetch<List<RenewalRequest>>;
      final syncTimes = [rentalResult.lastSyncedAt, renewalResult.lastSyncedAt].whereType<DateTime>();
      setState(() {
        _rental = rentalResult.data;
        _requests = renewalResult.data;
        _stale = rentalResult.stale || renewalResult.stale;
        _lastSyncedAt = syncTimes.isEmpty ? null : syncTimes.reduce((a, b) => a.isBefore(b) ? a : b);
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your lease details — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reviewAndSign() async {
    final agreement = _rental?.agreement;
    if (agreement == null) return;
    final signed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AgreementSignScreen(agreement: agreement, authRepository: _auth, rentalRepository: _rentals)),
    );
    if (signed == true) await _load();
  }

  Future<void> _pickPreferredDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _preferredEndDate ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _preferredEndDate = picked);
  }

  Future<void> _requestRenewal() async {
    if (_token == null) return;
    setState(() {
      _requesting = true;
      _error = null;
    });
    try {
      final requestedEndDate = _preferredEndDate == null
          ? null
          : '${_preferredEndDate!.year.toString().padLeft(4, '0')}-${_preferredEndDate!.month.toString().padLeft(2, '0')}-${_preferredEndDate!.day.toString().padLeft(2, '0')}';
      await _renewals.request(_token!, requestedEndDate: requestedEndDate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Renewal requested — your property manager has been notified')));
      await _load();
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A renewal request is already pending')));
        await _load();
      } else {
        setState(() => _error = e.message);
      }
    } catch (_) {
      setState(() => _error = 'Could not send the request — try again');
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lease')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rental == null
            ? _ErrorState(message: _error ?? 'Could not load your lease details', onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(NivasaSpacing.s24),
                  children: [
                    if (_stale) ...[
                      NivasaStaleBanner(lastSyncedAt: _lastSyncedAt),
                      const SizedBox(height: NivasaSpacing.s16),
                    ],
                    _SectionCard(
                      title: 'Room & bed',
                      sub: _rental!.allocation != null ? 'Checked in ${_rental!.allocation!.checkInDate}' : null,
                      child: _rental!.bed != null
                          ? Text('${_rental!.bed!.roomName} · Bed ${_rental!.bed!.label}', style: NivasaText.h3)
                          : Text('Not assigned to a bed yet', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
                    ),
                    const SizedBox(height: NivasaSpacing.s16),
                    _SectionCard(
                      title: 'Rent',
                      child: _rental!.billingProfile != null
                          ? Text(
                              '${_formatInr(_rental!.billingProfile!.amount)}${_cycleLabels[_rental!.billingProfile!.cycleType] ?? ''}',
                              style: NivasaText.h3,
                            )
                          : Text('No billing set up yet', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
                    ),
                    const SizedBox(height: NivasaSpacing.s16),
                    _SectionCard(
                      title: 'Agreement',
                      child: _rental!.agreement != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _StatusPill(status: _rental!.agreement!.status),
                                const SizedBox(height: NivasaSpacing.s8),
                                Text(
                                  'Monthly rent ${_formatInr(_rental!.agreement!.monthlyRent)} · Deposit ${_formatInr(_rental!.agreement!.securityDeposit)}',
                                  style: NivasaText.body,
                                ),
                                const SizedBox(height: NivasaSpacing.s4),
                                Text(
                                  _rental!.agreement!.endDate != null
                                      ? '${_rental!.agreement!.startDate} to ${_rental!.agreement!.endDate}'
                                      : 'Since ${_rental!.agreement!.startDate}',
                                  style: NivasaText.body.copyWith(color: NivasaColors.ink500, fontSize: 13),
                                ),
                                if (_rental!.agreement!.status == 'draft') ...[
                                  const SizedBox(height: NivasaSpacing.s12),
                                  NivasaPrimaryButton(label: 'Review & sign', onPressed: _reviewAndSign),
                                ],
                              ],
                            )
                          : Text('No agreement on file yet', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
                    ),
                    const SizedBox(height: NivasaSpacing.s16),
                    _SectionCard(
                      title: 'Rental offers',
                      child: Text('Coming soon', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
                    ),
                    const SizedBox(height: NivasaSpacing.s32),
                    Text('Renewal', style: NivasaText.label.copyWith(color: NivasaColors.ink500)),
                    const SizedBox(height: NivasaSpacing.s12),
                    if (_hasPending)
                      Container(
                        padding: const EdgeInsets.all(NivasaSpacing.s16),
                        decoration: BoxDecoration(
                          color: NivasaColors.warningTint,
                          border: Border.all(color: NivasaColors.warningTintBorder),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'A renewal request is pending — your property manager has been notified.',
                          style: NivasaText.body.copyWith(color: NivasaColors.warningTextOnTint),
                        ),
                      )
                    else ...[
                      TextButton(
                        onPressed: _requesting ? null : _pickPreferredDate,
                        child: Text(
                          _preferredEndDate == null
                              ? 'Set a preferred end date (optional)'
                              : 'Preferred end date: ${_preferredEndDate!.year}-${_preferredEndDate!.month.toString().padLeft(2, '0')}-${_preferredEndDate!.day.toString().padLeft(2, '0')}',
                        ),
                      ),
                      const SizedBox(height: NivasaSpacing.s8),
                      NivasaPrimaryButton(
                        label: _stale ? 'Reconnect to request a renewal' : 'Request renewal',
                        loading: _requesting,
                        loadingLabel: 'Sending…',
                        // "Reconnect" actually retries the fetch, rather than being a
                        // disabled label promising an action it can't perform — was
                        // previously onPressed: null when stale.
                        onPressed: _stale ? _load : _requestRenewal,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: NivasaSpacing.s16),
                      Text(_error!, style: NivasaText.body.copyWith(color: NivasaColors.negativeFg)),
                    ],
                    const SizedBox(height: NivasaSpacing.s32),
                    Text('Request history', style: NivasaText.label.copyWith(color: NivasaColors.ink500)),
                    const SizedBox(height: NivasaSpacing.s8),
                    if (_requests.isEmpty)
                      Text('No renewal requests yet', style: NivasaText.body.copyWith(color: NivasaColors.ink500))
                    else
                      ..._requests.map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: NivasaSpacing.s8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r.requestedEndDate != null ? 'Requested end date: ${r.requestedEndDate}' : 'Requested ${r.createdAt}',
                                  style: NivasaText.body,
                                ),
                              ),
                              Text(
                                r.status == 'pending' ? 'Pending' : 'Acknowledged',
                                style: NivasaText.body.copyWith(
                                  color: r.status == 'pending' ? NivasaColors.warningTextOnTint : NivasaColors.positiveTextOnTint,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.sub});

  final String title;
  final Widget child;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NivasaSpacing.s16),
      decoration: BoxDecoration(color: NivasaColors.white, border: Border.all(color: NivasaColors.line), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: NivasaText.label.copyWith(color: NivasaColors.ink500)),
          const SizedBox(height: NivasaSpacing.s8),
          child,
          if (sub != null) ...[
            const SizedBox(height: NivasaSpacing.s4),
            Text(sub!, style: NivasaText.body.copyWith(color: NivasaColors.ink500, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, border, text) = switch (status) {
      'signed' => (NivasaColors.positiveTint, NivasaColors.positiveTintBorder, NivasaColors.positiveTextOnTint),
      'terminated' => (NivasaColors.negativeTint, NivasaColors.negativeTintBorder, NivasaColors.negativeTextOnTint),
      _ => (NivasaColors.warningTint, NivasaColors.warningTintBorder, NivasaColors.warningTextOnTint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(999)),
      child: Text(status[0].toUpperCase() + status.substring(1), style: NivasaText.body.copyWith(color: text, fontSize: 12, fontWeight: FontWeight.w600)),
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
