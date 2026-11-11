import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/payment_config.dart';
import '../services/donation_checkout_service.dart';
import '../services/donation_receipt.dart';
import '../theme/brand.dart';
import '../utils/file_download.dart' as file_download;
import '../widgets/donation_steps.dart';
import '../widgets/ui.dart';
import 'donation_option_page.dart';
import 'landing_page.dart';

String donationModeLabel(DonationMode? mode) {
  switch (mode) {
    case DonationMode.specificCenter:
      return 'Specific Dialysis Center';
    case DonationMode.randomCenter:
      return 'Randomly assigned center';
    case DonationMode.allCenters:
      return 'Donate to All Centers (equal split)';
    case null:
      return 'Not recorded';
  }
}

/// Step three: review the donation the SERVER recorded (amount, recipients,
/// GCash), then pay through the sandbox -- PayMongo test checkout when it is
/// configured, otherwise the clearly-labelled internal demo simulator -- and
/// see the result.
///
/// Nothing on this page decides whether a payment succeeded. Every status
/// shown is read back from the database, which only changes it through the
/// simulator RPC (sandbox only) or a verified PayMongo webhook.
/// Opens a validated PayMongo checkout URL; returns whether it was opened.
typedef CheckoutUrlLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLaunchCheckout(Uri uri) =>
    launchUrl(uri, webOnlyWindowName: '_blank');

/// Saves a generated file for the donor; injectable for tests.
typedef ReceiptDownloader = void Function(String fileName, Uint8List bytes, String mimeType);

void _defaultDownload(String fileName, Uint8List bytes, String mimeType) =>
    file_download.downloadBytes(fileName: fileName, bytes: bytes, mimeType: mimeType);

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({
    super.key,
    required this.checkout,
    required this.clientSecret,
    this.service,
    this.launchCheckout = _defaultLaunchCheckout,
    this.showTestOutcomes = kSimulatorTestControls,
    this.downloadFile = _defaultDownload,
  });

  /// Saves the donation receipt; defaults to a browser download.
  final ReceiptDownloader downloadFile;

  final DonationCheckout checkout;
  final String clientSecret;
  final DonationCheckoutService? service;

  /// Injectable for tests; defaults to `launchUrl` in a new tab.
  final CheckoutUrlLauncher launchCheckout;

  /// Shows the developer-only failed/cancelled simulator outcomes. Never on
  /// for donors (see [kSimulatorTestControls]).
  final bool showTestOutcomes;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  late final DonationCheckoutService _service =
      widget.service ?? DonationCheckoutService();
  late DonationCheckout _checkout = widget.checkout;

  bool _busy = false;
  String? _error;

  /// The donor's explicit confirmation that they reviewed the amount and
  /// recipient(s); required before the donation is submitted for payment.
  bool _reviewConfirmed = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Poll only once a PayMongo session exists ('processing'); a 'pending'
    // donation has no session for the webhook to complete yet.
    if (_checkout.usesPaymongo && _checkout.paymentStatus == 'processing') {
      _startPolling();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _poll?.cancel();
    // The webhook, not the browser, marks a PayMongo payment as paid; this
    // only re-reads the server's answer.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final latest =
          await _service.fetchCheckout(_checkout.donationId, widget.clientSecret);
      if (!mounted) return;
      setState(() => _checkout = latest);
      if (!latest.isOpen) {
        _poll?.cancel();
        await _service.clearPending();
      }
    } catch (_) {
      // Keep showing the last known state; the next action reports errors.
    }
  }

  /// Runs [action] and returns its result, or null when it failed (the error
  /// is shown) or the page was disposed meanwhile.
  Future<DonationCheckout?> _run(Future<DonationCheckout> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return null;
      setState(() => _checkout = result);
      if (!result.isOpen) await _service.clearPending();
      return result;
    } on DonationCheckoutException catch (e) {
      if (!mounted) return null;
      setState(() => _error = e.message);
      await _refresh();
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPaymongo() async {
    final result = await _run(() => _service.startPaymongoCheckout(
          _checkout.donationId,
          widget.clientSecret,
        ));
    // Failed (or abandoned) request: never launch a stale URL, never poll.
    if (result == null || !mounted) return;

    // Only the URL from THIS successful response, and only if it is a
    // genuine PayMongo checkout URL.
    final uri = trustedPaymongoCheckoutUri(result.checkoutUrl);
    if (uri == null) {
      setState(() => _error =
          'The PayMongo test checkout link was not valid. Please try again.');
      return;
    }

    bool opened;
    try {
      opened = await widget.launchCheckout(uri);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (!opened) {
      setState(() => _error = 'Could not open the PayMongo test checkout.');
    }
    // The session exists now; follow the server's answer.
    _startPolling();
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingPage()),
      (route) => false,
    );
  }

  // ---------------------------------------------------------- presentation

  /// Per-centre note, only where it tells the donor something the summary
  /// does not: a payout state, or that nothing was allocated.
  String _allocationStatusLabel(String? status) {
    switch (status) {
      case 'pending_payout':
        return 'Pending payout';
      case 'paid_out':
        return 'Paid out';
      case 'void':
        return 'Not allocated';
      default:
        return '';
    }
  }

  /// How the payment is processed, in plain words; null for a live payment.
  String? get _paymentTypeLabel {
    final c = _checkout;
    if (c.usesSimulator) return 'Simulated payment';
    if (c.isSandbox) return 'PayMongo test mode';
    return null;
  }

  void _downloadReceipt() {
    final receipt = DonationReceipt(_checkout);
    try {
      widget.downloadFile(
        receipt.fileName,
        Uint8List.fromList(utf8.encode(receipt.toHtml())),
        'text/html;charset=utf-8',
      );
    } on UnsupportedError {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipts can be downloaded from the web browser.')),
      );
    }
  }

  Widget _row(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: Brand.body(13.5, color: Brand.textMuted)),
          ),
          Expanded(
            child: Text(
              value,
              style: strong
                  ? Brand.label(15.5, color: Brand.textStrong)
                  : Brand.label(14, color: Brand.textStrong),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Brand.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Brand.border),
        boxShadow: Brand.shadowCard,
      ),
      child: child,
    );
  }

  Widget _buildSummary() {
    final c = _checkout;
    final total = c.allocations.fold<int>(0, (sum, a) => sum + a.amountCentavos);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review your donation', style: Brand.heading(19)),
          const SizedBox(height: 12),
          _row('Reference', c.reference),
          _row('Donation option', donationModeLabel(c.mode)),
          _row('Amount', formatCentavos(c.amountCentavos), strong: true),
          _row('Payment method', 'GCash'),
          if (_paymentTypeLabel != null) _row('Payment type', _paymentTypeLabel!),
          const SizedBox(height: 18),
          Text(
            c.allocations.length == 1
                ? 'Recipient center'
                : 'Recipient centers (${c.allocations.length})',
            style: Brand.label(15, color: Brand.textStrong),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Brand.tealSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < c.allocations.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Brand.brand.withValues(alpha: 0.12)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.local_hospital_rounded, color: Brand.brand, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.allocations[i].clinicName, style: Brand.label(14, color: Brand.textStrong)),
                              if (_allocationStatusLabel(c.allocations[i].status).isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _allocationStatusLabel(c.allocations[i].status),
                                  style: Brand.body(12, color: Brand.textMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(formatCentavos(c.allocations[i].amountCentavos),
                            style: Brand.label(14, color: Brand.brandDeep)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (c.allocations.length > 1) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total allocated: ${formatCentavos(total)}',
                style: Brand.label(14, color: Brand.brandDeep),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Small, unobtrusive sandbox notice (replaces the old full-width banner
  /// on this page). Never claims a real GCash or PayMongo payment.
  Widget _sandboxNotice() {
    return Row(
      key: const ValueKey('sandbox-notice'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline_rounded, size: 16, color: Brand.textMuted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _checkout.usesPaymongo
                ? '$kDemoBannerText PayMongo is in test mode.'
                : kDemoBannerText,
            style: Brand.body(12.5, color: Brand.textMuted),
          ),
        ),
      ],
    );
  }

  /// The single primary action. Disabled until the review is confirmed;
  /// shows progress while the server records the result.
  Widget _primaryAction({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final enabled = _reviewConfirmed && !_busy;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        key: key,
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Brand.coral,
          disabledBackgroundColor: Brand.coral.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, letterSpacing: 0.2),
        ),
        child: _busy
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 10),
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }

  /// Cancels the open donation after an explicit confirmation. Nothing has
  /// been charged; the result screen then says so clearly.
  Future<void> _confirmAndCancel() async {
    final c = _checkout;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Cancel this donation?', style: Brand.heading(19)),
        content: Text(
          'Donation ${c.reference} for ${formatCentavos(c.amountCentavos)} will be '
          'cancelled. Nothing has been charged.',
          style: Brand.body(14),
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-keep'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          ElevatedButton(
            key: const ValueKey('cancel-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Brand.coral,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Yes, cancel it'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await _run(() => _service.cancel(c.donationId, widget.clientSecret));
    }
  }

  /// Developer/test-only outcomes for the sandbox simulator. Hidden from
  /// donors; shown only when the app is started with
  /// --dart-define=CURENURTURE_SIMULATOR_TEST_CONTROLS=true (or in tests).
  Widget _testOutcomes(String id, String secret) {
    return Container(
      key: const ValueKey('test-outcomes'),
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Brand.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Developer test outcomes (not shown to donors)',
              style: Brand.label(12.5, color: Brand.textMuted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('simulate-failure'),
                onPressed: _busy ? null : () => _run(() => _service.simulate(id, secret, 'failure')),
                child: const Text('Simulate failed payment'),
              ),
              OutlinedButton(
                key: const ValueKey('simulate-cancel'),
                onPressed: _busy ? null : () => _run(() => _service.simulate(id, secret, 'cancel')),
                child: const Text('Simulate cancelled payment'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayActions() {
    final c = _checkout;
    final id = c.donationId;
    final secret = widget.clientSecret;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.usesPaymongo ? 'Pay with GCash' : 'Complete your donation',
              style: Brand.heading(19)),
          const SizedBox(height: 14),
          _buildReviewConfirmation(),
          const SizedBox(height: 18),
          if (c.usesSimulator) ...[
            _primaryAction(
              key: const ValueKey('complete-donation'),
              label: 'Complete donation',
              icon: Icons.favorite_rounded,
              onPressed: () => _run(() => _service.simulate(id, secret, 'success')),
            ),
            const SizedBox(height: 12),
            _sandboxNotice(),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                key: const ValueKey('cancel-donation'),
                onPressed: _busy ? null : _confirmAndCancel,
                child: const Text('Cancel this donation'),
              ),
            ),
            if (widget.showTestOutcomes) _testOutcomes(id, secret),
          ] else if (c.usesPaymongo) ...[
            Text(
              'You will continue to PayMongo to finish with GCash. This page '
              'updates automatically once the payment is confirmed.',
              style: Brand.body(13.5),
            ),
            const SizedBox(height: 16),
            _primaryAction(
              key: const ValueKey('paymongo-continue'),
              label: c.checkoutUrl == null
                  ? 'Continue to GCash (PayMongo test)'
                  : 'Reopen PayMongo test checkout',
              icon: Icons.open_in_new_rounded,
              onPressed: _openPaymongo,
            ),
            const SizedBox(height: 12),
            _sandboxNotice(),
            if (c.paymentStatus == 'processing') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Waiting for PayMongo to confirm the payment…',
                      style: Brand.body(13),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                key: const ValueKey('cancel-donation'),
                onPressed: _busy ? null : _confirmAndCancel,
                child: const Text('Cancel this donation'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Final review: the donor confirms the amount and recipient(s) shown above
  /// before submitting. Outcomes that submit nothing (failed / cancel) stay
  /// available without it.
  Widget _buildReviewConfirmation() {
    final c = _checkout;
    void toggle() => setState(() => _reviewConfirmed = !_reviewConfirmed);
    // The whole row (box and sentence) toggles the confirmation, and reads
    // as one checkbox to assistive technology.
    return MergeSemantics(
      child: Material(
        color: Brand.tealSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const ValueKey('review-confirm-row'),
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    key: const ValueKey('review-confirm'),
                    value: _reviewConfirmed,
                    activeColor: Brand.brand,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: _busy ? null : (_) => toggle(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'I have reviewed this donation of ${formatCentavos(c.amountCentavos)} '
                    'and its recipient ${c.allocations.length == 1 ? 'center' : 'centers'}, '
                    'and I confirm it.',
                    style: Brand.label(13.5, color: Brand.textStrong),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _buildResult() {
    final c = _checkout;
    late final IconData icon;
    late final Color color;
    late final String title;
    late final String body;

    if (c.paymentStatus == 'simulated_paid') {
      icon = Icons.check_circle_rounded;
      color = Brand.mint;
      title = 'Donation complete';
      body = 'Your donation has been recorded with the allocation shown above. '
          'This was a simulated payment, so no real money was charged or '
          'transferred.';
    } else if (c.paymentStatus == 'paid') {
      icon = Icons.check_circle_rounded;
      color = Brand.mint;
      title = c.isSandbox
          ? 'Test payment confirmed'
          : 'Payment confirmed';
      body = c.isSandbox
          ? 'PayMongo confirmed this test-mode payment. Test mode uses no real '
              'money, so no funds were transferred.'
          : 'Thank you! Your donation has been confirmed.';
    } else if (c.paymentStatus == 'failed') {
      icon = Icons.error_rounded;
      color = Brand.coral;
      title = 'Payment failed';
      body = 'The payment did not go through, so nothing was recorded as '
          'donated. You can start a new donation from the home page.';
    } else {
      icon = Icons.cancel_rounded;
      color = Brand.textMuted;
      title = 'Donation cancelled';
      body = c.statusReason?.startsWith('Recipient no longer eligible') == true
          ? 'A selected center stopped accepting donations before payment '
              'was completed (${c.statusReason!.split(': ').last}). Nothing was '
              'charged. Please start a new donation.'
          : 'This donation was cancelled and nothing was charged.';
    }

    final success = c.isSuccessful;

    return _card(
      child: Column(
        children: [
          Icon(icon, color: color, size: 52),
          const SizedBox(height: 12),
          if (success) ...[
            Text('Thank You!', textAlign: TextAlign.center, style: Brand.heading(26)),
            const SizedBox(height: 6),
          ],
          Text(title, textAlign: TextAlign.center, style: Brand.heading(20)),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: Brand.body(14)),
          if (success) ...[
            const SizedBox(height: 12),
            Text(
              'Reference ${c.reference} · ${formatCentavos(c.amountCentavos)}'
              '${c.confirmedAt != null ? ' · confirmed ${_formatDate(c.confirmedAt!)}' : ''}',
              key: const ValueKey('completion-details'),
              textAlign: TextAlign.center,
              style: Brand.label(13.5, color: Brand.brandDeep),
            ),
            const SizedBox(height: 12),
            // Receipt: where the donation goes, exactly as recorded.
            Container(
              key: const ValueKey('receipt-allocations'),
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Brand.tealSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  for (final a in c.allocations)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(child: Text(a.clinicName, style: Brand.body(13, color: Brand.textStrong))),
                          Text(formatCentavos(a.amountCentavos), style: Brand.label(13, color: Brand.brandDeep)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _goHome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Brand.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Back to Home'),
                ),
              ),
              if (success)
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    key: const ValueKey('download-receipt'),
                    onPressed: _downloadReceipt,
                    icon: const Icon(Icons.download_rounded, size: 19),
                    label: Text(
                      DonationReceipt(c).isLivePayment ? 'Download receipt' : 'Download acknowledgement',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Brand.brandDeep,
                      side: const BorderSide(color: Brand.brand),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              if (success)
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    key: const ValueKey('donate-again'),
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const DonationOptionPage()),
                      (route) => false,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Brand.brandDeep,
                      side: const BorderSide(color: Brand.brand),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Make another donation'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Brand.isMobile(MediaQuery.of(context).size.width);

    return PopScope(
      // Leaving mid-checkout is fine -- the donation stays pending and can be
      // resumed from the donation page -- but a finished one goes home.
      canPop: _checkout.isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        backgroundColor: Brand.canvas,
        appBar: AppBar(
          backgroundColor: Brand.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          title: Text(
            _checkout.usesPaymongo ? 'GCash Checkout' : 'Donation Checkout',
            style: Brand.heading(17),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: mobile ? 24 : 36),
                child: ContentColumn(
                  maxWidth: 760,
                  child: Column(
                    children: [
                      const DonationSteps(current: 2),
                      const SizedBox(height: 22),
                      _buildSummary(),
                      const SizedBox(height: 18),
                      if (_error != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Brand.coralSoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(_error!, style: Brand.label(13.5, color: Brand.coral)),
                        ),
                        const SizedBox(height: 18),
                      ],
                      _checkout.isOpen ? _buildPayActions() : _buildResult(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
