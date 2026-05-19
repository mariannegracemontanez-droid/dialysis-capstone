import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class ProfileService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  String get currentUserId {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("User not logged in");
    return user.id;
  }

  Future<List<Map<String, dynamic>>> getAdminProfiles() async {
    final data = await _supabase
        .from('profiles')
        .select('*, clinics(name)')
        .eq('role', 'admin')
        .eq('status', 'active')
        .order('full_name');

    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getAdminLogs() async {
    final data = await _supabase
        .from('audit_logs')
        .select()
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<String> createAdmin({
    required String fullName,
    required String email,
    required String password,
    required String phone,
    required String clinicId,
  }) async {
    final authResponse = await _supabase.auth.signUp(
      email: email,
      password: password,
    );

    final user = authResponse.user;

    if (user == null) {
      throw Exception("Failed to create user");
    }

    await _supabase.from('profiles').insert({
      'id': user.id, //
      'full_name': fullName,
      'email': email,
      'role': 'admin',
      'phone': phone,
      'clinic_id': clinicId,
      'status': 'active',
    });

    return user.id;
  }

  Future<void> updateAdmin({
    required String adminId,
    required String fullName,
    String? phone,
    String? password,
    String? clinicId,
  }) async {
    await _supabase
        .from('profiles')
        .update({'full_name': fullName, 'phone': phone, 'clinic_id': clinicId})
        .eq('id', adminId);

    if (password != null && password.isNotEmpty) {
      await _supabase.auth.updateUser(UserAttributes(password: password));
    }
  }

  Future<void> deleteAdmin({required String adminId}) async {
    await SupabaseConfig.client
        .from('profiles')
        .update({'status': 'inactive', 'is_active': false, 'clinic_id': null})
        .eq('id', adminId)
        .eq('role', 'admin');
  }

  Future<void> logAction({
    required String action,
    required String targetId,
    required String targetName,
    Map<String, dynamic>? metadata,
  }) async {
    final user = _supabase.auth.currentUser;

    await _supabase.from('audit_logs').insert({
      'action': action,
      'actor_id': user?.id,
      'actor_name': 'Super Admin',
      'target_id': targetId,
      'target_name': targetName,
      'metadata': metadata,
    });
  }
}
