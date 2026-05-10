class Clinic {
  final String id;
  final String name;
  final String location;
  final int machines;
  final int availableSlots;
  final String openingHours;

  Clinic({
    required this.id,
    required this.name,
    required this.location,
    required this.machines,
    required this.availableSlots,
    required this.openingHours,
  });

  factory Clinic.fromJson(Map<String, dynamic> json) {
    return Clinic(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? json['clinic_name'] ?? 'Unknown Clinic',
      location: json['location'] ?? json['address'] ?? 'Unknown Location',
      machines: int.tryParse(json['machines']?.toString() ?? '') ?? 0,
      availableSlots: int.tryParse(json['avail_slots']?.toString() ?? '') ?? 0,
      openingHours: json['open_hours'] ?? json['hours'] ?? '7 AM - 5 PM',
    );
  }

  String? get status => null;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'location': location,
      'machines': machines,
      'avail_slots': availableSlots,
      'open_hours': openingHours,
    };
  }
}
