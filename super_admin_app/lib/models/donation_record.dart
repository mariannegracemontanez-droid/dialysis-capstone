class DonationRecord {
  final String id;
  final String donorName;
  final double amount;
  final String status;
  final String? proofUrl;
  final String? paymentMethod;
  final DateTime createdAt;

  /// One of 'specific_center', 'random_center', 'equal_distribution', or
  /// null for donations recorded before this was tracked.
  final String? allocationType;

  /// The resolved center for a specific/random donation. Null for equal
  /// distribution (see [DonationAllocation] for the per-center breakdown)
  /// and for donations made before allocation tracking existed.
  final String? clinicId;
  final String? clinicName;

  /// True when the donor chose to donate without exposing their identity.
  final bool isAnonymous;

  DonationRecord({
    required this.id,
    required this.donorName,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.proofUrl,
    this.paymentMethod,
    this.allocationType,
    this.clinicId,
    this.clinicName,
    this.isAnonymous = false,
  });

  String get allocationLabel {
    switch (allocationType) {
      case 'specific_center':
        return 'Specific Dialysis Center';
      case 'random_center':
        return 'Randomly Assigned Center';
      case 'equal_distribution':
        return 'Equal Distribution';
      default:
        return 'Not recorded';
    }
  }

  factory DonationRecord.fromJson(Map<String, dynamic> json) {
    final donorId = json['donor_id'];
    final name = json['name'] as String?;
    final email = json['email'] as String?;

    // A donation is anonymous when it carries no donor account and no
    // contact details -- matches how donation_page.dart writes anonymous
    // donations (donor_id/name/email all left null).
    final anonymous = donorId == null &&
        (name == null || name.trim().isEmpty) &&
        (email == null || email.trim().isEmpty);

    final clinic = json['clinics'];
    final clinicName = clinic is Map ? clinic['name']?.toString() : null;

    return DonationRecord(
      id: json['id']?.toString() ?? '',
      donorName: anonymous ? 'Anonymous Donor' : (name ?? 'Anonymous'),
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      status: json['status'] ?? 'pending',
      proofUrl: json['proof_url'],
      paymentMethod: json['payment_method'],
      createdAt: DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now(),
      allocationType: json['allocation_type']?.toString(),
      clinicId: json['clinic_id']?.toString(),
      clinicName: clinicName,
      isAnonymous: anonymous,
    );
  }
}

/// One center's share of an equal-distribution donation.
class DonationAllocation {
  final String id;
  final String donationId;
  final String clinicId;
  final String clinicName;
  final double amount;

  DonationAllocation({
    required this.id,
    required this.donationId,
    required this.clinicId,
    required this.clinicName,
    required this.amount,
  });

  factory DonationAllocation.fromJson(Map<String, dynamic> json) {
    final clinic = json['clinics'];
    return DonationAllocation(
      id: json['id']?.toString() ?? '',
      donationId: json['donation_id']?.toString() ?? '',
      clinicId: json['clinic_id']?.toString() ?? '',
      clinicName: clinic is Map
          ? (clinic['name']?.toString() ?? 'Unnamed Center')
          : 'Unnamed Center',
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
    );
  }
}
