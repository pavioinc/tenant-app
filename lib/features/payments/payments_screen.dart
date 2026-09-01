import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
import '../../core/date_utils.dart';
import '../../core/razorpay_checkout.dart';
import '../../theme/nivasa_colors.dart';
import '../../theme/nivasa_spacing.dart';
import '../../theme/nivasa_text_styles.dart';
import '../../widgets/nivasa_button.dart';
import '../../widgets/nivasa_stale_banner.dart';
import '../auth/auth_repository.dart';
import 'payments_repository.dart';

String _formatInr(int amountMinor) => '₹${(amountMinor / 100).toStringAsFixed(0)}';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, this.authRepository, this.paymentsRepository, this.cacheStore, this.checkout});

  final AuthRepository? authRepository;
  final PaymentsRepository? paymentsRepository;
  final CacheStore? cacheStore;
  final RazorpayCheckout? checkout;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  late final PaymentsRepository _payments = widget.paymentsRepository ?? PaymentsRepository();
  late final CacheStore _cache = widget.cacheStore ?? const SharedPreferencesCacheStore();
  late final RazorpayCheckout _checkout = widget.checkout ?? RealRazorpayCheckout();

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
      final result = await fetchWithCache<PendingInvoices>(cache: _cache, cacheKey: 'payments_invoices', fetchNetwork: () => _payments.pendingInvoices(_token!), toJson: (p) => p.toJson(), fromJson: (json) => PendingInvoices.fromJson(json as Map<String, dynamic>));
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
      final result = await fetchWithCache<TenantTransactions>(cache: _cache, cacheKey: 'payments_transactions', fetchNetwork: () => _payments.recentTransactions(_token!), toJson: (t) => t.toJson(), fromJson: (json) => TenantTransactions.fromJson(json as Map<String, dynamic>));
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
      final idempotencyKey = '${invoice.invoiceId}-${DateTime.now().microsecondsSinceEpoch}';
      final order = await _payments.createOrder(_token!, invoiceId: invoice.invoiceId, idempotencyKey: idempotencyKey);
      if (!mounted) return;
      if (order.keyId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payments are not configured yet — try again later')));
        setState(() => _payingInvoiceId = null);
        return;
      }
      _checkout.open(
        order: CheckoutOrder(keyId: order.keyId!, razorpayOrderId: order.razorpayOrderId, amountMinorUnits: invoice.amount, currency: invoice.currency),
        name: 'NivasaOS',
        description: 'Rent payment',
        onSuccess: () {
          if (!mounted) return;
          setState(() => _payingInvoiceId = null);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment submitted — pull to refresh in a moment to confirm')));
        },
        onError: (message) {
          if (!mounted) return;
          setState(() => _payingInvoiceId = null);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        },
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _payingInvoiceId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _payingInvoiceId = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start payment — try again')));
    }
  }

  void _showBalanceDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NivasaColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(NivasaRadius.bottomSheetTop))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NivasaSpacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Balance details', style: NivasaText.h3),
              const SizedBox(height: NivasaSpacing.s16),
              if (_invoices.isEmpty)
                Text('Nothing to pay right now', style: NivasaText.body.copyWith(color: NivasaColors.ink500))
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
                              Text(_formatInr(invoice.amount), style: NivasaText.h3.copyWith(fontFamily: 'Noto Sans Mono')),
                              const SizedBox(height: NivasaSpacing.s4),
                              Text('Due ${formatDisplayDate(invoice.dueDate)}', style: NivasaText.bodySmall.copyWith(color: NivasaColors.ink500)),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: NivasaPrimaryButton(
                            label: _stale ? 'Reconnect' : 'Pay',
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              if (_stale) {
                                _load();
                              } else {
                                _pay(invoice);
                              }
                            },
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
                      padding: const EdgeInsets.fromLTRB(NivasaSpacing.s24, NivasaSpacing.s24, NivasaSpacing.s24, 0),
                      child: NivasaStaleBanner(lastSyncedAt: _lastSyncedAt, onRetry: _load),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(NivasaSpacing.s24),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(NivasaSpacing.s20),
                            decoration: BoxDecoration(
                              color: NivasaColors.white,
                              border: Border.all(color: NivasaColors.line),
                              borderRadius: BorderRadius.circular(NivasaRadius.card),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_totalDue == 0 ? 'Nothing to Pay' : 'Amount Due', style: NivasaText.h3),
                                const SizedBox(height: NivasaSpacing.s8),
                                Text(_formatInr(_totalDue), style: NivasaText.display.copyWith(fontFamily: 'Noto Sans Mono')),
                                const SizedBox(height: NivasaSpacing.s20),
                                SizedBox(
                                  width: double.infinity,
                                  child: NivasaPrimaryButton(
                                    label: _stale ? 'Reconnect' : 'Pay now',
                                    loading: primaryInvoice != null && _payingInvoiceId == primaryInvoice.invoiceId,
                                    loadingLabel: '…',
                                    onPressed: _stale
                                        ? _load
                                        : primaryInvoice == null
                                        ? null
                                        : () => _pay(primaryInvoice),
                                  ),
                                ),
                                const SizedBox(height: NivasaSpacing.s20),
                                const Divider(height: 1),
                                _ActionRow(icon: Icons.receipt_long_outlined, label: 'View Balance Details', onTap: _showBalanceDetails),
                                //_ActionRow(icon: Icons.account_balance_wallet_outlined, label: 'Manage Payment Methods', onTap: _comingSoon, disabled: true),
                                //_ActionRow(icon: Icons.autorenew, label: 'Manage Auto Payments', onTap: _comingSoon, disabled: true),
                                //_ActionRow(icon: Icons.account_balance_outlined, label: 'Manage Refund Account', onTap: _comingSoon, disabled: true),
                              ],
                            ),
                          ),
                          const SizedBox(height: NivasaSpacing.s24),
                          Text('Recent transactions', style: NivasaText.label.copyWith(color: NivasaColors.ink700)),
                          const SizedBox(height: NivasaSpacing.s12),
                          if (_transactionsError != null)
                            Text(_transactionsError!, style: NivasaText.body.copyWith(color: NivasaColors.ink500))
                          else if (_transactions.isEmpty)
                            Text('No recent activity', style: NivasaText.body.copyWith(color: NivasaColors.ink500))
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: NivasaSpacing.s16),
                              decoration: BoxDecoration(
                                color: NivasaColors.white,
                                border: Border.all(color: NivasaColors.line),
                                borderRadius: BorderRadius.circular(NivasaRadius.card),
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < _transactions.length; i++) ...[_TransactionRow(transaction: _transactions[i]), if (i != _transactions.length - 1) const Divider(height: 1)],
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NivasaSpacing.s12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: NivasaColors.ink700),
            const SizedBox(width: NivasaSpacing.s12),
            Expanded(
              child: Text(label, style: NivasaText.body),
            ),
            const Icon(Icons.chevron_right, size: 20, color: NivasaColors.ink400),
          ],
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction});

  final TenantTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NivasaSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(transaction.title, style: NivasaText.body.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(
                _formatInr(transaction.amount),
                style: NivasaText.body.copyWith(fontWeight: FontWeight.w600, fontFamily: 'Noto Sans Mono'),
              ),
            ],
          ),
          const SizedBox(height: NivasaSpacing.s4),
          Text(transaction.subtitle ?? formatDisplayDate(transaction.date), style: NivasaText.caption),
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
