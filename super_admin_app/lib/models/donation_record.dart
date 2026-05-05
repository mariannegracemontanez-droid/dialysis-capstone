class DonationRecord {
  final String id;
  final String donorName;
  final String centerName;
  final double amount;
  final String status;
  final DateTime createdAt;

  DonationRecord({
    required this.id,
    required this.donorName,
    required this.centerName,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  factory DonationRecord.fromJson(Map<String, dynamic> json) {
    return DonationRecord(
      id: json['id']?.toString() ?? '',
      donorName: json['donor_name']?.toString() ?? 'Anonymous',
      centerName: json['center_name']?.toString() ?? json['clinic_name']?.toString() ?? 'Unknown Center',
      amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0.0,
      status: json['status']?.toString() ?? 'Pending',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
