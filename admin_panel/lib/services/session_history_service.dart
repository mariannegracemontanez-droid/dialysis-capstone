import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dialysis_session.dart';
import 'supabase_config.dart';

/// Reads a patient's real dialysis session records.
///
/// There is no session-history table and this does not add one: a session
/// IS a `daily_schedules` row (see supabase/dialysis_session_duration.sql,
/// which moved before/after weight, before blood pressure and duration
/// onto that row precisely so a history view would be one query).
///
/// ## Scoping
///
/// Every read is filtered by BOTH the patient and the admin's own
/// `clinic_id`, resolved server-side from the signed-in profile and never
/// taken from the caller. RLS on daily_schedules already restricts a
/// center admin to their own clinic; the explicit filter means a bug in a
/// policy cannot turn into another center's data appearing in a downloaded
/// file. [getPatientForHistory] applies the same filter to the patient
/// record itself, so asking for a patient at another center returns
/// nothing rather than a header with a real name on it.
class SessionHistoryService {
  final SupabaseClient client = SupabaseConfig.client;

  /// The admin's own clinic. Null when the account has no clinic
  /// assigned, in which case every method below returns empty rather than
  /// falling back to an unscoped query.
  Future<String?> getCurrentClinicId() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    final profile = await client
        .from('profiles')
        .select('clinic_id')
        .eq('id', user.id)
        .maybeSingle();

    return profile?['clinic_id']?.toString();
  }

  /// The identifying details printed at the top of a downloaded history.
  ///
  /// Scoped to the admin's clinic, so this doubles as the authorization
  /// check for the whole feature: no row back, no history and no file.
  Future<Map<String, dynamic>?> getPatientForHistory(String patientId) async {
    final clinicId = await getCurrentClinicId();
    if (clinicId == null) return null;

    final row = await client
        .from('patients')
        .select(
          'id, full_name, email, phone, home_address, date_of_birth, '
          'blood_type, dialysis_stage, status, clinic_id, clinics(name)',
        )
        .eq('id', patientId)
        .eq('clinic_id', clinicId)
        .maybeSingle();

    return row;
  }

  /// Every session on record for one patient, newest first.
  ///
  /// [completedOnly] is the default view: a pending row is a session that
  /// has not happened yet, and a cancelled row is one that did not
  /// happen, so neither belongs in a history. The flag exists so the UI
  /// can offer "show cancelled too" without a second query shape.
  Future<List<DialysisSession>> getSessionHistory(
    String patientId, {
    bool completedOnly = true,
    int limit = 500,
  }) async {
    final clinicId = await getCurrentClinicId();
    if (clinicId == null) return const [];

    var query = client
        .from('daily_schedules')
        .select(
          'id, schedule_date, shift, status, start_time, end_time, '
          'completed_at, before_weight, before_systolic, before_diastolic, '
          'after_weight, duration_hours, duration_minutes',
        )
        .eq('patient_id', patientId)
        .eq('clinic_id', clinicId);

    if (completedOnly) {
      query = query.eq('status', 'completed');
    }

    final response = await query
        .order('schedule_date', ascending: false)
        .limit(limit);

    return (response as List)
        .map((row) => DialysisSession.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Headline figures for the history view, derived from the rows that
  /// are already loaded rather than from a second round of queries.
  ///
  /// Averages skip sessions where the value was never recorded, so a
  /// half-filled record lowers the sample size instead of dragging the
  /// average towards zero.
  static SessionHistorySummary summarize(List<DialysisSession> sessions) {
    final completed = sessions.where((s) => s.isCompleted).toList();

    final durations = completed
        .map((s) => s.durationInMinutes)
        .whereType<int>()
        .toList();

    final changes = completed
        .map((s) => s.weightChange)
        .whereType<double>()
        .toList();

    return SessionHistorySummary(
      totalSessions: completed.length,
      firstSession: completed.isEmpty ? null : completed.last.date,
      lastSession: completed.isEmpty ? null : completed.first.date,
      averageDurationMinutes: durations.isEmpty
          ? null
          : durations.reduce((a, b) => a + b) / durations.length,
      averageWeightChange: changes.isEmpty
          ? null
          : changes.reduce((a, b) => a + b) / changes.length,
      recordedDurations: durations.length,
      recordedWeightChanges: changes.length,
    );
  }
}

/// Aggregates over one patient's completed sessions.
class SessionHistorySummary {
  final int totalSessions;
  final DateTime? firstSession;
  final DateTime? lastSession;

  /// Null when no session has a duration recorded.
  final double? averageDurationMinutes;

  /// Negative means fluid was removed, which is the normal direction.
  final double? averageWeightChange;

  /// How many sessions each average is actually based on, so the UI can
  /// say "across 8 of 12 sessions" instead of implying full coverage.
  final int recordedDurations;
  final int recordedWeightChanges;

  const SessionHistorySummary({
    required this.totalSessions,
    required this.firstSession,
    required this.lastSession,
    required this.averageDurationMinutes,
    required this.averageWeightChange,
    required this.recordedDurations,
    required this.recordedWeightChanges,
  });

  String get averageDurationLabel {
    final minutes = averageDurationMinutes;
    if (minutes == null) return '--';

    final total = minutes.round();
    final hours = total ~/ 60;
    final remainder = total % 60;

    if (hours == 0) return '${remainder}m';
    return '${hours}h ${remainder}m';
  }

  String get averageWeightChangeLabel {
    final change = averageWeightChange;
    if (change == null) return '--';
    return '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)} kg';
  }
}
