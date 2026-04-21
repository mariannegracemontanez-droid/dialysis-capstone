class Patient {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final DateTime? dateOfBirth;

  Patient({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.dateOfBirth,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      phone: json['phone'],
      dateOfBirth: json['date_of_birth'] != null ? DateTime.parse(json['date_of_birth']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'date_of_birth': dateOfBirth?.toIso8601String(),
    };
  }
}