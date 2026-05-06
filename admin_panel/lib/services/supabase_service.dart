// ignore_for_file: avoid_print

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/clinic.dart';
import '../models/patient.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Fetch all patients
  Future<List<Patient>> getPatients() async {
    final response = await _client.from('patients').select();
    return response.map((json) => Patient.fromJson(json)).toList();
  }


  // Get total patients count from profiles table where role is patient
  Future<int> getTotalPatients() async {
    final response = await _client.from('profiles').select().eq('role', 'patient');
    return response.length;
  }

  Future<int> getClinicCount() async {
    try {
      final response = await _client.from('clinics').select();
      print('✓ Clinic count: ${response.length}');
      return response.length;
    } catch (e) {
      print('✗ Error fetching clinic count: $e');
      return 0;
    }
  }

  Future<List<Clinic>> getClinics() async {
    try {
      final response = await _client.from('clinics').select();
      print('✓ Clinics fetched: ${response.length} records');
      print('Response: $response');
      return (response as List).map((json) => Clinic.fromJson(json)).toList();
    } catch (e) {
      print('✗ Error fetching clinics: $e');
      return [];
    }
  }

  Future<Clinic?> getClinicById(String clinicId) async {
    final response = await _client
        .from('clinics')
        .select()
        .eq('id', clinicId)
        .maybeSingle();
    if (response == null) return null;
    return Clinic.fromJson(response);
  }

  Future<List<Patient>> getPatientsByClinic(String clinicId) async {
    final response = await _client
        .from('profiles')
        .select()
        .eq('role', 'patient')
        .eq('clinic_id', clinicId)
        .limit(5);
    return (response as List).map((json) => Patient.fromJson(json)).toList();
  }

  Future<List<Patient>> getAllPatients() async {
    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('role', 'patient');
      print('✓ All patients fetched: ${response.length} records');
      print('Response: $response');
      return (response as List).map((json) => Patient.fromJson(json)).toList();
    } catch (e) {
      print('✗ Error fetching all patients: $e');
      return [];
    }
  }

  Future<List<Patient>> getPatientRoster() async {
    final profilesResponse = await _client
        .from('profiles')
        .select()
        .eq('role', 'patient');
    final patientsResponse = await _client.from('patients').select();

    final profilePatients = (profilesResponse as List)
        .map((json) => Patient.fromJson(json))
        .toList();
    final patientTablePatients = (patientsResponse as List)
        .map((json) => Patient.fromJson(json))
        .toList();

    final merged = <Patient>[];
    final existingIds = <String>{};

    for (final patient in profilePatients) {
      existingIds.add(patient.id);
      merged.add(patient);
    }
    for (final patient in patientTablePatients) {
      if (!existingIds.contains(patient.id)) {
        merged.add(patient);
      }
    }

    return merged;
  }

  Future<Patient?> getPatientById(String patientId) async {
    final response = await _client
        .from('profiles')
        .select()
        .eq('id', patientId)
        .maybeSingle();
    if (response == null) return null;
    return Patient.fromJson(response);
  }

  Future<void> createClinic(Map<String, dynamic> clinicData) async {
    await _client.from('clinics').insert(clinicData);
  }

  Future<void> createPatient(Map<String, dynamic> patientData) async {
    await _client.from('profiles').insert(patientData);
  }

  Future<void> updatePatient(String patientId, Map<String, dynamic> updates) async {
    await _client
        .from('profiles')
        .update(updates)
        .eq('id', patientId);
  }


  // Fetch available time slots for dialysis appointments
  Future<List<Map<String, dynamic>>> getAvailableTimeSlots({int daysAhead = 7}) async {
    final slots = <Map<String, dynamic>>[];
    final now = DateTime.now();
    final timeSlots = ['08:00 AM', '09:30 AM', '11:00 AM', '01:00 PM', '02:30 PM', '04:00 PM'];
    
    // Generate slots for the next N days
    for (int i = 0; i < daysAhead; i++) {
      final date = now.add(Duration(days: i));
      // Skip Sundays (dialysis centers typically closed)
      if (date.weekday == 7) continue;
      
      for (final time in timeSlots) {
        slots.add({
          'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          'time': time,
          'displayDate': '${_getWeekdayName(date.weekday)}, ${date.month}/${date.day}',
          'available': true,
        });
      }
    }
    
    return slots;
  }

  String _getWeekdayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  // Get pending patients count
  Future<int> getPendingPatientsCount() async {
    try {
      final response = await _client
          .from('patients')
          .select()
          .eq('status', 'pending');
      return response.length;
    } catch (e) {
      print('Error fetching pending patients count: $e');
      return 0;
    }
  }

  // Get list of pending patients
  Future<List<Patient>> getPendingPatients() async {
    try {
      final response = await _client
          .from('patients')
          .select('*, profiles(*)')
          .eq('status', 'pending');
      return (response as List).map((json) => Patient.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching pending patients: $e');
      return [];
    }
  }

  // Get list of accepted patients
  Future<List<Patient>> getAcceptedPatients() async {
    try {
      final response = await _client
          .from('patients')
          .select('*, profiles(*)')
          .inFilter('status', ['accepted', 'no_sched']);
      return (response as List).map((json) => Patient.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching accepted patients: $e');
      return [];
    }
  }

  // Get list of declined patients
  Future<List<Patient>> getDeclinedPatients() async {
    try {
      final response = await _client
          .from('patients')
          .select('*, profiles(*)')
          .eq('status', 'declined');
      return (response as List).map((json) => Patient.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching declined patients: $e');
      return [];
    }
  }

  // Update patient status
  Future<void> updatePatientStatus(String patientId, String status) async {
    try {
      await _client
          .from('patients')
          .update({'status': status})
          .eq('id', patientId);
      print('Patient status updated: $patientId -> $status');
    } catch (e) {
      print('Error updating patient status: $e');
      rethrow;
    }
  }

  // Get monthly patient data for graph
  Future<List<Map<String, dynamic>>> getMonthlyPatientData({int months = 6}) async {
    try {
      final data = <Map<String, dynamic>>[];
      final now = DateTime.now();

      for (int i = months - 1; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        final nextMonth = DateTime(date.year, date.month + 1, 1);

        final response = await _client
            .from('profiles')
            .select()
            .eq('role', 'patient')
            .gte('created_at', date.toIso8601String())
            .lt('created_at', nextMonth.toIso8601String());

        final month = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        data.add({
          'month': _getMonthName(date.month),
          'count': response.length,
          'date': month,
        });
      }

      return data;
    } catch (e) {
      print('Error fetching monthly patient data: $e');
      return [];
    }
  }

  // Create dialysis slot for patient
  Future<void> createDialysisSlot(Map<String, dynamic> slotData) async {
    try {
      await _client.from('dialysis_slots').insert(slotData);
      print('Dialysis slot created successfully');
    } catch (e) {
      print('Error creating dialysis slot: $e');
      rethrow;
    }
  }

  // Get patient's dialysis schedule
  Future<List<Map<String, dynamic>>> getPatientSchedule(String patientId) async {
    try {
      final response = await _client
          .from('dialysis_slots')
          .select()
          .eq('patient_id', patientId);
      return response;
    } catch (e) {
      print('Error fetching patient schedule: $e');
      return [];
    }
  }

  // Update patient's dialysis schedule
  Future<void> updatePatientSchedule(
      String patientId, List<String> days) async {
    try {
      // Delete existing slots
      await _client
          .from('dialysis_slots')
          .delete()
          .eq('patient_id', patientId);

      // Create new slots
      for (final day in days) {
        await createDialysisSlot({
          'patient_id': patientId,
          'day_of_week': day,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      print('Patient schedule updated successfully');
    } catch (e) {
      print('Error updating patient schedule: $e');
      rethrow;
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  Future<void> setPatientSchedule(String id, String s, List<Map<String, String?>> scheduleEntries) async {}

  Future<List<Patient>> getPatientsByStatus(String s) async {
    try {
      final response = await _client.from('patients').select().eq('status', s);
      return response.map((json) => Patient.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching patients by status: $e');
      return [];
    }
  }

}