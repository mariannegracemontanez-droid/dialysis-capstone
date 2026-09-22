/// One configured shift at a clinic (see clinic_shifts table). shiftCode
/// stays fixed to 'AM'/'PM' -- the same two values daily_schedules.shift
/// and the mobile app already use -- while label/times/capacity are fully
/// admin-configurable per clinic instead of hardcoded.
class ClinicShift {
  /// The only two shift codes the system runs on, in reading order.
  /// `clinic_shifts.shift_code` is constrained to exactly these values,
  /// so this is the full set a center can ever have -- which is what
  /// lets the Center Profile page offer an editor per code rather than
  /// per stored row.
  static const List<String> codes = ['AM', 'PM'];

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

  /// The row for [shiftCode] among [shifts], or null when that shift has
  /// never been created for the center.
  ///
  /// Null is an ordinary state, not an error: a center created by the
  /// Super Admin after center_scheduling_foundation.sql ran was never
  /// covered by that migration's one-time seed and starts with no rows
  /// at all, until the Center Admin configures them.
  static ClinicShift? byCode(List<ClinicShift> shifts, String shiftCode) {
    for (final shift in shifts) {
      if (shift.shiftCode == shiftCode) return shift;
    }
    return null;
  }
}
