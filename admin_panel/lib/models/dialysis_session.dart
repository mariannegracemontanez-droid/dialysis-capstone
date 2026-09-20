/// One real dialysis session, as already stored.
///
/// This is a read model over a single `daily_schedules` row -- it is NOT a
/// new table and NOT the patient's recurring weekly schedule.
///
///   weekly_schedules / patient_schedule_days -> "Mondays and Thursdays,
///     AM shift", a repeating intention with no dates on it.
///   daily_schedules -> one row per patient per calendar date, carrying
///     what actually happened: the shift, the status, and (since
///     supabase/dialysis_session_duration.sql) the before/after weight,
///     the before-dialysis blood pressure and the session duration.
///
/// Session history is the second of those, filtered to the sessions that
/// were actually carried out.
class DialysisSession {
  final String id;
  final DateTime date;

  /// 'AM' or 'PM' -- the same two values daily_schedules.shift holds.
  final String shift;

  /// 'completed', 'pending' or 'cancelled'.
  final String status;

  /// Scheduled window for the shift, as recorded on the session row.
  final String? startTime;
  final String? endTime;

  final DateTime? completedAt;

  // Before dialysis.
  final double? beforeWeight;
  final int? beforeSystolic;
  final int? beforeDiastolic;

  // After dialysis.
  final double? afterWeight;
  final int? durationHours;
  final int? durationMinutes;

  const DialysisSession({
    required this.id,
    required this.date,
    required this.shift,
    required this.status,
    this.startTime,
    this.endTime,
    this.completedAt,
    this.beforeWeight,
    this.beforeSystolic,
    this.beforeDiastolic,
    this.afterWeight,
    this.durationHours,
    this.durationMinutes,
  });

  factory DialysisSession.fromJson(Map<String, dynamic> json) {
    double? toDouble(Object? value) =>
        value == null ? null : double.tryParse(value.toString());
    int? toInt(Object? value) =>
        value == null ? null : int.tryParse(value.toString());

    return DialysisSession(
      id: json['id'].toString(),
      date:
          DateTime.tryParse(json['schedule_date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      shift: json['shift']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      startTime: json['start_time']?.toString(),
      endTime: json['end_time']?.toString(),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.tryParse(json['completed_at'].toString()),
      beforeWeight: toDouble(json['before_weight']),
      beforeSystolic: toInt(json['before_systolic']),
      beforeDiastolic: toInt(json['before_diastolic']),
      afterWeight: toDouble(json['after_weight']),
      durationHours: toInt(json['duration_hours']),
      durationMinutes: toInt(json['duration_minutes']),
    );
  }

  bool get isCompleted => status == 'completed';

  /// True once anything was recorded before the machine was started.
  bool get hasBeforeData =>
      beforeWeight != null || beforeSystolic != null || beforeDiastolic != null;

  /// True once the after-dialysis form was saved.
  bool get hasAfterData =>
      afterWeight != null || durationHours != null || durationMinutes != null;

  /// Fluid removed across the session. Null unless BOTH weights are
  /// recorded -- a difference against a missing reading is not a number,
  /// and showing one would invent data.
  double? get weightChange {
    final before = beforeWeight;
    final after = afterWeight;
    if (before == null || after == null) return null;
    return after - before;
  }

  /// `120/80`, or null when the pair is incomplete.
  String? get bloodPressure {
    final systolic = beforeSystolic;
    final diastolic = beforeDiastolic;
    if (systolic == null || diastolic == null) return null;
    return '$systolic/$diastolic';
  }

  /// `3h 30m`. Null when neither part was recorded; a recorded zero is a
  /// real value and is kept.
  String? get duration {
    final hours = durationHours;
    final minutes = durationMinutes;
    if (hours == null && minutes == null) return null;

    final parts = <String>[
      if (hours != null && hours > 0) '${hours}h',
      if (minutes != null && minutes > 0) '${minutes}m',
    ];

    if (parts.isEmpty) return '0m';
    return parts.join(' ');
  }

  /// Total minutes, for averaging across a history. Null when nothing was
  /// recorded.
  int? get durationInMinutes {
    if (durationHours == null && durationMinutes == null) return null;
    return (durationHours ?? 0) * 60 + (durationMinutes ?? 0);
  }
}
