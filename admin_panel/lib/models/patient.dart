class Patient {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? homeAddress;
  final String? role;
  final DateTime? birthDate;
  final String? timeSlot;
  final String? bloodType;
  final String? emergencyContactName;
  final String? emergencyContactNumber;
  final String? address;
  final String? status; // pending, accepted, declined, no_sched
  final DateTime? createdAt;
  final String? clinicId;

  Patient({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.homeAddress,
    this.role,
    this.birthDate,
    this.timeSlot,
    this.bloodType,
    this.emergencyContactName,
    this.emergencyContactNumber,
    this.address,
    this.status,
    this.createdAt,
    this.clinicId,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] ?? json['profile'];
    final birthDateValue = json['date_of_birth'] ?? profile?['date_of_birth'];

    return Patient(
      id: json['id']?.toString() ?? '',
      name: json['full_name'] ?? profile?['full_name'] ?? 'Unknown',
      email: json['email'] ?? profile?['email'] ?? '',
      phone: json['phone'] ?? profile?['phone'],
      homeAddress: json['home_address'] ?? profile?['homeAddress'],
      role: json['role']?.toString() ?? profile?['role']?.toString(),
      birthDate: birthDateValue != null ? DateTime.tryParse(birthDateValue.toString()) : null,
      timeSlot: json['time_slot'] ?? profile?['time_slot'],
      bloodType: json['blood_type'] ?? profile?['blood_type'],
      emergencyContactName: json['emergency_contact_name'] ?? profile?['emergency_contact__name'],
      emergencyContactNumber: json['emergency_contact_number'] ?? profile?['emergency_contact__contact'],      status: json['status'] ?? profile?['status'] ?? 'pending',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      clinicId: json['clinic_id']?.toString() ?? profile?['clinic_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': name,
      'email': email,
      'phone': phone,
      'home_address': homeAddress,
      'role': role,
      'date_of_birth': birthDate?.toIso8601String(),
      'time_slot': timeSlot,
      'blood_type': bloodType,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_number': emergencyContactNumber,
      'status': status,
      'created_at': createdAt?.toIso8601String(),
      'clinic_id': clinicId,
    };
  }

  String operator [](String other) {
    switch (other) {
      case 'id':
        return id;
      case 'name':
        return name;
      case 'email':
        return email;
      case 'phone':
        return phone ?? '';
      case 'homeAddress':
        return homeAddress ?? '';
      case 'role':
        return role ?? '';
      case 'birthDate':
        return birthDate?.toIso8601String() ?? '';
      case 'timeSlot':
        return timeSlot ?? '';
      case 'bloodType':
        return bloodType ?? '';
      case 'emergencyContactName':
        return emergencyContactName ?? '';
      case 'emergencyContactNumber':
        return emergencyContactNumber ?? '';
      case 'status':
        return status ?? '';
      case 'createdAt':
        return createdAt?.toIso8601String() ?? '';
      case 'clinicId':
        return clinicId ?? '';
      default:
        throw ArgumentError('Property not found: $other');
    }
  }
}
