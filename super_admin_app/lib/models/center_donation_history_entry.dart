/// One row in a single center's donation history -- either a whole
/// specific/random donation, or one center's share of an equal-distribution
/// donation. Used by the Superadmin "Center Donation History" section.
class CenterDonationHistoryEntry {
  final String donationId;
  final double amount;
  final String allocationType;
  final String status;
  final DateTime date;

  CenterDonationHistoryEntry({
    required this.donationId,
    required this.amount,
    required this.allocationType,
    required this.status,
    required this.date,
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
