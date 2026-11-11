import 'package:flutter/material.dart';

import '../pages/checkout_page.dart' show donationModeLabel;
import '../services/donation_checkout_service.dart';
import '../theme/brand.dart';

/// What the donor chose for an unfinished donation.
enum UnfinishedDonationChoice { continueDonation, startOver }

/// Asks whether to continue an unfinished donation or start over. Every
/// figure shown (reference, amount, option, recipients and their amounts)
/// is the donation as the SERVER recorded it.
///
/// Returns null when dismissed (the unfinished donation is left as is).
/// "Start over" is only returned after [confirmStartOver] said yes.
Future<UnfinishedDonationChoice?> showUnfinishedDonationDialog(
  BuildContext context,
  DonationCheckout checkout,
) async {
  while (true) {
    final choice = await showDialog<UnfinishedDonationChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.history_rounded, color: Brand.brandDeep),
            const SizedBox(width: 10),
            Expanded(child: Text('Continue your donation?', style: Brand.heading(19))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have an unfinished donation. You can continue it exactly as '
                'it was, or start over.',
                style: Brand.body(14),
              ),
              const SizedBox(height: 14),
              UnfinishedDonationSummary(checkout: checkout),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            key: const ValueKey('unfinished-start-over'),
            onPressed: () => Navigator.of(dialogContext).pop(UnfinishedDonationChoice.startOver),
            child: const Text('Start over'),
          ),
          ElevatedButton(
            key: const ValueKey('unfinished-continue'),
            onPressed: () => Navigator.of(dialogContext).pop(UnfinishedDonationChoice.continueDonation),
            style: ElevatedButton.styleFrom(
              backgroundColor: Brand.brand,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Continue donation'),
          ),
        ],
      ),
    );

    if (choice != UnfinishedDonationChoice.startOver) return choice;
    if (!context.mounted) return null;
    if (await confirmStartOver(context, checkout)) return UnfinishedDonationChoice.startOver;
    if (!context.mounted) return null;
    // "Keep it" goes back to the first question.
  }
}

/// Second, explicit confirmation before an unfinished donation is discarded.
Future<bool> confirmStartOver(BuildContext context, DonationCheckout checkout) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Start over?', style: Brand.heading(19)),
      content: Text(
        'This cancels your unfinished donation ${checkout.reference} for '
        '${formatCentavos(checkout.amountCentavos)}. Nothing has been charged. '
        'You can then start a new donation.',
        style: Brand.body(14),
      ),
      actions: [
        TextButton(
          key: const ValueKey('start-over-keep'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep it'),
        ),
        ElevatedButton(
          key: const ValueKey('start-over-confirm'),
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
  return confirmed == true;
}

/// Compact server-side summary of an unfinished donation.
class UnfinishedDonationSummary extends StatelessWidget {
  const UnfinishedDonationSummary({super.key, required this.checkout});

  final DonationCheckout checkout;

  @override
  Widget build(BuildContext context) {
    final c = checkout;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, child: Text(label, style: Brand.body(13, color: Brand.textMuted))),
              Expanded(child: Text(value, style: Brand.label(13.5, color: Brand.textStrong))),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.tealSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Reference', c.reference),
          row('Amount', formatCentavos(c.amountCentavos)),
          row('Option', donationModeLabel(c.mode)),
          const SizedBox(height: 6),
          for (final a in c.allocations)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  const Icon(Icons.local_hospital_rounded, size: 15, color: Brand.brand),
                  const SizedBox(width: 6),
                  Expanded(child: Text(a.clinicName, style: Brand.body(13, color: Brand.textStrong))),
                  Text(formatCentavos(a.amountCentavos), style: Brand.label(13, color: Brand.brandDeep)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
