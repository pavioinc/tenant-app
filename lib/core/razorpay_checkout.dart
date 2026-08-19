import 'package:razorpay_flutter/razorpay_flutter.dart' as sdk;

class CheckoutOrder {
  const CheckoutOrder({required this.keyId, required this.razorpayOrderId, required this.amountMinorUnits, required this.currency});

  final String keyId;
  final String razorpayOrderId;
  final int amountMinorUnits;
  final String currency;
}

/// Thin seam over `razorpay_flutter`'s native checkout SDK, same shape/reason as
/// `FilePickerService`/`UrlOpener` — a platform channel `flutter test` can't exercise,
/// so tests inject a fake instead. The SDK's own success callback is optimistic, not
/// authoritative — payment-service's webhook (unchanged by this arc, see its README)
/// is the real source of truth; [onSuccess] here just means "the checkout sheet
/// reported success," not "the invoice is confirmed paid."
abstract class RazorpayCheckout {
  void open({required CheckoutOrder order, required String name, required String description, required void Function() onSuccess, required void Function(String message) onError});

  void dispose();
}

class RealRazorpayCheckout implements RazorpayCheckout {
  RealRazorpayCheckout() : _razorpay = sdk.Razorpay();

  final sdk.Razorpay _razorpay;

  @override
  void open({
    required CheckoutOrder order,
    required String name,
    required String description,
    required void Function() onSuccess,
    required void Function(String message) onError,
  }) {
    _razorpay.on(sdk.Razorpay.EVENT_PAYMENT_SUCCESS, (_) => onSuccess());
    _razorpay.on(sdk.Razorpay.EVENT_PAYMENT_ERROR, (sdk.PaymentFailureResponse response) => onError(response.message ?? 'Payment failed'));
    _razorpay.open({
      'key': order.keyId,
      'order_id': order.razorpayOrderId,
      'amount': order.amountMinorUnits,
      'currency': order.currency,
      'name': name,
      'description': description,
    });
  }

  @override
  void dispose() => _razorpay.clear();
}
