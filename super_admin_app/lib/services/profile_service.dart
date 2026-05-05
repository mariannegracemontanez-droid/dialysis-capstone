import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class ProfileService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  // 🔥 GET CURRENT USER ID
  String get currentUserId {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("User not logged in");
    return user.id;
  }

  // 🔥 FETCH ADMIN PROFILES
  Future<List<Map<String, dynamic>>> getAdminProfiles() async {
    final data = await _supabase
        .from('profiles')
        .select('*, clinics(name)')
        .eq('role', 'admin')
        .eq('status', 'active')
        .order('full_name');

    return List<Map<String, dynamic>>.from(data);
  }

  // 🔥 FETCH AUDIT LOGS
  Future<List<Map<String, dynamic>>> getAdminLogs() async {
    final data = await _supabase
        .from('audit_logs')
        .select()
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  // 🔥 CREATE ADMIN
  Future<String> createAdmin({
  required String fullName,
  required String email,
  required String password,
  required String phone,
  required String clinicId,
}) async {

  // 🔥 STEP 1: CREATE AUTH USER
  final authResponse = await _supabase.auth.signUp(
    email: email,
    password: password,
  );

  final user = authResponse.user;

  if (user == null) {
    throw Exception("Failed to create user");
  }
  
  // 🔥 STEP 2: INSERT PROFILE (IMPORTANT FK)
  await _supabase.from('profiles').insert({
    'id': user.id, // ✅ MUST MATCH auth.users
    'full_name': fullName,
    'email': email,
    'role': 'admin',
    'phone': phone,
    'clinic_id': clinicId,
    'status': 'active',
  });

  return user.id;
}

  // 🔥 UPDATE ADMIN
  Future<void> updateAdmin({
    required String adminId,
    required String fullName,
    String? phone,
    String? password,
    String? clinicId,
  }) async {
    await _supabase
        .from('profiles')
        .update({
          'full_name': fullName,
          'phone': phone,
          'clinic_id': clinicId,
        })
        .eq('id', adminId);

    if (password != null && password.isNotEmpty) {
      await _supabase.auth.updateUser(
        UserAttributes(password: password),
      );
    }
  }

  // 🔥 DELETE ADMIN
  Future<void> deleteAdmin({required String adminId}) async {
    await _supabase.from('profiles').delete().eq('id', adminId);
  }

  // 🔥 AUDIT LOG
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