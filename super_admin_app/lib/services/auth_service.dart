import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/user_model.dart';

class AuthService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<UserModel> signIn({
    required String email,
    required String password,
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
        await _supabase.from('profiles').insert({
          'id': user.id,
          'email': email,
          'full_name': 'Super Admin',
          'role': 'superadmin',
        });

        return UserModel(
          id: user.id,
          email: email,
          fullName: 'Super Admin',
          role: 'superadmin',
          createdAt: DateTime.now(),
        );
      }

      return UserModel.fromJson(profile);
    } catch (error) {
      throw Exception('Sign in error: ${error.toString()}');
    }
  }
}
