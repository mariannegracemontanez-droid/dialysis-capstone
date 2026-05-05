class FundDistribution {
  final String id;
  final String centerName;
  final double amount;
  final String remarks;
  final String status;
  final DateTime createdAt;

  FundDistribution({
    required this.id,
    required this.centerName,
    required this.amount,
    required this.remarks,
    required this.status,
    required this.createdAt,
  });

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
    );
  }
}
