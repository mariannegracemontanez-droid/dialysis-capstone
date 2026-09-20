/// One configured shift at a clinic (see clinic_shifts table). shiftCode
/// stays fixed to 'AM'/'PM' -- the same two values daily_schedules.shift
/// and the mobile app already use -- while label/times/capacity are fully
/// admin-configurable per clinic instead of hardcoded.
class ClinicShift {
  final String id;
  final String clinicId;
  final String shiftCode;
  final String shiftLabel;
  final String startTime;
  final String endTime;
  final int capacity;
  final bool isActive;

  const ClinicShift({
    required this.id,
    required this.clinicId,
    required this.shiftCode,
    required this.shiftLabel,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.isActive,
  });

  factory ClinicShift.fromJson(Map<String, dynamic> json) {
    return ClinicShift(
      id: json['id'].toString(),
      clinicId: json['clinic_id'].toString(),
      shiftCode: json['shift_code'].toString(),
      shiftLabel: (json['shift_label'] ?? '').toString(),
      startTime: (json['start_time'] ?? '').toString(),
      endTime: (json['end_time'] ?? '').toString(),
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  /// Falls back to the shift code ('AM'/'PM') when no label has been set.
  String get displayLabel => shiftLabel.trim().isEmpty ? shiftCode : shiftLabel;
}
