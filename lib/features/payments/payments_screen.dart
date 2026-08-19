import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/cache_store.dart';
import '../../core/cached_fetch.dart';
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
        fromJson: (json) => PendingInvoices.fromJson(json as Map<String, dynamic>),
      );
      if (!mounted) return;
      setState(() {
        _invoices = result.data.invoices;
        _totalDue = result.data.totalDue;
        _stale = result.stale;
        _lastSyncedAt = result.lastSyncedAt;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load your dues — try again');
    } finally {
      if (mounted) setState(() => _loading = false);
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Payment submitted — pull to refresh in a moment to confirm')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(NivasaSpacing.s24),
                  children: [
                    if (_stale) ...[
                      NivasaStaleBanner(lastSyncedAt: _lastSyncedAt),
                      const SizedBox(height: NivasaSpacing.s16),
                    ],
                    Container(
                      padding: const EdgeInsets.all(NivasaSpacing.s16),
                      decoration: BoxDecoration(
                        color: NivasaColors.white,
                        border: Border.all(color: NivasaColors.line),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total due', style: NivasaText.label.copyWith(color: NivasaColors.ink500)),
                          const SizedBox(height: NivasaSpacing.s8),
                          Text(_formatInr(_totalDue), style: NivasaText.h1),
                        ],
                      ),
                    ),
                    const SizedBox(height: NivasaSpacing.s24),
                    Text('Pending invoices', style: NivasaText.label.copyWith(color: NivasaColors.ink500)),
                    const SizedBox(height: NivasaSpacing.s12),
                    if (_invoices.isEmpty)
                      Text('Nothing to pay right now', style: NivasaText.body.copyWith(color: NivasaColors.ink500))
                    else
                      ..._invoices.map(
                        (invoice) => Padding(
                          padding: const EdgeInsets.only(bottom: NivasaSpacing.s12),
                          child: Container(
                            padding: const EdgeInsets.all(NivasaSpacing.s16),
                            decoration: BoxDecoration(
                              color: NivasaColors.white,
                              border: Border.all(color: NivasaColors.line),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_formatInr(invoice.amount), style: NivasaText.h3),
                                      const SizedBox(height: NivasaSpacing.s4),
                                      Text('Due ${invoice.dueDate}', style: NivasaText.body.copyWith(color: NivasaColors.ink500, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 100,
                                  child: NivasaPrimaryButton(
                                    label: _stale ? 'Reconnect' : 'Pay',
                                    loading: _payingInvoiceId == invoice.invoiceId,
                                    loadingLabel: '…',
                                    onPressed: _stale ? null : () => _pay(invoice),
                                  ),
                                ),
                              ],
                            ),
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
