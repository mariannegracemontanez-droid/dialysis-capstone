// ignore_for_file: avoid_print

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/appointment.dart';
import '../models/clinic.dart';
import '../models/patient.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Fetch all patients
  Future<List<Patient>> getPatients() async {
    final response = await _client.from('patients').select();
    return response.map((json) => Patient.fromJson(json)).toList();
  }

  // Fetch appointments for a specific date range
  Future<List<Appointment>> getAppointments(DateTime start, DateTime end) async {
    try {
      final response = await _client
          .from('appointments')
          .select('*, patients(name)')
          .gte('appointment_date', start.toIso8601String())
          .lte('appointment_date', end.toIso8601String());
      
      print('Appointments fetched: ${response.length} records');
      print('Response: $response');
      
      return response.map((json) {
        print('Processing appointment: $json');
        return Appointment.fromJson({
          ...json,
          'patient_name': json['patients'] != null ? json['patients']['name'] : 'Unknown',
        });
      }).toList();
    } catch (e) {
      print('Error fetching appointments: $e');
      rethrow;
    }
  }

  // Fetch today's appointments
  Future<List<Appointment>> getTodaysAppointments() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));
    return getAppointments(start, end);
  }

  // Get total patients count from profiles table where role is patient
  Future<int> getTotalPatients() async {
    final response = await _client.from('profiles').select().eq('role', 'patient');
    return response.length;
  }

  Future<int> getClinicCount() async {
    try {
      final response = await _client.from('clinics_centers').select();
      print('✓ Clinic count: ${response.length}');
      return response.length;
    } catch (e) {
      print('✗ Error fetching clinic count: $e');
      return 0;
    }
  }

  Future<List<Clinic>> getClinics() async {
    try {
      final response = await _client.from('clinics_centers').select();
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
        .from('clinics_centers')
        .select()
        .eq('id', clinicId)
        .maybeSingle();
    if (response == null) return null;
    return Clinic.fromJson(response as Map<String, dynamic>);
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
    return Patient.fromJson(response as Map<String, dynamic>);
  }

  Future<void> createClinic(Map<String, dynamic> clinicData) async {
    await _client.from('clinics_centers').insert(clinicData);
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

  // Get today's appointments count
  Future<int> getTodaysAppointmentsCount() async {
    final appointments = await getTodaysAppointments();
    return appointments.length;
  }

  // Update appointment status
  Future<void> updateAppointmentStatus(String appointmentId, String status) async {
    await _client
      .from('appointments')
      .update({'status': status})
      .eq('id', appointmentId);
  }

  // Confirm appointment
  Future<void> confirmAppointment(String appointmentId) async {
    await updateAppointmentStatus(appointmentId, 'Confirmed');
  }

  // Decline appointment
  Future<void> declineAppointment(String appointmentId) async {
    await updateAppointmentStatus(appointmentId, 'Declined');
  }

  // Fetch prescription info for appointment
  Future<String?> getPrescription(String appointmentId) async {
    final response = await _client
      .from('appointments')
      .select('prescription')
      .eq('id', appointmentId)
      .single();
    return response['prescription'] as String?;
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
}