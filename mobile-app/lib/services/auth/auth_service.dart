import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../../config/supabase_config.dart';

class AuthService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  // Sign Up
  Future<UserModel> signUp({
    required String email,
    required String password,
    required String fullName,
    String role = 'patient',
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Sign up failed');
      }

      await _supabase.from('profiles').insert({
        'id': response.user!.id,
        'email': email,
        'full_name': fullName,
        'role': role,
      });

      final createdAt = response.user?.createdAt;
      final parsedCreatedAt = createdAt != null
          ? DateTime.tryParse(createdAt) ?? DateTime.now()
          : DateTime.now();

      return UserModel(
        id: response.user!.id,
        email: email,
        fullName: fullName,
        role: role,
        createdAt: parsedCreatedAt,
      );
    } catch (e) {
      throw Exception('Sign up error: $e');
    }
  }

  // Sign In
  Future<UserModel> signIn({
    required String email,
    required String password,
    List<String> allowedRoles = const ['patient'],
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Sign in failed');
      }

      final userData = await _supabase
          .from('profiles')
          .select()
          .eq('id', response.user!.id)
          .single();

      final user = UserModel.fromJson(userData);
      if (!allowedRoles.contains(user.role)) {
        await _supabase.auth.signOut();
        throw Exception(
          'Access denied. Your account role (${user.role}) cannot sign in to this app.',
        );
      }

      return user;
    } catch (e) {
      throw Exception('Sign in error: $e');
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // Password reset email
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      throw Exception('Could not send reset link: $e');
    }
  }

  // Update password for logged in user
  Future<void> updatePassword(String password) async {
    try {
      final response = await _supabase.auth.updateUser(
        UserAttributes(password: password),
      );

      if (response.user == null) {
        throw Exception('Password update failed');
      }
    } catch (e) {
      throw Exception('Password update failed: $e');
    }
  }

  // Get Current User
  Future<UserModel?> getCurrentUser() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final userData = await _supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();

    final currentUser = UserModel.fromJson(userData);
    if (currentUser.role != 'patient') {
      await _supabase.auth.signOut();
      return null;
    }

    return currentUser;
  }

  static String? validatePassword(String password) {
    if (password.length < 8) {
      return 'At least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'At least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'At least one lowercase letter';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'At least one number';
    }
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) {
      return 'At least one special character';
    }
    return null;
  }

  static Map<String, bool> passwordRequirements(String password) {
    return {
      'At least 8 characters': password.length >= 8,
      'Uppercase letter': RegExp(r'[A-Z]').hasMatch(password),
      'Lowercase letter': RegExp(r'[a-z]').hasMatch(password),
      'Number': RegExp(r'\d').hasMatch(password),
      'Special character': RegExp(
        r'[!@#\$%^&*(),.?":{}|<>]',
      ).hasMatch(password),
    };
  }
}
