import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/supabase_config.dart';
import 'pages/dashboard_page.dart';
import 'pages/login_page_v2.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "assets/.env");
  await SupabaseConfig.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  final String? initError;

  const MyApp({super.key, this.initError});

  @override
  Widget build(BuildContext context) {
    if (initError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CureNurture Super Admin',
        theme: ThemeData(useMaterial3: true, primarySwatch: Colors.blue),
        home: Scaffold(
          appBar: AppBar(title: const Text('Initialization Error')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not initialize Supabase:\n$initError',
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

   return MaterialApp(
  debugShowCheckedModeBanner: false,
  title: 'CureNurture Super Admin',
  theme: ThemeData(useMaterial3: true, primarySwatch: Colors.blue),
  initialRoute: '/login',
  routes: {
    '/login': (context) => const LoginPage(),
    '/dashboard': (context) => const DashboardPage(),
  },
);
  }
}
