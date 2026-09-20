/// One row in a single center's donation history -- either a whole
/// specific/random donation, or one center's share of an equal-distribution
/// donation. Used by the Superadmin "Center Donation History" section.
class CenterDonationHistoryEntry {
  final String donationId;
  final double amount;
  final String allocationType;
  final String status;
  final DateTime date;

  /// Donor identity, sourced from the existing donations.name / donations.email
  /// columns. Null when the donation is anonymous or predates contact capture.
  /// Search-only -- not shown as a column in the history table.
  final String? donorName;
  final String? donorEmail;

  CenterDonationHistoryEntry({
    required this.donationId,
    required this.amount,
    required this.allocationType,
    required this.status,
    required this.date,
    this.donorName,
    this.donorEmail,
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

  String get statusLabel {
    switch (status) {
      case 'verified':
        return 'Received';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }
}
