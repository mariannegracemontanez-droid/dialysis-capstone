// ignore_for_file: avoid_print

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/appointment.dart';
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
          .gte('date', start.toIso8601String())
          .lte('date', end.toIso8601String());
      
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

  // Get total patients count
  Future<int> getTotalPatients() async {
    final response = await _client.from('patients').select();
    return response.length;
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
}