class Patient {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? userLocation;
  final String? role;
  final DateTime? birthDate;
  final String? timeSlot;

  Patient({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.userLocation,
    this.role,
    this.birthDate,
    this.timeSlot,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id']?.toString() ?? '',
      name: json['full_name'] ?? json['name'] ?? 'Unknown',
      email: json['email'] ?? '',
      phone: json['phone'],
      userLocation: json['user_location'] ?? json['address'],
      role: json['role']?.toString(),
      birthDate: json['birth_date'] != null
          ? DateTime.tryParse(json['birth_date'])
          : null,
      timeSlot: json['time_slot'] ?? json['schedule_time'],
    );
  }

  Null get scheduleTime => null;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': name,
      'email': email,
      'phone': phone,
      'user_location': userLocation,
      'role': role,
      'birth_date': birthDate?.toIso8601String(),
      'time_slot': timeSlot,
    };
  }
}