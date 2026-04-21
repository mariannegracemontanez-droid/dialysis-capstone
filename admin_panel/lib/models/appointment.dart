class Appointment {
  final String id;
  final String patientId;
  final String patientName;
  final DateTime date;
  final String time;
  final String status; // 'Scheduled', 'In Progress', 'Urgent'
  final String? description;

  Appointment({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.date,
    required this.time,
    required this.status,
    this.description,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: json['id'],
      patientId: json['patient_id'],
      patientName: json['patient_name'] ?? 'Unknown',
      date: DateTime.parse(json['date']),
      time: json['time'],
      status: json['status'],
      description: json['description'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'patient_name': patientName,
      'date': date.toIso8601String(),
      'time': time,
      'status': status,
      'description': description,
    };
  }
}