import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class ProfileService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<List<Map<String, dynamic>>> getProfilesByRole(String role) async {
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('role', role)
        .order('full_name', ascending: true);

    return List<Map<String, dynamic>>.from(data as List<dynamic>);
  }

  Future<List<Map<String, dynamic>>> getProfilesByRoles(List<String> roles) async {
    final data = await _supabase
        .from('profiles')
        .select()
        .inFilter('role', roles)
        .order('full_name', ascending: true);

    return List<Map<String, dynamic>>.from(data as List<dynamic>);
  }

  Future<List<Map<String, dynamic>>> getAllProfiles() async {
    final data = await _supabase.from('profiles').select().order('full_name', ascending: true);
    return List<Map<String, dynamic>>.from(data as List<dynamic>);
  }

  Future<void> createAdmin({
    required String fullName,
    required String email,
    required String password,
    String? phoneNumber,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Unable to create admin account.');
    }

    final profileInsert = await _supabase.from('profiles').insert({
      'id': user.id,
      'email': email,
      'full_name': fullName,
      'role': 'admin',
      if (phoneNumber != null && phoneNumber.isNotEmpty) 'phone_number': phoneNumber,
    });

    if (profileInsert.error != null) {
      throw Exception('Failed to insert admin profile: ${profileInsert.error!.message}');
    }
  }
}
