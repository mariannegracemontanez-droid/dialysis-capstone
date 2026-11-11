import 'donation_checkout_service.dart';

/// Builds the downloadable record of a completed donation.
///
/// Every figure comes from the checkout the SERVER returned (reference,
/// amount, recipients, dates); nothing is computed or assumed here. The
/// wording depends on what actually happened:
///
///  * live, provider-confirmed payment -> "Donation Receipt", "Payment confirmed";
///  * simulated payment or PayMongo test mode -> "Donation Acknowledgement",
///    stating plainly that no money was charged or transferred.
///
/// Only completed donations get a document; anything else throws.
class DonationReceipt {
  DonationReceipt(this.checkout, {DateTime? generatedAt})
      : generatedAt = generatedAt ?? DateTime.now() {
    if (!checkout.isSuccessful) {
      throw StateError('A receipt is only available for a completed donation.');
    }
  }

  final DonationCheckout checkout;
  final DateTime generatedAt;

  /// A live payment confirmed by the provider: the only case that is a real
  /// payment receipt.
  bool get isLivePayment => !checkout.isSandbox && checkout.paymentStatus == 'paid';

  String get title => isLivePayment ? 'Donation Receipt' : 'Donation Acknowledgement';

  String get paymentStatusText {
    if (isLivePayment) return 'Payment confirmed';
    if (checkout.usesPaymongo) return 'Completed in PayMongo test mode (no real money)';
    return 'Completed with a simulated payment (no real money)';
  }

  /// Shown on every non-live document; empty for a live receipt.
  String get disclosure => isLivePayment
      ? ''
      : 'This is not a payment receipt. The donation was completed with a '
          'simulated payment: no money was charged and no funds were '
          'transferred to any center.';

  String get fileName {
    final safeRef = checkout.reference.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return 'CureNurture-${isLivePayment ? 'receipt' : 'acknowledgement'}-$safeRef.html';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String formatDateTime(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${months[d.month - 1]} ${d.day}, ${d.year} · $hour:${_two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  String get modeLabel {
    switch (checkout.mode) {
      case DonationMode.specificCenter:
        return 'Specific dialysis center';
      case DonationMode.randomCenter:
        return 'Randomly assigned center';
      case DonationMode.allCenters:
        return 'Shared equally among all centers';
      case null:
        return 'Not recorded';
    }
  }

  /// Rows of label/value pairs, in display order (used by the HTML and tests).
  List<(String, String)> get details => [
        ('Reference', checkout.reference),
        if (checkout.createdAt != null) ('Donation date', formatDateTime(checkout.createdAt!)),
        if (checkout.confirmedAt != null)
          (isLivePayment ? 'Payment confirmed' : 'Completed', formatDateTime(checkout.confirmedAt!)),
        ('Amount', formatCentavos(checkout.amountCentavos)),
        ('Donation option', modeLabel),
        ('Payment method', 'GCash'),
        ('Payment status', paymentStatusText),
      ];

  int get allocatedCentavos => checkout.allocations.fold(0, (sum, a) => sum + a.amountCentavos);

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  /// A self-contained, printable HTML document (no external resources).
  String toHtml() {
    final b = StringBuffer()
      ..writeln('<!doctype html>')
      ..writeln('<html lang="en"><head><meta charset="utf-8">')
      ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
      ..writeln('<title>${_esc(title)} ${_esc(checkout.reference)}</title>')
      ..writeln('<style>'
          'body{font-family:Arial,Helvetica,sans-serif;color:#1f2d3d;margin:0;padding:32px;background:#f4f7fa}'
          '.doc{max-width:640px;margin:0 auto;background:#fff;border:1px solid #e4ebf1;border-radius:14px;padding:32px}'
          'h1{font-size:22px;margin:0 0 4px}.brand{color:#2a5f7e;font-weight:700;letter-spacing:.3px}'
          '.muted{color:#7c8b9b;font-size:13px}table{width:100%;border-collapse:collapse;margin-top:16px}'
          'td,th{padding:8px 6px;border-bottom:1px solid #eef2f6;text-align:left;font-size:14px}'
          'th{font-size:12px;text-transform:uppercase;color:#4a5c70}.num{text-align:right}'
          '.note{margin-top:20px;padding:12px 14px;border-radius:10px;background:#f4f8fa;font-size:13px;color:#4a5c70}'
          '.total td{font-weight:700;border-bottom:none}@media print{body{background:#fff;padding:0}.doc{border:none}}'
          '</style></head><body><div class="doc">')
      ..writeln('<div class="brand">CureNurture</div>')
      ..writeln('<h1>${_esc(title)}</h1>')
      ..writeln('<div class="muted">Generated ${_esc(formatDateTime(generatedAt))}</div>')
      ..writeln('<table>');
    for (final (label, value) in details) {
      b.writeln('<tr><th>${_esc(label)}</th><td>${_esc(value)}</td></tr>');
    }
    b
      ..writeln('</table>')
      ..writeln('<table><tr><th>Recipient center</th><th class="num">Amount</th></tr>');
    for (final a in checkout.allocations) {
      b.writeln('<tr><td>${_esc(a.clinicName)}</td><td class="num">${_esc(formatCentavos(a.amountCentavos))}</td></tr>');
    }
    b.writeln('<tr class="total"><td>Total</td><td class="num">${_esc(formatCentavos(allocatedCentavos))}</td></tr></table>');
    if (disclosure.isNotEmpty) b.writeln('<div class="note">${_esc(disclosure)}</div>');
    b
      ..writeln('<div class="note">Thank you for supporting dialysis patients through CureNurture.</div>')
      ..writeln('</div></body></html>');
    return b.toString();
  }
}
