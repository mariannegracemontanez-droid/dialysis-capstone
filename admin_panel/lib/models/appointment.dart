class Appointment {
  final String id;
  final String patientId;
  final String patientName;
  final DateTime date;
  final String time;
  final String status; // 'Scheduled', 'In Progress', 'Urgent'
  final String? description;
  final String? clinicId;
  final String? clinicName;
  final String? clinicLocation;

  Appointment({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.date,
    required this.time,
    required this.status,
    this.description,
    this.clinicId,
    this.clinicName,
    this.clinicLocation,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    final dateString = json['appointment_date'] ?? json['date'] ?? json['appointmentDate'];
    return Appointment(
      id: json['id']?.toString() ?? '',
      patientId: json['patient_id']?.toString() ?? '',
      patientName: json['patient_name'] ?? 'Unknown',
      date: DateTime.tryParse(dateString?.toString() ?? '') ?? DateTime.now(),
      time: json['time'] ?? json['appointment_time'] ?? '',
      status: json['status'] ?? 'Scheduled',
      description: json['description'],
      clinicId: json['clinic_id']?.toString(),
      clinicName: json['clinic_name']?.toString(),
      clinicLocation: json['clinic_location']?.toString() ?? json['location']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'patient_name': patientName,
      'appointment_date': date.toIso8601String(),
      'time': time,
      'status': status,
      'description': description,
      'clinic_id': clinicId,
      'clinic_name': clinicName,
      'clinic_location': clinicLocation,
    };
  }
}