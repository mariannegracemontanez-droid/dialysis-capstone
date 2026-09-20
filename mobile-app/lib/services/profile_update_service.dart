import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileUpdateService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<String> _getActivePatientId(String passedId) async {
    final currentUserId = _supabase.auth.currentUser?.id;

    Map<String, dynamic>? patient;

    patient = await _supabase
        .from('patients')
        .select('id')
        .eq('id', passedId)
        .eq('status', 'active')
        .maybeSingle();

    if (patient != null) return patient['id'].toString();

    patient = await _supabase
        .from('patients')
        .select('id')
        .eq('profile_id', passedId)
        .eq('status', 'active')
        .maybeSingle();

    if (patient != null) return patient['id'].toString();

    if (currentUserId != null) {
      patient = await _supabase
          .from('patients')
          .select('id')
          .eq('profile_id', currentUserId)
          .eq('status', 'active')
          .maybeSingle();

      if (patient != null) return patient['id'].toString();
    }

    throw Exception('No active patient record found for this account.');
  }

  Future<void> updateContactInfo({
    required String patientId,
    required String email,
    required String fullName,
    String? phone,
    String? location,
  }) async {
    try {
      final activePatientId = await _getActivePatientId(patientId);

      await _supabase
          .from('patients')
          .update({
            'email': email.trim(),
            'full_name': fullName.trim(),
            'phone': phone?.trim(),
            'home_address': location?.trim(),
          })
          .eq('id', activePatientId);
    } on PostgrestException catch (e) {
      throw Exception(_formatSupabaseError(e));
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> updateMedicalInfo({
    required String patientId,
    String? bloodType,
    double? weight,
    double? height,
    DateTime? lastDialysisDate,
  }) async {
    final updateData = <String, dynamic>{
      if (bloodType != null && bloodType.trim().isNotEmpty)
        'blood_type': bloodType.trim(),
      'weight': ?weight,
      'height': ?height,
      if (lastDialysisDate != null)
        'last_dialysis_date': lastDialysisDate
            .toIso8601String()
            .split('T')
            .first,
    };

    if (updateData.isEmpty) return;

    try {
      final activePatientId = await _getActivePatientId(patientId);

      await _supabase
          .from('patients')
          .update(updateData)
          .eq('id', activePatientId);
    } on PostgrestException catch (e) {
      throw Exception(_formatSupabaseError(e));
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _formatSupabaseError(PostgrestException error) {
    final message = error.message.toLowerCase();

    if (message.contains('weight') && message.contains('column')) {
      return 'Weight field is missing in database.';
    }

    if (message.contains('height') && message.contains('column')) {
      return 'Height field is missing in database.';
    }

    if (message.contains('last_dialysis_date') && message.contains('column')) {
      return 'Last dialysis date field is missing in database.';
    }

    if (message.contains('invalid input syntax')) {
      return 'Please enter a valid value.';
    }

    return error.message;
  }
}
