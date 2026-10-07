import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../core/date_utils.dart';
import '../../core/url_opener.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_elevation.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_button.dart';
import '../../widgets/pavio_section_label.dart';
import '../../widgets/pavio_skeleton.dart';
import '../../widgets/pavio_stale_banner.dart';
import '../auth/auth_repository.dart';
import '../rental/agreement_sign_screen.dart';
import '../rental/rental_repository.dart';
import '../renewal/renewal_repository.dart';

const _cycleLabels = {
  'monthly': '/ month',
  'weekly': '/ week',
  'daily': '/ day',
};

String _formatInr(int amountMinor) =>
    '₹${(amountMinor / 100).toStringAsFixed(0)}';

const _factLabelStyle = TextStyle(
  fontFamily: 'Noto Sans',
  fontSize: 14,
  fontWeight: FontWeight.w500,
  color: PavioColors.ink500,
);

/// "$days left" for the hero's term countdown — under 45 days reads better as days than
/// a rounded "1 month left" (which would round the same as an actual 45-day span).
String _remainingLabel(int days) {
  if (days <= 0) return 'Lease ended';
  if (days < 45) return '$days day${days == 1 ? '' : 's'} left';
  final months = (days / 30).round();
  return '$months month${months == 1 ? '' : 's'} left';
}

({double progress, String remainingLabel})? _leaseTerm(Agreement agreement) {
  final endDateRaw = agreement.endDate;
  if (endDateRaw == null) return null;
  final start = DateTime.tryParse(agreement.startDate);
  final end = DateTime.tryParse(endDateRaw);
  if (start == null || end == null) return null;
  final totalDays = end.difference(start).inDays;
  if (totalDays <= 0) return null;
  final now = DateTime.now();
  final elapsedDays = now.difference(start).inDays.clamp(0, totalDays);
  return (
    progress: elapsedDays / totalDays,
    remainingLabel: _remainingLabel(end.difference(now).inDays),
  );
}

/// "Your stay ends in February. …" — the mock's own copy names the month the agreement
/// actually ends in, not a placeholder; month-to-month agreements (no end date) drop that
/// clause rather than naming a month that doesn't exist.
String _renewalIntro(Agreement? agreement) {
  const tail = "Ask your manager to renew and they'll draw up a new agreement.";
  final endDateRaw = agreement?.endDate;
  if (endDateRaw == null) return tail;
  final end = DateTime.tryParse(endDateRaw);
  if (end == null) return tail;
  return 'Your stay ends in ${fullMonthName(end.month)}. $tail';
}

/// Combines the former My rental + Renewal screens into one "Lease" tile (2026-08-18
/// Resident Hub redesign) — same two repositories, unchanged, just one screen instead of
/// two. Redesigned again (2026-09, doc option "1d") into a status hero with the tenancy
/// drawn as a term, one definition list for the facts, one renewal card — replacing four
/// bordered one-fact cards and a dead "Rental offers" section that never had a backing
/// feature.
class LeaseScreen extends StatefulWidget {
  const LeaseScreen({
    super.key,
    this.authRepository,
    this.rentalRepository,
    this.renewalRepository,
    this.cacheStore,
    this.urlOpener,
  });

  final AuthRepository? authRepository;
  final RentalRepository? rentalRepository;
  final RenewalRepository? renewalRepository;
  final CacheStore? cacheStore;
  final UrlOpener? urlOpener;

  @override
  State<LeaseScreen> createState() => _LeaseScreenState();
}

class _LeaseScreenState extends State<LeaseScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final RentalRepository _rentals =
      widget.rentalRepository ?? RentalRepository();
  late final RenewalRepository _renewals =
      widget.renewalRepository ?? RenewalRepository();
  late final CacheStore _cache =
      widget.cacheStore ?? const SharedPreferencesCacheStore();
  late final UrlOpener _urlOpener = widget.urlOpener ?? const RealUrlOpener();

  String? _token;
  RentalInfo? _rental;
  List<RenewalRequest> _requests = [];
  DateTime? _preferredEndDate;
  bool _loading = true;
  bool _requesting = false;
  bool _openingAgreement = false;
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
          fromJson: (json) => (json as List)
              .map((r) => RenewalRequest.fromJson(r as Map<String, dynamic>))
              .toList(),
        ),
      ]);
      if (!mounted) return;
      final rentalResult = results[0] as CachedFetch<RentalInfo>;
      final renewalResult = results[1] as CachedFetch<List<RenewalRequest>>;
      final syncTimes = [
        rentalResult.lastSyncedAt,
        renewalResult.lastSyncedAt,
      ].whereType<DateTime>();
      setState(() {
        _rental = rentalResult.data;
        _requests = renewalResult.data;
        _stale = rentalResult.stale || renewalResult.stale;
        _lastSyncedAt = syncTimes.isEmpty
            ? null
            : syncTimes.reduce((a, b) => a.isBefore(b) ? a : b);
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
      MaterialPageRoute(
        builder: (_) => AgreementSignScreen(
          agreement: agreement,
          authRepository: _auth,
          rentalRepository: _rentals,
        ),
      ),
    );
    if (signed == true) await _load();
  }

  Future<void> _openAgreement() async {
    final agreement = _rental?.agreement;
    if (agreement == null || _token == null || _openingAgreement) return;
    setState(() => _openingAgreement = true);
    try {
      final url = await _rentals.agreementDocumentUrl(
        _token!,
        agreement.agreementId,
      );
      await _urlOpener.open(url);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the agreement — try again'),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingAgreement = false);
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Renewal requested — your property manager has been notified',
          ),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A renewal request is already pending')),
        );
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
    final rental = _rental;
    return Scaffold(
      appBar: AppBar(title: const Text('Lease')),
      body: SafeArea(
        child: _loading
            ? const _LeaseLoadingSkeleton()
            : rental == null
            ? _ErrorState(
                message: _error ?? 'Could not load your lease details',
                onRetry: _load,
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
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(PavioSpacing.s24),
                        children: [
                          _LeaseHero(
                            agreement: rental.agreement,
                            onReviewAndSign: _reviewAndSign,
                          ),
                          const SizedBox(height: PavioSpacing.s24),
                          const PavioSectionLabel('Your rental'),
                          const SizedBox(height: PavioSpacing.s12),
                          _RentalFactsCard(
                            rental: rental,
                            openingAgreement: _openingAgreement,
                            onReadAgreement: _openAgreement,
                          ),
                          const SizedBox(height: PavioSpacing.s24),
                          const PavioSectionLabel('Renewal'),
                          const SizedBox(height: PavioSpacing.s12),
                          if (_hasPending)
                            Container(
                              padding: const EdgeInsets.all(PavioSpacing.s16),
                              decoration: BoxDecoration(
                                color: PavioColors.warningTint,
                                border: Border.all(
                                  color: PavioColors.warningTintBorder,
                                ),
                                borderRadius: BorderRadius.circular(
                                  PavioRadius.card,
                                ),
                              ),
                              child: Text(
                                'A renewal request is pending — your property manager has been notified.',
                                style: PavioText.body.copyWith(
                                  color: PavioColors.warningTextOnTint,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(PavioSpacing.s16),
                              decoration: BoxDecoration(
                                color: PavioColors.white,
                                border: Border.all(color: PavioColors.line),
                                borderRadius: BorderRadius.circular(
                                  PavioRadius.card,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _renewalIntro(rental.agreement),
                                    style: PavioText.body.copyWith(
                                      color: PavioColors.ink700,
                                    ),
                                  ),
                                  const SizedBox(height: PavioSpacing.s16),
                                  _PreferredDateField(
                                    value: _preferredEndDate,
                                    onTap: _requesting
                                        ? null
                                        : _pickPreferredDate,
                                  ),
                                  const SizedBox(height: PavioSpacing.s12),
                                  PavioPrimaryButton(
                                    label: _stale
                                        ? 'Reconnect to request a renewal'
                                        : 'Request renewal',
                                    loading: _requesting,
                                    loadingLabel: 'Sending…',
                                    // "Reconnect" actually retries the fetch, rather than being a
                                    // disabled label promising an action it can't perform — was
                                    // previously onPressed: null when stale.
                                    onPressed: _stale ? _load : _requestRenewal,
                                  ),
                                ],
                              ),
                            ),
                          if (_error != null) ...[
                            const SizedBox(height: PavioSpacing.s16),
                            Text(
                              _error!,
                              style: PavioText.body.copyWith(
                                color: PavioColors.negativeFg,
                              ),
                            ),
                          ],
                          const SizedBox(height: PavioSpacing.s32),
                          Text(
                            'Request history',
                            style: PavioText.label.copyWith(
                              color: PavioColors.ink500,
                            ),
                          ),
                          const SizedBox(height: PavioSpacing.s8),
                          if (_requests.isEmpty)
                            Text(
                              'No renewal requests yet',
                              style: PavioText.body.copyWith(
                                color: PavioColors.ink500,
                              ),
                            )
                          else
                            ..._requests.map(
                              (r) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: PavioSpacing.s8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.requestedEndDate != null
                                            ? 'Requested end date: ${formatDisplayDate(r.requestedEndDate!)}'
                                            : 'Requested ${formatDisplayDate(r.createdAt)}',
                                        style: PavioText.body,
                                      ),
                                    ),
                                    Text(
                                      r.status == 'pending'
                                          ? 'Pending'
                                          : 'Acknowledged',
                                      style: PavioText.bodySmall.copyWith(
                                        color: r.status == 'pending'
                                            ? PavioColors.warningTextOnTint
                                            : PavioColors.positiveTextOnTint,
                                        fontWeight: FontWeight.w600,
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
                ],
              ),
      ),
    );
  }
}

/// Mirrors the loaded body's real shape (doc option "1l") — hero card, facts card, and
/// renewal card, in the same three-section layout the real content renders once the
/// fetch resolves, replacing the old `Center(child: CircularProgressIndicator())`.
class _LeaseLoadingSkeleton extends StatelessWidget {
  const _LeaseLoadingSkeleton();

  static Widget _card({required List<Widget> children}) => Container(
    padding: const EdgeInsets.all(PavioSpacing.s20),
    decoration: BoxDecoration(
      color: PavioColors.white,
      border: Border.all(color: PavioColors.line),
      borderRadius: BorderRadius.circular(PavioRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(PavioSpacing.s24),
      children: [
        _card(
          children: const [
            Row(
              children: [
                PavioSkeleton(
                  width: 70,
                  height: 24,
                  borderRadius: PavioRadius.pill,
                ),
                Spacer(),
                PavioSkeleton(width: 90, height: 13),
              ],
            ),
            SizedBox(height: PavioSpacing.s16),
            PavioSkeleton(height: 6, borderRadius: PavioRadius.pill),
            SizedBox(height: PavioSpacing.s8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                PavioSkeleton(width: 70, height: 12),
                PavioSkeleton(width: 70, height: 12),
              ],
            ),
          ],
        ),
        const SizedBox(height: PavioSpacing.s24),
        const PavioSkeleton(width: 90, height: 11),
        const SizedBox(height: PavioSpacing.s12),
        _card(
          children: const [
            PavioSkeleton(width: 200, height: 15),
            SizedBox(height: PavioSpacing.s16),
            PavioSkeleton(width: 140, height: 15),
            SizedBox(height: PavioSpacing.s16),
            PavioSkeleton(width: 100, height: 15),
            SizedBox(height: PavioSpacing.s16),
            PavioSkeleton(width: 160, height: 15),
          ],
        ),
        const SizedBox(height: PavioSpacing.s24),
        const PavioSkeleton(width: 70, height: 11),
        const SizedBox(height: PavioSpacing.s12),
        _card(
          children: const [
            PavioSkeleton(height: 13),
            SizedBox(height: PavioSpacing.s8),
            PavioSkeleton(width: 220, height: 13),
            SizedBox(height: PavioSpacing.s16),
            PavioSkeleton(height: 52, borderRadius: PavioRadius.button),
          ],
        ),
      ],
    );
  }
}

class _LeaseHero extends StatelessWidget {
  const _LeaseHero({required this.agreement, required this.onReviewAndSign});

  final Agreement? agreement;
  final VoidCallback onReviewAndSign;

  @override
  Widget build(BuildContext context) {
    final agreement = this.agreement;
    if (agreement == null) {
      return Container(
        padding: const EdgeInsets.all(PavioSpacing.s20),
        decoration: BoxDecoration(
          color: PavioColors.white,
          border: Border.all(color: PavioColors.line),
          borderRadius: BorderRadius.circular(PavioRadius.card),
        ),
        child: Text(
          'No agreement on file yet',
          style: PavioText.body.copyWith(color: PavioColors.ink500),
        ),
      );
    }
    final term = agreement.status == 'signed' ? _leaseTerm(agreement) : null;
    return Container(
      padding: const EdgeInsets.all(PavioSpacing.s20),
      decoration: BoxDecoration(
        color: PavioColors.white,
        border: Border.all(color: PavioColors.line),
        borderRadius: BorderRadius.circular(PavioRadius.card),
        boxShadow: PavioElevation.e1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusPill(status: agreement.status),
              const Spacer(),
              if (term != null)
                Text(
                  term.remainingLabel,
                  style: PavioText.bodySmall.copyWith(
                    color: PavioColors.ink500,
                  ),
                )
              else if (agreement.status == 'signed')
                Text(
                  'Since ${formatDisplayDate(agreement.startDate)}',
                  style: PavioText.bodySmall.copyWith(
                    color: PavioColors.ink500,
                  ),
                ),
            ],
          ),
          if (term != null) ...[
            const SizedBox(height: PavioSpacing.s16),
            ClipRRect(
              borderRadius: BorderRadius.circular(PavioRadius.pill),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: term.progress,
                  backgroundColor: PavioColors.canvas,
                  valueColor: const AlwaysStoppedAnimation(
                    PavioColors.primary700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: PavioSpacing.s8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatDisplayDate(agreement.startDate),
                  style: PavioText.caption,
                ),
                Text(
                  formatDisplayDate(agreement.endDate!),
                  style: PavioText.caption,
                ),
              ],
            ),
          ],
          if (agreement.status == 'draft') ...[
            const SizedBox(height: PavioSpacing.s16),
            PavioPrimaryButton(
              label: 'Review & sign',
              onPressed: onReviewAndSign,
            ),
          ],
        ],
      ),
    );
  }
}

class _RentalFactsCard extends StatelessWidget {
  const _RentalFactsCard({
    required this.rental,
    required this.openingAgreement,
    required this.onReadAgreement,
  });

  final RentalInfo rental;
  final bool openingAgreement;
  final VoidCallback onReadAgreement;

  @override
  Widget build(BuildContext context) {
    final bed = rental.bed;
    final billingProfile = rental.billingProfile;
    final agreement = rental.agreement;
    final allocation = rental.allocation;
    final showReadAgreement = agreement?.status == 'signed';

    return Container(
      decoration: BoxDecoration(
        color: PavioColors.white,
        border: Border.all(color: PavioColors.line),
        borderRadius: BorderRadius.circular(PavioRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _FactRow(
            label: 'Room & bed',
            value: bed != null
                ? Text(
                    'Room ${bed.roomName} · Bed ${bed.label}',
                    style: PavioText.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Text(
                    'Not assigned to a bed yet',
                    style: PavioText.body.copyWith(color: PavioColors.ink500),
                  ),
          ),
          const Divider(
            height: 1,
            indent: PavioSpacing.s16,
            color: PavioColors.line,
          ),
          _FactRow(
            label: 'Rent',
            // A Row of two Text widgets here overflowed by a fraction of a pixel
            // (Flutter sums each child's own rounded intrinsic width, which doesn't
            // always match the merged run one RichText/Text.rich lays out as a whole).
            value: billingProfile != null
                ? Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _formatInr(billingProfile.amount),
                          style: PavioText.mono.copyWith(fontSize: 15),
                        ),
                        TextSpan(
                          text:
                              ' ${_cycleLabels[billingProfile.cycleType] ?? ''}',
                          style: _factLabelStyle,
                        ),
                      ],
                    ),
                  )
                : Text(
                    'No billing set up yet',
                    style: PavioText.body.copyWith(color: PavioColors.ink500),
                  ),
          ),
          const Divider(
            height: 1,
            indent: PavioSpacing.s16,
            color: PavioColors.line,
          ),
          _FactRow(
            label: 'Deposit',
            // The hero above already says "No agreement on file yet" when there's no
            // agreement — repeating that full sentence a second time here just to fill
            // this row would be noise, not information.
            value: agreement != null
                ? Text(
                    _formatInr(agreement.securityDeposit),
                    style: PavioText.mono.copyWith(fontSize: 15),
                  )
                : Text(
                    '—',
                    style: PavioText.body.copyWith(color: PavioColors.ink500),
                  ),
          ),
          const Divider(
            height: 1,
            indent: PavioSpacing.s16,
            color: PavioColors.line,
          ),
          _FactRow(
            label: 'Moved in',
            value: allocation != null
                ? Text(
                    formatDisplayDate(allocation.checkInDate),
                    style: PavioText.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Text(
                    'Not checked in yet',
                    style: PavioText.body.copyWith(color: PavioColors.ink500),
                  ),
          ),
          if (showReadAgreement) ...[
            const Divider(
              height: 1,
              indent: PavioSpacing.s16,
              color: PavioColors.line,
            ),
            InkWell(
              onTap: openingAgreement ? null : onReadAgreement,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PavioSpacing.s16,
                ),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 20,
                        color: PavioColors.primary700,
                      ),
                      const SizedBox(width: PavioSpacing.s12),
                      Expanded(
                        child: Text(
                          openingAgreement ? 'Opening…' : 'Read the agreement',
                          style: PavioText.body.copyWith(
                            color: PavioColors.primary700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (openingAgreement)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: PavioColors.ink400,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PavioSpacing.s16,
        vertical: 14,
      ),
      child: Row(
        children: [
          SizedBox(width: 118, child: Text(label, style: _factLabelStyle)),
          Expanded(child: value),
        ],
      ),
    );
  }
}

class _PreferredDateField extends StatelessWidget {
  const _PreferredDateField({required this.value, required this.onTap});

  final DateTime? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final label = value == null
        ? 'Preferred end date'
        : formatDisplayDate(
            '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
          );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PavioRadius.button),
      child: Container(
        height: PavioSpacing.buttonHeightMobile,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: PavioColors.line, width: 1.5),
          borderRadius: BorderRadius.circular(PavioRadius.button),
        ),
        child: Row(
          children: [
            Icon(Icons.event_outlined, size: 19, color: PavioColors.ink500),
            const SizedBox(width: PavioSpacing.s12),
            Expanded(
              child: Text(
                label,
                style: PavioText.body.copyWith(
                  color: value == null
                      ? PavioColors.ink500
                      : PavioColors.ink900,
                ),
              ),
            ),
            Text(
              value == null ? 'Optional' : 'Change',
              style: _factLabelStyle.copyWith(color: PavioColors.primary700),
            ),
          ],
        ),
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
      'signed' => (
        PavioColors.positiveTint,
        PavioColors.positiveTintBorder,
        PavioColors.positiveTextOnTint,
      ),
      'terminated' => (
        PavioColors.negativeTint,
        PavioColors.negativeTintBorder,
        PavioColors.negativeTextOnTint,
      ),
      _ => (
        PavioColors.warningTint,
        PavioColors.warningTintBorder,
        PavioColors.warningTextOnTint,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(PavioRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'signed') ...[
            Icon(Icons.check_circle, size: 14, color: text),
            const SizedBox(width: 5),
          ],
          Text(
            status[0].toUpperCase() + status.substring(1),
            style: PavioText.badge.copyWith(color: text),
          ),
        ],
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
