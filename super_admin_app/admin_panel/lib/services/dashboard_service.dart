import 'package:admin_panel/features/dashboard/dashboard_page.dart' show supabase;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/patient.dart';
import 'supabase_config.dart';

class DashboardService {
  final SupabaseClient client = SupabaseConfig.client;

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

  Future<int> getTotalPatients() async {
    final clinicId = await getCurrentClinicId();
    if (clinicId == null) return 0;

    final response = await client
        .from('patients')
        .select('id')
        .eq('clinic_id', clinicId);

    return (response as List).length;
  }

  Future<int> getPendingPatientsCount() async {
    final clinicId = await getCurrentClinicId();
    if (clinicId == null) return 0;

    final response = await client
        .from('patients')
        .select('id')
        .eq('clinic_id', clinicId)
        .eq('status', 'pending');

    return (response as List).length;
  }

  Future<Map<String, dynamic>?> getCurrentAdminInfo() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    final response = await client
        .from('profiles')
        .select('full_name, clinics(name)')
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) return null;

    return {
      'adminName': response['full_name'] ?? 'Admin',
      'clinicName': response['clinics']?['name'] ?? 'No clinic assigned',
    };
  }

  Future<List<Patient>> getPatientsByStatus(String status) async {
    final clinicId = await getCurrentClinicId();
    if (clinicId == null) return [];

    final response = await client
        .from('patients')
        .select('*, profiles(*)')
        .eq('clinic_id', clinicId)
        .eq('status', status)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => Patient.fromJson(row as Map<String, dynamic>))
        .toList();
  }

Future<List<Map<String, dynamic>>> getMonthlyPatientData() async {
  final clinicId = await getCurrentClinicId();
  if (clinicId == null) return [];

  final now = DateTime.now();
  final data = <Map<String, dynamic>>[];

  for (int i = 4; i >= 0; i--) {
    final monthStart = DateTime(now.year, now.month - i, 1);
    final nextMonth = DateTime(monthStart.year, monthStart.month + 1, 1);

    final response = await client
        .from('patients')
        .select('id')
        .eq('clinic_id', clinicId)
        .gte('created_at', monthStart.toIso8601String())
        .lt('created_at', nextMonth.toIso8601String());

    data.add({
      'month': _getMonthName(monthStart.month),
      'count': (response as List).length,
    });
  }

  return data;
}

String _getMonthName(int month) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  return months[month - 1];
}

Future<List<Map<String, dynamic>>> getTodaySchedules({
  required String clinicId,
}) async {
  final today = DateTime.now();
  final weekday = _getWeekdayName(today.weekday);

  final weekly = await supabase
      .from('weekly_schedules')
      .select('patient_id')
      .eq('clinic_id', clinicId)
      .contains('scheduled_days', [weekday]);

  if (weekly.isEmpty) return [];

  final patientIds = weekly.map((e) => e['patient_id']).toList();

  final response = await supabase
      .from('patients')
      .select()
      .inFilter('id', patientIds);

  return List<Map<String, dynamic>>.from(response);
}

String _getWeekdayName(int weekday) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  return days[weekday - 1];
}

  Future<void> setPatientSchedule({
    required String patientId,
    required List<String> selectedDays,
  }) async {
    final clinicId = await getCurrentClinicId();

    if (clinicId == null) {
      throw Exception('No clinic assigned to this admin account.');
    }

    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged in user found.');
    }

    await supabase.from('weekly_schedules').upsert({
      'patient_id': patientId,
      'clinic_id': clinicId,
      'created_by': user.id,
      'scheduled_days': selectedDays,
    }, onConflict: 'patient_id');

    await supabase
        .from('patients')
        .update({'status': 'active'})
        .eq('id', patientId)
        .eq('clinic_id', clinicId);
  }

  Future<void> removeTodaySchedule(String dailyScheduleId) async {
    await supabase
        .from('daily_schedules')
        .delete()
        .eq('id', dailyScheduleId);
  }

  Future<Map<String, dynamic>?> getLatestDonation(String centerName) async {
    final response = await client
        .from('fund_distributions')
        .select()
        .eq('center_name', centerName)
        .order('distribution_date', ascending: false)
        .limit(1)
        .maybeSingle();

    return response;
  }

  Future<num> getTotalDonations(String centerName) async {
    final response = await client
        .from('fund_distributions')
        .select('amount')
        .eq('center_name', centerName);

    num total = 0;

    for (final item in response) {
      total += item['amount'] ?? 0;
    }

    return total;
  }

  Future<List<Map<String, dynamic>>> getDonationHistory(String centerName) async {
    final response = await client
        .from('fund_distributions')
        .select()
        .eq('center_name', centerName)
        .order('distribution_date', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

}