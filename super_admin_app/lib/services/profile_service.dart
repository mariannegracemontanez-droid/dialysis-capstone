import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class ProfileService {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final GoTrueClient? _adminAuth = _createAdminAuthClient();

  static GoTrueClient? _createAdminAuthClient() {
    final url =
        dotenv.env['SUPABASE_URL'] ??
        const String.fromEnvironment('SUPABASE_URL');
    final serviceRoleKey = dotenv.env['SUPABASE_SERVICE_ROLE_KEY'];

    if (url.isEmpty || serviceRoleKey == null || serviceRoleKey.isEmpty) {
      return null;
    }

    return GoTrueClient(
      url: url,
      headers: {
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
        'Content-Type': 'application/json',
      },
      autoRefreshToken: false,
    );
  }

  Future<String> _adminActorId() async {
    final actorId = _supabase.auth.currentUser?.id;
    if (actorId == null) {
      throw Exception('Super Admin session not found.');
    }
    return actorId;
  }

  Future<List<Map<String, dynamic>>> getProfilesByRole(String role) async {
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('role', role)
        .order('full_name', ascending: true);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getProfilesByRoles(
    List<String> roles,
  ) async {
    final data = await _supabase
        .from('profiles')
        .select()
        .inFilter('role', roles)
        .order('full_name', ascending: true);

    return List<Map<String, dynamic>>.from(data as List<dynamic>);
  }

  Future<List<Map<String, dynamic>>> getAllProfiles() async {
    final data = await _supabase
        .from('profiles')
        .select()
        .order('full_name', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getAdminProfiles() async {
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('role', 'admin')
        .order('full_name', ascending: true);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getAdminLogs() async {
    final logsResponse = await _supabase
        .from('admin_logs')
        .select()
        .order('created_at', ascending: false);

    final logs = List<Map<String, dynamic>>.from(logsResponse);
    final profileIds = <String>{};

    for (final log in logs) {
      if (log['admin_id'] != null) {
        profileIds.add(log['admin_id'] as String);
      }
      if (log['target_id'] != null) {
        profileIds.add(log['target_id'] as String);
      }
    }

    if (profileIds.isEmpty) {
      return logs;
    }

    final profilesResponse = await _supabase
        .from('profiles')
        .select('id, full_name, email')
        .inFilter('id', profileIds.toList());

    final profiles = List<Map<String, dynamic>>.from(profilesResponse);

    final profileMap = {
      for (final profile in profiles) profile['id'] as String: profile,
    };

    return logs.map((log) {
      final adminProfile = profileMap[log['admin_id'] as String? ?? ''];
      final targetProfile = profileMap[log['target_id'] as String? ?? ''];

      return {
        ...log,
        'actor_name': adminProfile == null
            ? 'Unknown'
            : (adminProfile['full_name'] ?? adminProfile['email'] ?? 'Unknown'),
        'target_name': targetProfile == null
            ? 'Unknown'
            : (targetProfile['full_name'] ??
                  targetProfile['email'] ??
                  'Unknown'),
      };
    }).toList();
  }

  Future<Map<String, dynamic>?> getAdminById(String adminId) async {
    final response = await _supabase
        .from('profiles')
        .select()
        .eq('id', adminId)
        .eq('role', 'admin')
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<void> createAdmin({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    if (_adminAuth == null) {
      throw Exception(
        'Creating admins requires SUPABASE_SERVICE_ROLE_KEY in your .env.',
      );
    }

    final adminAuth = _adminAuth;
    final userResponse = await adminAuth.admin.createUser(
      AdminUserAttributes(
        email: email,
        password: password,
        userMetadata: {
          'full_name': fullName,
          if (phone?.isNotEmpty ?? false) 'phone': phone,
        },
        appMetadata: {'role': 'admin'},
        emailConfirm: true,
      ),
    );

    final user = userResponse.user;
    if (user == null) {
      throw Exception('Unable to create admin account.');
    }

    try {
      await _supabase.from('profiles').insert({
        'id': user.id,
        'email': email,
        'full_name': fullName,
        'role': 'admin',
        if (phone?.isNotEmpty ?? false) 'phone': phone,
      });
    } catch (error) {
      try {
        await adminAuth.admin.deleteUser(user.id);
      } catch (_) {
        // ignore cleanup failure, the original error is more important
      }
      throw Exception('Failed to insert admin profile: $error');
    }

    await _insertAdminLog(
      adminId: await _adminActorId(),
      action: 'create',
      targetId: user.id,
    );
  }

  Future<void> updateAdmin({
    required String adminId,
    required String fullName,
    String? phone,
    String? password,
  }) async {
    final updateData = <String, dynamic>{
      'full_name': fullName,
      if (phone?.isNotEmpty ?? false) 'phone': phone,
    };

    try {
      await _supabase
          .from('profiles')
          .update(updateData)
          .eq('id', adminId)
          .eq('role', 'admin');
    } catch (error) {
      throw Exception('Failed to update admin profile: $error');
    }

    if (password != null && password.isNotEmpty) {
      if (_adminAuth == null) {
        throw Exception(
          'Password reset requires SUPABASE_SERVICE_ROLE_KEY in your .env.',
        );
      }

      await _adminAuth.admin.updateUserById(
        adminId,
        attributes: AdminUserAttributes(password: password),
      );
    }

    await _insertAdminLog(
      adminId: await _adminActorId(),
      action: 'update',
      targetId: adminId,
    );
  }

  Future<void> deleteAdmin({required String adminId}) async {
    if (_adminAuth == null) {
      throw Exception(
        'Admin deletion requires SUPABASE_SERVICE_ROLE_KEY in your .env.',
      );
    }

    await _adminAuth.admin.deleteUser(adminId);

    try {
      await _supabase
          .from('profiles')
          .delete()
          .eq('id', adminId)
          .eq('role', 'admin');
    } catch (error) {
      throw Exception('Failed to delete admin profile: $error');
    }

    await _insertAdminLog(
      adminId: await _adminActorId(),
      action: 'delete',
      targetId: adminId,
    );
  }

  Future<void> _insertAdminLog({
    required String adminId,
    required String action,
    required String targetId,
  }) async {
    try {
      await _supabase.from('admin_logs').insert({
        'admin_id': adminId,
        'action': action,
        'target_table': 'profiles',
        'target_id': targetId,
      });
    } catch (error) {
      throw Exception('Failed to write admin log: $error');
    }
  }
}
