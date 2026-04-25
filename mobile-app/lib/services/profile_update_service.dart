import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileUpdateService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> updateContactInfo({
    required String userId,
    required String email,
    required String fullName,
    String? phone,
    String? location,
  }) async {
    await _supabase
        .from('profiles')
        .update({
          'email': email,
          'full_name': fullName, // Adjust if column name differs
          'phone': phone,
          'user_location': location, // Explicitly use 'user_location' column
        })
        .eq('id', userId); // Assuming 'id' is the primary key
  }

  Future<void> updateMedicalInfo({
    required String userId,
    String? bloodType,
    double? weight,
    double? height,
    DateTime? lastDialysisDate,
  }) async {
    await _supabase
        .from('profiles')
        .update({
          'blood_type': ?bloodType,
          'weight': ?weight,
          'height': ?height,
          if (lastDialysisDate != null)
            'last_dialysis_date': lastDialysisDate.toIso8601String(),
        })
        .eq('id', userId);
  }
}
