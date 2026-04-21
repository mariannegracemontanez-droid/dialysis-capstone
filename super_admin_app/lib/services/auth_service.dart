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
        throw Exception('Login failed. Please check your credentials.');
      }

      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        if (!allowedRoles.contains('superadmin')) {
          await _supabase.auth.signOut();
          throw Exception(
            'Access denied. Your account cannot sign in to this dashboard.',
          );
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
          throw Exception('Failed to create superadmin profile: $error');
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
      if (!allowedRoles.contains(loggedInUser.role)) {
        await _supabase.auth.signOut();
        throw Exception(
          'Access denied. Your account role (${loggedInUser.role}) cannot sign in to this dashboard.',
        );
      }

      return loggedInUser;
    } catch (error) {
      throw Exception('Sign in error: ${error.toString()}');
    }
  }
}
