class CenterModel {
  final String id;
  final String name;
  final String address;
  final String city;
  final List<String> requirements; // ✅ FIXED
  final double? latitude;
  final double? longitude;
  final int machines;
  final int totalPatients;
  final int availableSlots;
  final String status;
  final String operatingHours;
  final int shifts;
  final String contactNumber;
  final DateTime createdAt;

  CenterModel({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.requirements,
    required this.latitude,
    required this.longitude,
    required this.machines,
    required this.totalPatients,
    required this.availableSlots,
    required this.status,
    required this.operatingHours,
    required this.shifts,
    required this.contactNumber,
    required this.createdAt,
  });

  bool get isOpen => status.toLowerCase() == 'open';
  String get statusText => isOpen ? 'Open' : 'Closed';

  factory CenterModel.fromJson(Map<String, dynamic> json) {
    final statusValue = json['open_status'] ?? json['status'] ?? 'open';
    final openTime = json['open_time']?.toString() ?? '';
    final closeTime = json['close_time']?.toString() ?? '';
    final hours = json['operating_hours']?.toString() ??
        (openTime.isNotEmpty && closeTime.isNotEmpty
            ? '$openTime - $closeTime'
            : '7:00 AM - 5:00 PM');

    return CenterModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Center',
      address: json['address']?.toString() ?? 'Unspecified address',
      city: json['city']?.toString() ?? '',
      requirements: (json['requirements'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [], // ✅ FIXED
      latitude: json['latitude'] != null
          ? double.tryParse(json['latitude'].toString())
          : null,
      longitude: json['longitude'] != null
          ? double.tryParse(json['longitude'].toString())
          : null,
      machines: int.tryParse(json['machine']?.toString() ?? '') ?? 0,
      totalPatients:
          int.tryParse(json['total_patients']?.toString() ?? '') ?? 0,
      availableSlots:
          int.tryParse(json['slots_available']?.toString() ?? '') ?? 0,
      status: statusValue.toString(),
      operatingHours: hours,
      shifts: int.tryParse(json['shifts']?.toString() ?? '') ?? 2,
      contactNumber: json['contact_number']?.toString() ?? 'N/A',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ??
              DateTime.now()
          : DateTime.now(),
    );
  }
}