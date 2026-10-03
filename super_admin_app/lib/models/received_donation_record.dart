/// Where a received amount came from -- the three sources the Admin
/// Dashboard's "Donation Funds" total adds together.
enum ReceivedDonationSource {
  /// A verified specific/random donation sent straight to the center.
  direct,

  /// The center's share of a verified equal-distribution donation.
  equalShare,

  /// A Super Admin manual fund_distributions entry.
  manualDistribution,
}

/// One amount a center has actually received, as counted by the Admin
/// Dashboard. Used by the Super Admin donation history export.
class ReceivedDonationRecord {
  /// donations.id for donor records, fund_distributions.id for manual ones.
  /// Kept for search matching only; it is not exported.
  final String sourceId;
  final ReceivedDonationSource source;
  final DateTime date;
  final double amount;
  final String centerName;

  /// donations.allocation_type for [ReceivedDonationSource.direct].
  final String? allocationType;

  /// Null for anonymous donations and for manual distributions.
  final String? donorName;
  final String? donorEmail;
  final bool isAnonymous;

  const ReceivedDonationRecord({
    required this.sourceId,
    required this.source,
    required this.date,
    required this.amount,
    required this.centerName,
    this.allocationType,
    this.donorName,
    this.donorEmail,
    this.isAnonymous = false,
  });

  bool get isManualDistribution =>
      source == ReceivedDonationSource.manualDistribution;

  /// Same wording as the Super Admin history tables, plus the manual ledger.
  String get allocationLabel {
    switch (source) {
      case ReceivedDonationSource.equalShare:
        return 'Equal Share';
      case ReceivedDonationSource.manualDistribution:
        return 'Manual Distribution';
      case ReceivedDonationSource.direct:
        switch (allocationType) {
          case 'specific_center':
            return 'Specific Center';
          case 'random_center':
            return 'Random';
          default:
            return 'Not recorded';
        }
    }
  }

  /// What the export shows in the Donor column, following the existing
  /// privacy rule: anonymous donations never expose a name or email.
  String get donorLabel {
    if (isManualDistribution) return 'Super Admin distribution';
    final name = donorName;
    if (isAnonymous || name == null || name.trim().isEmpty) return 'Anonymous';
    return name;
  }
}
