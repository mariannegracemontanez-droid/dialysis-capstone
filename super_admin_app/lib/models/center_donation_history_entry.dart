import 'donation_history_status.dart';

/// One row in a single center's donation history -- either a whole
/// specific/random donation, or one center's share of an equal-distribution
/// donation. Used by the Overall Donation History when one center is selected.
class CenterDonationHistoryEntry {
  final String donationId;
  final double amount;
  final String allocationType;
  final String status;
  final DateTime date;

  /// Donor identity, sourced from the existing donations.name / donations.email
  /// columns. Null when the donation is anonymous or predates contact capture.
  final String? donorName;
  final String? donorEmail;

  /// Checkout reference, outcome and environment of the donation (or of the
  /// parent donation, for a share). All null for older donations.
  final String? reference;
  final String? paymentStatus;
  final String? paymentEnvironment;

  CenterDonationHistoryEntry({
    required this.donationId,
    required this.amount,
    required this.allocationType,
    required this.status,
    required this.date,
    this.donorName,
    this.donorEmail,
    this.reference,
    this.paymentStatus,
    this.paymentEnvironment,
  });

  String get allocationLabel {
    switch (allocationType) {
      case 'specific_center':
        return 'Specific Center';
      case 'random_center':
        return 'Random';
      case 'equal_distribution':
        return 'Equal Share';
      default:
        return 'Not recorded';
    }
  }

  /// Same labels as the Donation Transactions section for checkouts; the
  /// original Received / Rejected / Pending for older donations.
  String get statusLabel => donationHistoryStatusLabel(
        status: status,
        paymentStatus: paymentStatus,
        paymentEnvironment: paymentEnvironment,
      );

  /// Money actually received (never a simulated payment).
  bool get isReceived =>
      countsAsReceived(status: status, paymentEnvironment: paymentEnvironment);
}

/// Builds one center's history from the two `donations` /
/// `donation_allocations` reads, newest first.
///
///  * [directRows]: donations whose `clinic_id` is this center (specific and
///    random, older and checkout alike) -- one row each, full amount.
///  * [shareRows]: this center's `donation_allocations` rows with the parent
///    donation embedded as `donations`. Only shares of a split donation
///    (parent `clinic_id` null) are listed: a specific/random checkout also
///    has one allocation row, but it is already the direct row, so listing
///    it again would count it twice.
///
/// Checkout (sandbox) donations are included, with their reference and
/// payment status; whether a row is money is decided by [isReceived] only.
List<CenterDonationHistoryEntry> centerHistoryFromRows(
  Iterable<dynamic> directRows,
  Iterable<dynamic> shareRows,
) {
  DateTime date(Object? v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
  double amount(Object? v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  final entries = <CenterDonationHistoryEntry>[
    for (final item in directRows)
      CenterDonationHistoryEntry(
        donationId: item['id'].toString(),
        amount: amount(item['amount']),
        allocationType: item['allocation_type']?.toString() ?? 'specific_center',
        status: item['status']?.toString() ?? 'pending',
        date: date(item['created_at']),
        donorName: item['name']?.toString(),
        donorEmail: item['email']?.toString(),
        reference: item['reference_code']?.toString(),
        paymentStatus: item['payment_status']?.toString(),
        paymentEnvironment: item['payment_environment']?.toString(),
      ),
    for (final item in shareRows)
      if (item['donations'] is! Map || item['donations']['clinic_id'] == null)
        CenterDonationHistoryEntry(
          donationId: item['donation_id'].toString(),
          amount: amount(item['amount']),
          allocationType: 'equal_distribution',
          status: (item['donations'] is Map ? item['donations']['status']?.toString() : null) ?? 'pending',
          date: date(item['created_at']),
          donorName: item['donations'] is Map ? item['donations']['name']?.toString() : null,
          donorEmail: item['donations'] is Map ? item['donations']['email']?.toString() : null,
          reference: item['donations'] is Map ? item['donations']['reference_code']?.toString() : null,
          paymentStatus: item['donations'] is Map ? item['donations']['payment_status']?.toString() : null,
          paymentEnvironment: item['donations'] is Map ? item['donations']['payment_environment']?.toString() : null,
        ),
  ];

  entries.sort((a, b) => b.date.compareTo(a.date));
  return entries;
}
