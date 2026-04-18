class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName:
          json['full_name'] as String? ??
          json['fullName'] as String? ??
          'Super Admin',
      role: json['role'] as String? ?? 'superadmin',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
