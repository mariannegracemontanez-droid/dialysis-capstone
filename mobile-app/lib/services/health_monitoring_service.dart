import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class HealthMonitoringService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<String?> getCurrentPatientId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No logged in user found.');
    }

    final patient = await _supabase
        .from('patients')
        .select('id')
        .eq('profile_id', user.id)
        .maybeSingle();

    return patient == null ? null : patient['id'] as String?;
  }

  Future<int> getTodayWaterTotal() async {
    final patientId = await getCurrentPatientId();
    if (patientId == null) {
      return 0;
    }

    final today = DateTime.now().toUtc().toIso8601String().split('T').first;
    final data = await _supabase
        .from('water_intake_logs')
        .select('amount_ml')
        .eq('patient_id', patientId)
        .eq('log_date', today);

    return (data as List<dynamic>).fold<int>(0, (sum, item) {
      final amount = item['amount_ml'];
      return sum +
          (amount is int ? amount : int.tryParse(amount.toString()) ?? 0);
    });
  }

  Future<List<Map<String, dynamic>>> getTodayWaterLogs() async {
    final patientId = await getCurrentPatientId();
    if (patientId == null) {
      return [];
    }

    final today = DateTime.now().toUtc().toIso8601String().split('T').first;
    final data = await _supabase
        .from('water_intake_logs')
        .select('id, amount_ml, logged_at, log_date, notes')
        .eq('patient_id', patientId)
        .eq('log_date', today)
        .order('logged_at', ascending: false);

    return List<Map<String, dynamic>>.from(data as List<dynamic>);
  }

  Future<List<Map<String, dynamic>>> getWaterHistory() async {
    final patientId = await getCurrentPatientId();
    if (patientId == null) {
      return [];
    }

    final monthAgo = DateTime.now().subtract(const Duration(days: 30));
    final startDate = monthAgo.toUtc().toIso8601String().split('T').first;
    final data = await _supabase
        .from('water_intake_logs')
        .select('id, amount_ml, logged_at, log_date, notes')
        .eq('patient_id', patientId)
        .gte('log_date', startDate)
        .order('log_date', ascending: false)
        .order('logged_at', ascending: false);

    return List<Map<String, dynamic>>.from(data as List<dynamic>);
  }

  Future<void> addWaterIntake(int amountMl) async {
    final patientId = await getCurrentPatientId();
    if (patientId == null) {
      throw Exception('Unable to find patient record.');
    }

    await _supabase.from('water_intake_logs').insert({
      'patient_id': patientId,
      'amount_ml': amountMl,
    });
  }

  Future<Map<String, dynamic>?> getLatestBloodPressure() async {
    return null;
  }

  Future<Map<String, dynamic>?> getLatestWeightLog() async {
    return null;
  }
}
