import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/user_model.dart';

class AuthService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<UserModel> signIn({
    required String email,
    required String password,
    List<String> allowedRoles = const ['superadmin'],
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw Exception('Incorrect password or email. Please try again.');
      }

      final profile = await _supabase
          .from('profiles')
          .select('id, email, full_name, role, created_at')
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        if (!allowedRoles.map((role) => role.toLowerCase().trim()).contains('superadmin')) {
          await _supabase.auth.signOut();
          throw Exception('Incorrect password or email. Please try again.');
        }

        try {
          await _supabase.from('profiles').insert({
            'id': user.id,
            'email': email,
            'full_name': 'Super Admin',
            'role': 'superadmin',
          });
        } catch (error) {
          await _supabase.auth.signOut();
          throw Exception('Incorrect password or email. Please try again.');
        }

        return UserModel(
          id: user.id,
          email: email,
          fullName: 'Super Admin',
          role: 'superadmin',
          createdAt: DateTime.now(),
        );
      }

      final loggedInUser = UserModel.fromJson(profile);
      final normalizedRole = loggedInUser.role.toLowerCase().trim();
      if (!allowedRoles
          .map((role) => role.toLowerCase().trim())
          .contains(normalizedRole)) {
        await _supabase.auth.signOut();
        throw Exception('Incorrect password or email. Please try again.');
      }

      return loggedInUser;
    } on AuthException catch (_) {
      throw Exception('Incorrect password or email. Please try again.');
    } catch (_) {
      throw Exception('Incorrect password or email. Please try again.');
    }
  }
}
