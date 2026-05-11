import 'package:supabase_flutter/supabase_flutter.dart';

class HealthMonitoringService {
  final SupabaseClient supabase = Supabase.instance.client;

  // =========================
  // BLOOD PRESSURE
  // =========================

  Future<List<dynamic>> getBloodPressureLogs({
    required String patientId,
  }) async {
    final response = await supabase
        .from('blood_pressure_logs')
        .select()
        .eq('patient_id', patientId)
        .order('session_date', ascending: true);

    return response;
  }

  Future<Map<String, dynamic>?> getLatestBloodPressure({
  required String patientId,
}) async {
  final response = await supabase
      .from('blood_pressure_logs')
      .select()
      .eq('patient_id', patientId)
      .order('session_date', ascending: false)
      .limit(1)
      .maybeSingle();

  return response;
}

  Future<void> addBloodPressureLog({
    required String patientId,
    required String clinicId,
    required String sessionDate,
    required int systolic,
    required int diastolic,
    String? notes,
  }) async {
    await supabase.from('blood_pressure_logs').insert({
      'patient_id': patientId,
      'clinic_id': clinicId,
      'session_date': sessionDate,
      'systolic': systolic,
      'diastolic': diastolic,
      'notes': notes,
    });
  }

  Future<void> deleteBloodPressureLog(String logId) async {
    await supabase
        .from('blood_pressure_logs')
        .delete()
        .eq('id', logId);
  }

  // =========================
  // WEIGHT MONITORING
  // =========================

  Future<List<dynamic>> getWeightLogs({
    required String patientId,
  }) async {
    final response = await supabase
        .from('weight_logs')
        .select()
        .eq('patient_id', patientId)
        .order('session_date', ascending: true);

    return response;
  }

  Future<Map<String, dynamic>?> getLatestWeight({
  required String patientId,
}) async {
  final response = await supabase
      .from('weight_logs')
      .select()
      .eq('patient_id', patientId)
      .order('session_date', ascending: false)
      .limit(1)
      .maybeSingle();

  return response;
}

  Future<void> addWeightLog({
    required String patientId,
    required String clinicId,
    required String sessionDate,
    required double beforeWeight,
    required double afterWeight,
    String? notes,
  }) async {
    await supabase.from('weight_logs').insert({
      'patient_id': patientId,
      'clinic_id': clinicId,
      'session_date': sessionDate,
      'before_weight': beforeWeight,
      'after_weight': afterWeight,
      'notes': notes,
    });
  }

  Future<void> deleteWeightLog(String logId) async {
    await supabase
        .from('weight_logs')
        .delete()
        .eq('id', logId);
  }

  // =========================
  // ANALYSIS HELPERS
  // =========================

  String analyzeBloodPressure({
    required int systolic,
    required int diastolic,
  }) {
    if (systolic < 120 && diastolic < 80) {
      return 'Blood pressure is within normal monitoring range.';
    }

    if (systolic < 130 && diastolic < 80) {
      return 'Blood pressure is slightly elevated.';
    }

    if (systolic < 140 || diastolic < 90) {
      return 'Blood pressure requires continued monitoring.';
    }

    return 'Blood pressure is higher than previous monitoring ranges.';
  }

  String analyzeWeightDifference({
    required double beforeWeight,
    required double afterWeight,
  }) {
    final difference = beforeWeight - afterWeight;

    if (difference <= 0) {
      return 'Weight difference appears unusual. Please verify entries.';
    }

    if (difference <= 1.5) {
      return 'Weight difference is within light fluid removal range.';
    }

    if (difference <= 3.0) {
      return 'Weight difference is within expected dialysis range.';
    }

    return 'Higher than usual weight difference detected.';
  }
}