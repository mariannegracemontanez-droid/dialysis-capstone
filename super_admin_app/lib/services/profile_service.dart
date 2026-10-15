import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/center_assignment.dart';

class ProfileService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  String get currentUserId {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("User not logged in");
    return user.id;
  }

  /// Returns every admin profile regardless of status -- both active and
  /// inactive (soft-deactivated) accounts -- so the Account Management page's
  /// Status filter has real active/inactive data to filter between. Note this
  /// is a different query from the separate status='active' clinic-locking
  /// checks inside the Create/Edit modals, which stay unchanged.
  Future<List<Map<String, dynamic>>> getAdminProfiles() async {
    final data = await _supabase
        .from('profiles')
        .select('*, clinics(name)')
        .eq('role', 'admin')
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

  /// Updates an admin's own profile row only.
  ///
  /// There is deliberately no password parameter (R4). The only client-side
  /// API available, auth.updateUser(), acts on the CURRENTLY AUTHENTICATED
  /// user and accepts no target user id, so passing a password here changed
  /// the Super Admin's own password rather than [adminId]'s, while the UI
  /// reported success. Setting another user's password requires a privileged
  /// server-side call (auth.admin.updateUserById) that a client holding only
  /// the anon key cannot make, so the capability was removed rather than
  /// faked. Account creation is unaffected -- there the password belongs to
  /// the account being registered.
  Future<void> updateAdmin({
    required String adminId,
    required String fullName,
    String? phone,
    String? clinicId,
  }) async {
    // .select() so the update reports which rows it actually changed. A
    // PostgREST update that matches nothing is NOT an error -- it quietly
    // affects zero rows -- so without this an account that no longer exists,
    // or that this session cannot change, still reported success.
    final updated = await _supabase
        .from('profiles')
        .update({'full_name': fullName, 'phone': phone, 'clinic_id': clinicId})
        .eq('id', adminId)
        .select();

    if (updated.isEmpty) {
      throw Exception(
        'This account could not be updated. It may have been removed or '
        'changed by someone else. Refresh and try again.',
      );
    }

  }

  Future<void> deleteAdmin({required String adminId}) async {
    // Verified with .select() for the same reason as updateAdmin: a zero-row
    // update is silent. Here the row must also still match role='admin', so
    // an id that is not an admin account changes nothing and must not be
    // reported as a successful deactivation.
    final updated = await SupabaseConfig.client
        .from('profiles')
        .update({'status': 'inactive', 'is_active': false, 'clinic_id': null})
        .eq('id', adminId)
        .eq('role', 'admin')
        .select();

    if (updated.isEmpty) {
      throw Exception(
        'This account could not be deactivated. It may have been removed or '
        'changed by someone else. Refresh and try again.',
      );
    }
  }

  /// Mirrors deleteAdmin() in reverse. The previous clinic assignment is not
  /// stored anywhere once cleared, so reactivation always requires a fresh
  /// clinic choice from the Super Admin -- this method does not attempt to
  /// recover or guess the old clinic_id.
  Future<void> reactivateAdmin({
    required String adminId,
    required String clinicId,
  }) async {
    // Verified with .select(), mirroring deleteAdmin() -- a zero-row update
    // is silent, so a reactivation that matched no admin account must not
    // report success.
    final updated = await SupabaseConfig.client
        .from('profiles')
        .update({
          'status': 'active',
          'is_active': true,
          'clinic_id': clinicId,
        })
        .eq('id', adminId)
        .eq('role', 'admin')
        .select();

    if (updated.isEmpty) {
      throw Exception(
        'This account could not be reactivated. It may have been removed or '
        'changed by someone else. Refresh and try again.',
      );
    }
  }

  /// Re-checks, immediately before saving, that [clinicId] can still take an
  /// admin assignment: the centre exists, is Active, and has no other active
  /// admin. The modal's dropdown already hides ineligible centres, but its
  /// list may be stale (another session may have assigned or deactivated the
  /// centre since it loaded). Throws an [Exception] with a user-facing
  /// message when the centre is no longer eligible. [adminId] is the account
  /// being assigned, which never counts against itself.
  Future<void> ensureClinicAssignable(
    String clinicId, {
    String? adminId,
  }) async {
    final clinic = await _supabase
        .from('clinics')
        .select('id, status')
        .eq('id', clinicId)
        .maybeSingle();

    final admins = await _supabase
        .from('profiles')
        .select('id, clinic_id')
        .eq('role', 'admin')
        .eq('status', 'active')
        .eq('is_active', true)
        .eq('clinic_id', clinicId);

    final otherAdmins = admins
        .where((row) => row['id']?.toString() != adminId)
        .map((row) => row['clinic_id']?.toString())
        .whereType<String>()
        .toSet();

    if (clinic == null ||
        !isCenterEligibleForAssignment(clinic, clinicsWithAdmin: otherAdmins)) {
      throw Exception(
        clinic == null
            ? 'The selected center no longer exists. Refresh and choose '
                  'another center.'
            : 'The selected center is no longer available -- it is inactive '
                  'or another admin was assigned to it. Choose another center.',
      );
    }
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
