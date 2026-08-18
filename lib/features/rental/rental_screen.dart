import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import 'rental_repository.dart';

const _cycleLabels = {'monthly': '/month', 'weekly': '/week', 'daily': '/day'};

String _formatInr(int amountMinor) => '₹${(amountMinor / 100).toStringAsFixed(0)}';

class RentalScreen extends StatefulWidget {
  const RentalScreen({super.key, this.authRepository, this.rentalRepository, this.cacheStore});

  final AuthRepository? authRepository;
  final RentalRepository? rentalRepository;
  final CacheStore? cacheStore;

  @override
  State<RentalScreen> createState() => _RentalScreenState();
}

class _RentalScreenState extends State<RentalScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final RentalRepository _rentals = widget.rentalRepository ?? RentalRepository();
  late final CacheStore _cache = widget.cacheStore ?? const SharedPreferencesCacheStore();

  RentalInfo? _rental;
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
      final result = await fetchWithCache<RentalInfo>(
        cache: _cache,
        cacheKey: 'rental_info',
        fetchNetwork: () => _rentals.fetch(session.accessToken),
        toJson: (r) => r.toJson(),
        fromJson: (json) => RentalInfo.fromJson(json as Map<String, dynamic>),
      );
      if (!mounted) return;
      setState(() {
        _rental = result.data;
        _stale = result.stale;
        _lastSyncedAt = result.lastSyncedAt;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your rental details — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My rental')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rental == null
            ? _ErrorState(message: _error ?? 'Could not load your rental details', onRetry: _load)
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
                              ],
                            )
                          : Text('No agreement on file yet', style: NivasaText.body.copyWith(color: NivasaColors.ink500)),
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
