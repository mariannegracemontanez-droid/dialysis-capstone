class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String? location;
  final String? medicalId;
  final String? bloodType;
  final double? weight;
  final double? height;
  final DateTime? lastDialysisDate;
  final String role;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    this.phone,
    this.location,
    this.medicalId,
    this.bloodType,
    this.weight,
    this.height,
    this.lastDialysisDate,
    required this.role,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      email: json['email'],
      fullName: json['full_name'],
      phone: json['phone'],
      location: json['user_location'] ?? json['location'],
      medicalId: json['medical_id'],
      bloodType: json['blood_type'],
      weight: json['weight'] != null
          ? double.parse(json['weight'].toString())
          : null,
      height: json['height'] != null
          ? double.parse(json['height'].toString())
          : null,
      lastDialysisDate: json['last_dialysis_date'] != null
          ? DateTime.parse(json['last_dialysis_date'])
          : null,
      role: json['role'] ?? 'patient',
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'email': email,
    'full_name': fullName,
    'phone': phone,
    'user_location': location,
    'medical_id': medicalId,
    'blood_type': bloodType,
    'weight': weight,
    'height': height,
    'last_dialysis_date': lastDialysisDate?.toIso8601String(),
    'role': role,
  };
}
