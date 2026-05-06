import 'package:flutter/material.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://emnpezpkrrrilrcxnuwe.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVtbnBlenBrcnJyaWxyY3hudXdlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI0MTkwNzcsImV4cCI6MjA4Nzk5NTA3N30.ow7VCTizP-Q6j-0FD4gtKWiok3kVUZFCxag5UWg9weM',
  );
  runApp(const ProviderScope(child: MyApp()));
}

Future<void> main2() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? dotenvError;
  try {
    await dotenv.load();
  } catch (e) {
    dotenvError = 'Failed to load .env file: $e';
  }

  final url = dotenv.env['SUPABASE_URL'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (dotenvError != null || url == null || anonKey == null) {
    // Shows a helpful message instead of crashing.
    final message = dotenvError != null
        ? '$dotenvError\n\nMake sure you have a .env file in the project root.'
        : 'Missing .env values.\nMake sure .env contains SUPABASE_URL and SUPABASE_ANNON_KEY.';

    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Text(message, textAlign: TextAlign.center)),
        ),
      ),
    );
    return;
  }

  await Supabase.initialize(url: url, anonKey: anonKey);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginPage(),
    );
  }
}
