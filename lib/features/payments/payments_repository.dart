import '../../core/api_client.dart';
import '../../core/date_utils.dart' show shortDate;

class PendingInvoice {
  const PendingInvoice({required this.invoiceId, required this.amount, required this.currency, required this.dueDate, required this.status});

  final String invoiceId;
  final int amount;
  final String currency;
  final String dueDate;
  final String status;

  factory PendingInvoice.fromJson(Map<String, dynamic> json) => PendingInvoice(
    invoiceId: json['invoice_id'] as String,
    amount: json['amount'] as int,
    currency: json['currency'] as String,
    dueDate: shortDate(json['due_date'] as String),
    status: json['status'] as String,
  );

  Map<String, dynamic> toJson() => {'invoice_id': invoiceId, 'amount': amount, 'currency': currency, 'due_date': dueDate, 'status': status};
}

class PendingInvoices {
  const PendingInvoices({required this.invoices, required this.totalDue});

  final List<PendingInvoice> invoices;
  final int totalDue;

  factory PendingInvoices.fromJson(Map<String, dynamic> json) => PendingInvoices(
    invoices: (json['invoices'] as List).map((i) => PendingInvoice.fromJson(i as Map<String, dynamic>)).toList(),
    totalDue: json['total_due'] as int,
  );

  Map<String, dynamic> toJson() => {'invoices': invoices.map((i) => i.toJson()).toList(), 'total_due': totalDue};
}

/// Deliberately doesn't carry amount/currency — the caller already knows both from the
/// `PendingInvoice` it created this order for, so there's no need to trust (or add to
/// payment-service's shared order-creation response shape for) a duplicate copy here.
class RazorpayOrder {
  const RazorpayOrder({required this.paymentId, required this.invoiceId, required this.razorpayOrderId, this.keyId});

  final String paymentId;
  final String invoiceId;
  final String razorpayOrderId;
  final String? keyId;

  factory RazorpayOrder.fromJson(Map<String, dynamic> json) => RazorpayOrder(
    paymentId: json['payment_id'] as String,
    invoiceId: json['invoice_id'] as String,
    razorpayOrderId: json['razorpay_order_id'] as String,
    keyId: json['key_id'] as String?,
  );
}

/// One row in the Payments screen's "Recent transactions" feed — either a confirmed
/// payment or a still-pending invoice, as returned by `/tenant/me/transactions`.
class TenantTransaction {
  const TenantTransaction({
    required this.transactionId,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.currency,
    required this.date,
  });

  final String transactionId;
  final String type;
  final String title;
  final String? subtitle;
  final int amount;
  final String currency;
  final String date;

  factory TenantTransaction.fromJson(Map<String, dynamic> json) => TenantTransaction(
    transactionId: json['transaction_id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    subtitle: json['subtitle'] as String?,
    amount: json['amount'] as int,
    currency: json['currency'] as String,
    date: shortDate(json['date'] as String),
  );

  Map<String, dynamic> toJson() => {
    'transaction_id': transactionId,
    'type': type,
    'title': title,
    'subtitle': subtitle,
    'amount': amount,
    'currency': currency,
    'date': date,
  };
}

class TenantTransactions {
  const TenantTransactions({required this.transactions});

  final List<TenantTransaction> transactions;

  factory TenantTransactions.fromJson(Map<String, dynamic> json) => TenantTransactions(
    transactions: (json['transactions'] as List).map((t) => TenantTransaction.fromJson(t as Map<String, dynamic>)).toList(),
  );

  Map<String, dynamic> toJson() => {'transactions': transactions.map((t) => t.toJson()).toList()};
}

/// payment-service's `/tenant/me/invoices` + `/tenant/me/orders` + `/tenant/me/transactions`
/// — the tenant-scoped counterpart to the existing manager-facing order-creation flow,
/// plus a `total_due` summary that finally gives the Home screen's payment banner
/// (currently static) a real number to eventually show.
class PaymentsRepository {
  PaymentsRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<PendingInvoices> pendingInvoices(String token) async {
    final body = await _api.get('/api/payments/v1/tenant/me/invoices', token: token);
    return PendingInvoices.fromJson(body);
  }

  Future<TenantTransactions> recentTransactions(String token) async {
    final body = await _api.get('/api/payments/v1/tenant/me/transactions', token: token);
    return TenantTransactions.fromJson(body);
  }

  Future<RazorpayOrder> createOrder(String token, {required String invoiceId, required String idempotencyKey}) async {
    final body = await _api.post('/api/payments/v1/tenant/me/orders', {
      'invoice_id': invoiceId,
      'idempotency_key': idempotencyKey,
    }, token: token);
    return RazorpayOrder.fromJson(body);
  }
}
