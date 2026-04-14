import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    final url =
        dotenv.env['SUPABASE_URL'] ??
        const String.fromEnvironment('SUPABASE_URL');
    final anonKey =
        dotenv.env['SUPABASE_ANON_KEY'] ??
        const String.fromEnvironment('SUPABASE_ANON_KEY');

    if (url.isEmpty || anonKey.isEmpty) {
      throw Exception(
        'Missing Supabase configuration. Add SUPABASE_URL and SUPABASE_ANON_KEY to .env or pass as --dart-define',
      );
    }

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      // Optional: you can set debug mode for easier troubleshooting
      debug: true,
    );

    _initialized = true;
  }

  static SupabaseClient get client {
    if (!_initialized) {
      throw Exception(
        'Supabase is not initialized. Call SupabaseConfig.initialize() first.',
      );
    }
    return Supabase.instance.client;
  }
}
