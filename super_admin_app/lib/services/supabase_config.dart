// lib/services/supabase_config.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
  // Expose a single SupabaseClient for the whole app
  static late final SupabaseClient client;

  /// Call this once in main.dart before runApp()
  static Future<void> initialize() async {
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (supabaseUrl == null || supabaseAnonKey == null) {
      throw Exception(
        'Missing Supabase configuration. Check your .env file for SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }

    client = SupabaseClient(supabaseUrl, supabaseAnonKey);
  }
}
