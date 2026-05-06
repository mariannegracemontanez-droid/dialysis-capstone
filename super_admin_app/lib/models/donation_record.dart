class DonationRecord {
  final String id;
  final String donorName;
  final double amount;
  final String status;
  final String? proofUrl;
  final String? paymentMethod;
  final DateTime createdAt;

  DonationRecord({
    required this.id,
    required this.donorName,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.proofUrl,
    this.paymentMethod,
  });

  factory DonationRecord.fromJson(Map<String, dynamic> json) {
    return DonationRecord(
      id: json['id']?.toString() ?? '',
      donorName: json['name'] ?? 'Anonymous',
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      status: json['status'] ?? 'pending',
      proofUrl: json['proof_url'],
      paymentMethod: json['payment_method'],
      createdAt: DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now(),
    );
  }
}