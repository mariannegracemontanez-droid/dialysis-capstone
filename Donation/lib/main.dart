import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'theme/brand.dart';
import 'pages/landing_page.dart';

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
      title: 'CureNurture — Donate',
      // Presentation only: gives Flutter's built-in widgets (selection
      // handles, focus rings, progress indicators, dialogs) the CureNurture
      // palette instead of the default Material blue.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Brand.brand,
          primary: Brand.brand,
          secondary: Brand.teal,
          surface: Brand.white,
          error: Brand.coral,
        ),
        scaffoldBackgroundColor: Brand.canvas,
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Brand.teal,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Brand.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          titleTextStyle: Brand.heading(20),
          contentTextStyle: Brand.body(14.5),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: const LandingPage(),
    );
  }
}
