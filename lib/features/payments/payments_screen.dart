import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../core/date_utils.dart';
import '../../core/razorpay_checkout.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_section_label.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import 'payments_repository.dart';

/// Indian digit grouping (last 3 digits, then pairs: ₹1,03,000) — the mock's own "₹3,300"
/// needs it and no screen in this app has ever grouped digits at all (every other
/// `_formatInr` prints "₹3300"). No `intl` dependency added for it: this is one small,
/// pure function, not a locale system.
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

String _invoiceCountLabel(int count) =>
    '$count invoice${count == 1 ? '' : 's'}';

/// "Paid 5 Aug 2026 · UPI" — the mock's own copy drops the year ("Paid 5 Aug"), but
/// formatDisplayDate's with-year shape is what every other screen in the app already
/// shows a renter, and forking a year-less date formatter for one subtitle would cost
/// more in app-wide consistency than it'd gain in mock fidelity.
String _paymentSubtitle(TenantTransaction transaction) {
  final paidOn = 'Paid ${formatDisplayDate(transaction.date)}';
  return transaction.subtitle != null
      ? '$paidOn · ${transaction.subtitle}'
      : paidOn;
}

/// Redesigned (doc option "1c") from a single bordered box stacking a summary, a CTA and
/// a nav row (IA-8) into: a gold hero that's the one place money-colour appears (amount +
/// due date + invoice count, gold only ever meaning "this is what you owe"), a "See the
/// invoices" row promoted out of the summary box, and a Pay button pinned in the thumb
/// zone (TT-5) instead of scrolling away with the rest of the page. ₹ figures now render
/// in Noto Sans Mono, and with real digit grouping — NivasaText.mono's own doc comment
/// names "₹ amounts" as exactly what it's for.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({
    super.key,
    this.authRepository,
    this.paymentsRepository,
    this.cacheStore,
    this.checkout,
  });

  final AuthRepository? authRepository;
  final PaymentsRepository? paymentsRepository;
  final CacheStore? cacheStore;
  final RazorpayCheckout? checkout;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final PaymentsRepository _payments =
      widget.paymentsRepository ?? PaymentsRepository();
  late final CacheStore _cache =
      widget.cacheStore ?? const SharedPreferencesCacheStore();
  late final RazorpayCheckout _checkout =
      widget.checkout ?? RealRazorpayCheckout();

  String? _token;
  List<PendingInvoice> _invoices = [];
  int _totalDue = 0;
  List<TenantTransaction> _transactions = [];
  String? _transactionsError;
  String? _payingInvoiceId;
  bool _loading = true;
  bool _stale = false;
  DateTime? _lastSyncedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _checkout.dispose();
    super.dispose();
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
      final result = await fetchWithCache<PendingInvoices>(
        cache: _cache,
        cacheKey: 'payments_invoices',
        fetchNetwork: () => _payments.pendingInvoices(_token!),
        toJson: (p) => p.toJson(),
        fromJson: (json) =>
            PendingInvoices.fromJson(json as Map<String, dynamic>),
      );
      if (!mounted) return;
      setState(() {
        _invoices = result.data.invoices;
        _totalDue = result.data.totalDue;
        _stale = result.stale;
        _lastSyncedAt = result.lastSyncedAt;
      });
      await _loadTransactions();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your dues — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Kept separate from _load's try/catch so a failure here (still fairly likely — this
  // is a brand-new endpoint) doesn't take down the invoices list and Pay flow above it,
  // which is the part of this screen that actually matters.
  Future<void> _loadTransactions() async {
    try {
      final result = await fetchWithCache<TenantTransactions>(
        cache: _cache,
        cacheKey: 'payments_transactions',
        fetchNetwork: () => _payments.recentTransactions(_token!),
        toJson: (t) => t.toJson(),
        fromJson: (json) =>
            TenantTransactions.fromJson(json as Map<String, dynamic>),
      );
      if (!mounted) return;
      setState(() {
        _transactions = result.data.transactions;
        _transactionsError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _transactionsError = 'Could not load recent transactions');
    }
  }

  Future<void> _pay(PendingInvoice invoice) async {
    if (_token == null) return;
    setState(() => _payingInvoiceId = invoice.invoiceId);
    try {
      final idempotencyKey =
          '${invoice.invoiceId}-${DateTime.now().microsecondsSinceEpoch}';
      final order = await _payments.createOrder(
        _token!,
        invoiceId: invoice.invoiceId,
        idempotencyKey: idempotencyKey,
      );
      if (!mounted) return;
      if (order.keyId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payments are not configured yet — try again later'),
          ),
        );
        setState(() => _payingInvoiceId = null);
        return;
      }
      _checkout.open(
        order: CheckoutOrder(
          keyId: order.keyId!,
          razorpayOrderId: order.razorpayOrderId,
          amountMinorUnits: invoice.amount,
          currency: invoice.currency,
        ),
        name: 'NivasaOS',
        description: 'Rent payment',
        onSuccess: () {
          if (!mounted) return;
          setState(() => _payingInvoiceId = null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Payment submitted — pull to refresh in a moment to confirm',
              ),
            ),
          );
        },
        onError: (message) {
          if (!mounted) return;
          setState(() => _payingInvoiceId = null);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        },
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _payingInvoiceId = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _payingInvoiceId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start payment — try again')),
      );
    }
  }

  void _showInvoices() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NivasaColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NivasaRadius.bottomSheetTop),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NivasaSpacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Invoices', style: NivasaText.h3),
              const SizedBox(height: NivasaSpacing.s16),
              if (_invoices.isEmpty)
                Text(
                  'Nothing to pay right now',
                  style: NivasaText.body.copyWith(color: NivasaColors.ink500),
                )
              else
                ..._invoices.map(
                  (invoice) => Padding(
                    padding: const EdgeInsets.only(bottom: NivasaSpacing.s12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatInr(invoice.amount),
                                style: NivasaText.h3.copyWith(
                                  fontFamily: 'Noto Sans Mono',
                                ),
                              ),
                              const SizedBox(height: NivasaSpacing.s4),
                              Text(
                                'Due ${formatDisplayDate(invoice.dueDate)}',
                                style: NivasaText.bodySmall.copyWith(
                                  color: NivasaColors.ink500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              if (_stale) {
                                _load();
                              } else {
                                _pay(invoice);
                              }
                            },
                            child: Text(_stale ? 'Reconnect' : 'Pay'),
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

  @override
  Widget build(BuildContext context) {
    final primaryInvoice = _invoices.isEmpty ? null : _invoices.first;
    final payments = _transactions.where((t) => t.type == 'payment').toList();
    final canPay = _totalDue > 0 && primaryInvoice != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
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
                          if (_totalDue == 0)
                            const _NothingDueCard()
                          else
                            _RentDueHero(
                              totalDue: _totalDue,
                              invoices: _invoices,
                            ),
                          if (_totalDue > 0) ...[
                            const SizedBox(height: NivasaSpacing.s16),
                            _SeeInvoicesButton(
                              count: _invoices.length,
                              onTap: _showInvoices,
                            ),
                          ],
                          const SizedBox(height: NivasaSpacing.s24),
                          const NivasaSectionLabel('Recent payments'),
                          const SizedBox(height: NivasaSpacing.s12),
                          if (_transactionsError != null)
                            Text(
                              _transactionsError!,
                              style: NivasaText.body.copyWith(
                                color: NivasaColors.ink500,
                              ),
                            )
                          else if (payments.isEmpty)
                            Text(
                              'No recent activity',
                              style: NivasaText.body.copyWith(
                                color: NivasaColors.ink500,
                              ),
                            )
                          else
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
                                  for (var i = 0; i < payments.length; i++) ...[
                                    _PaymentRow(transaction: payments[i]),
                                    if (i != payments.length - 1)
                                      const Divider(
                                        height: 1,
                                        indent: 36,
                                        color: NivasaColors.line,
                                      ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (canPay)
                    _PayBar(
                      label: _stale
                          ? 'Reconnect'
                          : 'Pay ${_formatInr(primaryInvoice.amount)}',
                      loading: _payingInvoiceId == primaryInvoice.invoiceId,
                      onPressed: _stale ? _load : () => _pay(primaryInvoice),
                    ),
                ],
              ),
      ),
    );
  }
}

class _RentDueHero extends StatelessWidget {
  const _RentDueHero({required this.totalDue, required this.invoices});

  final int totalDue;
  final List<PendingInvoice> invoices;

  @override
  Widget build(BuildContext context) {
    final earliestDue = invoices.isEmpty ? null : invoices.first.dueDate;
    return Container(
      padding: const EdgeInsets.all(NivasaSpacing.s20),
      decoration: BoxDecoration(
        color: NivasaColors.gold100,
        border: Border.all(color: NivasaColors.gold200),
        borderRadius: BorderRadius.circular(NivasaRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rent due',
            style: NivasaText.label.copyWith(color: NivasaColors.gold800),
          ),
          const SizedBox(height: NivasaSpacing.s8),
          Text(
            _formatInr(totalDue),
            style: NivasaText.display.copyWith(
              fontFamily: 'Noto Sans Mono',
              color: NivasaColors.goldTextOn,
            ),
          ),
          const SizedBox(height: NivasaSpacing.s8),
          if (earliestDue != null)
            Text(
              '${formatDueDate(earliestDue)} · ${_invoiceCountLabel(invoices.length)}',
              style: NivasaText.bodySmall.copyWith(color: NivasaColors.gold800),
            ),
        ],
      ),
    );
  }
}

class _NothingDueCard extends StatelessWidget {
  const _NothingDueCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NivasaSpacing.s20),
      decoration: BoxDecoration(
        color: NivasaColors.white,
        border: Border.all(color: NivasaColors.line),
        borderRadius: BorderRadius.circular(NivasaRadius.card),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: NivasaColors.positiveFg,
            size: 28,
          ),
          const SizedBox(width: NivasaSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nothing to Pay', style: NivasaText.h3),
                const SizedBox(height: NivasaSpacing.s4),
                Text(
                  "You're all caught up on rent.",
                  style: NivasaText.body.copyWith(color: NivasaColors.ink500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeeInvoicesButton extends StatelessWidget {
  const _SeeInvoicesButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NivasaRadius.button),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(color: NivasaColors.primary700, width: 1.5),
          borderRadius: BorderRadius.circular(NivasaRadius.button),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 19,
              color: NivasaColors.primary700,
            ),
            const SizedBox(width: NivasaSpacing.s8),
            Text(
              'See the ${_invoiceCountLabel(count)}',
              style: NivasaText.body.copyWith(
                color: NivasaColors.primary700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.transaction});

  final TenantTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NivasaSpacing.s16,
        vertical: 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: NivasaColors.positiveFg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: NivasaSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title,
                  style: NivasaText.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(_paymentSubtitle(transaction), style: NivasaText.caption),
              ],
            ),
          ),
          Text(
            _formatInr(transaction.amount),
            style: NivasaText.mono.copyWith(
              fontSize: 15,
              color: NivasaColors.ink900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned in the thumb zone (TT-5) instead of scrolling away with the rest of the page —
/// a Column+Expanded footer rather than the mock's CSS `position:absolute`, so it can
/// never overlap the last row above it (the same class of bug 1e's redesign caption
/// flags for Maintenance's FAB).
class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        NivasaSpacing.s24,
        NivasaSpacing.s12,
        NivasaSpacing.s24,
        NivasaSpacing.s24,
      ),
      decoration: const BoxDecoration(
        color: NivasaColors.white,
        border: Border(top: BorderSide(color: NivasaColors.line)),
      ),
      child: SizedBox(
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: NivasaColors.gold500,
            foregroundColor: NivasaColors.goldTextOn,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NivasaRadius.button),
            ),
          ),
          onPressed: loading ? null : onPressed,
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(NivasaColors.goldTextOn),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Noto Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: NivasaColors.goldTextOn,
                  ),
                ),
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
