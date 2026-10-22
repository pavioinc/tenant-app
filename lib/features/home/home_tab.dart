import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../core/date_utils.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_elevation.dart';
import '../../theme/pavio_spacing.dart';
import '../../theme/pavio_text_styles.dart';
import '../../widgets/pavio_logo.dart';
import '../../widgets/pavio_section_label.dart';
import '../../widgets/pavio_skeleton.dart';
import '../../widgets/pavio_stale_banner.dart';
import '../auth/auth_repository.dart';
import '../payments/payments_repository.dart';

/// Indian digit grouping, same rule as Payments' own `_formatInr` — kept as a private
/// copy rather than exported from payments_screen.dart, which otherwise has no public
/// surface for other features to reach into.
String _formatInr(int amountMinor) {
  final rupees = (amountMinor / 100).round();
  final digits = rupees.toString();
  if (digits.length <= 3) return '₹$digits';
  final lastThree = digits.substring(digits.length - 3);
  final rest = digits.substring(0, digits.length - 3);
  final grouped = StringBuffer();
  for (var i = 0; i < rest.length; i++) {
    final positionFromEnd = rest.length - i;
    grouped.write(rest[i]);
    if (positionFromEnd > 1 && positionFromEnd.isOdd) grouped.write(',');
  }
  return '₹$grouped,$lastThree';
}

/// Home tab of the bottom-tab shell (`Pavio Mobile Wireframes` doc, sample screen 2):
/// greeting, a rent-due hero the renter can act on without leaving Home, and a short
/// "Recent payments" preview. The full invoice list, payment methods and Pay action live
/// on the Pay tab — [onGoToPay] switches there rather than duplicating that flow here.
/// Shares its cache keys with PaymentsScreen ('payments_invoices' /
/// 'payments_transactions'): same server resource, so whichever screen fetched most
/// recently is what the other shows from cache too.
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.onGoToPay,
    this.authRepository,
    this.paymentsRepository,
    this.cacheStore,
  });

  final VoidCallback onGoToPay;
  final AuthRepository? authRepository;
  final PaymentsRepository? paymentsRepository;
  final CacheStore? cacheStore;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final PaymentsRepository _payments =
      widget.paymentsRepository ?? PaymentsRepository();
  late final CacheStore _cache =
      widget.cacheStore ?? const SharedPreferencesCacheStore();

  String? _name;
  List<PendingInvoice> _invoices = [];
  int _totalDue = 0;
  List<TenantTransaction> _recentPayments = [];
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
      final token = session.accessToken;
      final results = await Future.wait([
        fetchWithCache<PendingInvoices>(
          cache: _cache,
          cacheKey: 'payments_invoices',
          fetchNetwork: () => _payments.pendingInvoices(token),
          toJson: (p) => p.toJson(),
          fromJson: (json) =>
              PendingInvoices.fromJson(json as Map<String, dynamic>),
        ),
        fetchWithCache<TenantTransactions>(
          cache: _cache,
          cacheKey: 'payments_transactions',
          fetchNetwork: () => _payments.recentTransactions(token),
          toJson: (t) => t.toJson(),
          fromJson: (json) =>
              TenantTransactions.fromJson(json as Map<String, dynamic>),
        ),
      ]);
      if (!mounted) return;
      final invoicesResult = results[0] as CachedFetch<PendingInvoices>;
      final transactionsResult =
          results[1] as CachedFetch<TenantTransactions>;
      final syncTimes = [
        invoicesResult.lastSyncedAt,
        transactionsResult.lastSyncedAt,
      ].whereType<DateTime>();
      setState(() {
        _name = session.user.name;
        _invoices = invoicesResult.data.invoices;
        _totalDue = invoicesResult.data.totalDue;
        _recentPayments = transactionsResult.data.transactions
            .where((t) => t.type == 'payment')
            .take(3)
            .toList();
        _stale = invoicesResult.stale || transactionsResult.stale;
        _lastSyncedAt = syncTimes.isEmpty
            ? null
            : syncTimes.reduce((a, b) => a.isBefore(b) ? a : b);
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your home screen — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PavioSpacing.s24,
                PavioSpacing.s24,
                PavioSpacing.s24,
                0,
              ),
              child: Row(
                children: [
                  const PavioLogoMark(size: 36),
                  const SizedBox(width: PavioSpacing.s12),
                  Text(
                    'Pavio',
                    style: PavioText.h3.copyWith(color: PavioColors.primary800),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const _HomeTabLoadingSkeleton()
                  : _error != null
                  ? _HomeTabErrorState(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(PavioSpacing.s24),
                        children: [
                          Text(
                            'Namaskaram 🙏',
                            style: PavioText.body.copyWith(
                              color: PavioColors.ink500,
                            ),
                          ),
                          const SizedBox(height: PavioSpacing.s4),
                          Text(_name ?? '…', style: PavioText.h1),
                          const SizedBox(height: PavioSpacing.s24),
                          if (_stale) ...[
                            PavioStaleBanner(
                              lastSyncedAt: _lastSyncedAt,
                              onRetry: _load,
                            ),
                            const SizedBox(height: PavioSpacing.s16),
                          ],
                          _RentDueHeroCard(
                            totalDue: _totalDue,
                            invoices: _invoices,
                            onTap: widget.onGoToPay,
                          ),
                          const SizedBox(height: PavioSpacing.s24),
                          const PavioSectionLabel('Recent payments'),
                          const SizedBox(height: PavioSpacing.s12),
                          if (_recentPayments.isEmpty)
                            Text(
                              'No payments yet',
                              style: PavioText.body.copyWith(
                                color: PavioColors.ink500,
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: PavioColors.white,
                                border: Border.all(color: PavioColors.line),
                                borderRadius: BorderRadius.circular(
                                  PavioRadius.card,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (
                                    var i = 0;
                                    i < _recentPayments.length;
                                    i++
                                  ) ...[
                                    _RecentPaymentRow(
                                      transaction: _recentPayments[i],
                                    ),
                                    if (i != _recentPayments.length - 1)
                                      const Divider(
                                        height: 1,
                                        indent: 36,
                                        color: PavioColors.line,
                                      ),
                                  ],
                                ],
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

/// The hero rent-due card from the design doc's Home sample screen — a lighter, tap-
/// through version of Payments' own `_RentDueHero`: same gold-tint presentation, no
/// method-select or Pay action inline, since tapping it (or "Nothing to pay") just moves
/// to the Pay tab where that flow already lives.
class _RentDueHeroCard extends StatelessWidget {
  const _RentDueHeroCard({
    required this.totalDue,
    required this.invoices,
    required this.onTap,
  });

  final int totalDue;
  final List<PendingInvoice> invoices;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final earliestDue = invoices.isEmpty ? null : invoices.first.dueDate;
    final nothingDue = totalDue == 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PavioRadius.card),
      child: Container(
        padding: const EdgeInsets.all(PavioSpacing.s20),
        decoration: BoxDecoration(
          color: nothingDue ? PavioColors.white : PavioColors.gold100,
          border: Border.all(
            color: nothingDue ? PavioColors.line : PavioColors.gold200,
          ),
          borderRadius: BorderRadius.circular(PavioRadius.card),
          boxShadow: nothingDue ? PavioElevation.e1 : PavioElevation.e0,
        ),
        child: nothingDue
            ? Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: PavioColors.positiveFg,
                    size: 28,
                  ),
                  const SizedBox(width: PavioSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nothing to pay', style: PavioText.h3),
                        const SizedBox(height: PavioSpacing.s4),
                        Text(
                          "You're all caught up on rent.",
                          style: PavioText.body.copyWith(
                            color: PavioColors.ink500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rent due',
                    style: PavioText.label.copyWith(
                      color: PavioColors.gold800,
                    ),
                  ),
                  const SizedBox(height: PavioSpacing.s8),
                  Text(
                    _formatInr(totalDue),
                    style: PavioText.display.copyWith(
                      fontFamily: 'Noto Sans Mono',
                      color: PavioColors.goldTextOn,
                    ),
                  ),
                  const SizedBox(height: PavioSpacing.s8),
                  if (earliestDue != null)
                    Text(
                      formatDueDate(earliestDue),
                      style: PavioText.bodySmall.copyWith(
                        color: PavioColors.gold800,
                      ),
                    ),
                  const SizedBox(height: PavioSpacing.s16),
                  Row(
                    children: [
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(
                          horizontal: PavioSpacing.s16,
                        ),
                        decoration: BoxDecoration(
                          color: PavioColors.gold500,
                          borderRadius: BorderRadius.circular(
                            PavioRadius.button,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Pay ${_formatInr(totalDue)} now',
                              style: PavioText.body.copyWith(
                                color: PavioColors.goldTextOn,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

/// Mirrors Payments' own `_PaymentRow` — a smaller, read-only preview (no amount-row
/// divider changes, same green-dot/title/subtitle/mono-amount shape) since Home only ever
/// shows the top few before handing off to the Pay tab for the full list.
class _RecentPaymentRow extends StatelessWidget {
  const _RecentPaymentRow({required this.transaction});

  final TenantTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final subtitle = transaction.subtitle != null
        ? 'Paid ${formatDisplayDate(transaction.date)} · ${transaction.subtitle}'
        : 'Paid ${formatDisplayDate(transaction.date)}';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PavioSpacing.s16,
        vertical: 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: PavioColors.positiveFg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: PavioSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title,
                  style: PavioText.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: PavioText.caption),
              ],
            ),
          ),
          Text(
            _formatInr(transaction.amount),
            style: PavioText.mono.copyWith(
              color: PavioColors.ink900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mirrors the loaded body's shape — header, hero card, three list rows — per the design
/// doc's Loading section ("never a blank rectangle").
class _HomeTabLoadingSkeleton extends StatelessWidget {
  const _HomeTabLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(PavioSpacing.s24),
      children: [
        const PavioSkeleton(width: 140, height: 15),
        const SizedBox(height: PavioSpacing.s8),
        const PavioSkeleton(width: 180, height: 26),
        const SizedBox(height: PavioSpacing.s24),
        PavioSkeleton(height: 150, borderRadius: PavioRadius.card),
        const SizedBox(height: PavioSpacing.s24),
        const PavioSkeleton(width: 140, height: 15),
        const SizedBox(height: PavioSpacing.s12),
        const PavioSkeletonListTile(),
        const SizedBox(height: PavioSpacing.s12),
        const PavioSkeletonListTile(),
      ],
    );
  }
}

class _HomeTabErrorState extends StatelessWidget {
  const _HomeTabErrorState({required this.message, required this.onRetry});

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
            const Icon(
              Icons.error_outline,
              color: PavioColors.negativeFg,
              size: 32,
            ),
            const SizedBox(height: PavioSpacing.s12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: PavioText.body.copyWith(color: PavioColors.ink500),
            ),
            const SizedBox(height: PavioSpacing.s16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
