class FundDistribution {
  final String id;
  final String centerName;
  final double amount;
  final String remarks;
  final String status;
  final DateTime createdAt;

  /// When the funds were pushed to the center. Null on ledger rows written
  /// before the Super Admin insert set this column.
  final DateTime? distributionDate;

  FundDistribution({
    required this.id,
    required this.centerName,
    required this.amount,
    required this.remarks,
    required this.status,
    required this.createdAt,
    this.distributionDate,
  });

  /// The date the center received these funds -- distribution_date when
  /// set, created_at for older rows. Same fallback the Admin Dashboard's
  /// "Latest Donation" uses (admin_panel DashboardService.getLatestDonation).
  DateTime get receivedAt => distributionDate ?? createdAt;

  factory FundDistribution.fromJson(Map<String, dynamic> json) {
    return FundDistribution(
      id: json['id']?.toString() ?? '',
      centerName: json['center_name']?.toString() ?? 'Unknown Center',
      amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0.0,
      remarks: json['remarks']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Distributed',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      distributionDate:
          DateTime.tryParse(json['distribution_date']?.toString() ?? ''),
    );
  }
}
