import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'pages/landing_page.dart';
import 'pages/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? dotenvError;
  try {
    await dotenv.load();
  } catch (e) {
    dotenvError = 'Failed to load .env file: $e';
  }

  final url = dotenv.env['SUPABASE_URL']?.trim();
  final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim();

  if (dotenvError != null ||
      url == null ||
      anonKey == null ||
      url.isEmpty ||
      anonKey.isEmpty) {
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Donation App',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const LandingPage(),
    );
  }
}
