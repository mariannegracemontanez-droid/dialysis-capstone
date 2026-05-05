import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'models/signup_data.dart';
import 'pages/auth/change_password_page.dart';
import 'pages/auth/confirm_info_page.dart';
import 'pages/auth/forgot_password_page.dart';
import 'pages/auth/location_page.dart';
import 'pages/auth/clinic_info_page.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/medical_documents_page.dart';
import 'pages/auth/financial_page.dart';
import 'pages/auth/setup_page.dart';
import 'pages/auth/signup_page.dart';
import 'pages/auth/signup_complete_page.dart';
import 'pages/auth/welcome_page.dart';
import 'pages/home/home_page.dart';
import 'pages/home/privacy_security_page.dart';
import 'config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initError;

  try {
    // Use dotenv in both mobile/desktop and web for dev, but web can also use dart-define.
    await dotenv.load(fileName: '.env');

    await SupabaseConfig.initialize();
  } catch (e, st) {
    // ignore: avoid_print
    print('Initialization error: $e');
    // ignore: avoid_print
    print(st);
    initError = e.toString();
  }

  runApp(MyApp(initError: initError));
}

class MyApp extends StatelessWidget {
  final String? initError;

  const MyApp({super.key, this.initError});

  @override
  Widget build(BuildContext context) {
    if (initError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CureNurture App - Error',
        theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
        home: Scaffold(
          appBar: AppBar(title: const Text('Initialization Error')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Initialization failed: $initError',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CureNurture App',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      initialRoute: '/welcome',
      routes: {
        '/welcome': (context) => const WelcomePage(),
        '/login': (context) => const LoginPage(),
        '/login_page': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/signup-complete_page': (context) => const SignupCompletePage(),
        '/forgot-password': (context) => const ForgotPasswordPage(),
        '/change-password': (context) => const ChangePasswordPage(),
        '/home': (context) => const HomePage(),
        '/privacy-security': (context) => const PrivacySecurityPage(),
      },
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/setup':
            final args = settings.arguments as SignupData;
            return MaterialPageRoute(
              builder: (_) => SetupPage(signupData: args),
            );
          case '/location':
            final args = settings.arguments as SignupData;
            return MaterialPageRoute(
              builder: (_) => LocationPage(signupData: args),
            );
          case '/clinic-info':
            final args = settings.arguments as ClinicInfoArguments;
            return MaterialPageRoute(
              builder: (_) => ClinicInfoPage(arguments: args),
            );
          case '/medical-documents':
            final args = settings.arguments as SignupData;
            return MaterialPageRoute(
              builder: (_) => MedicalDocumentsPage(signupData: args),
            );
          case '/financial':
            final args = settings.arguments as SignupData;
            return MaterialPageRoute(
              builder: (_) => FinancialPage(signupData: args),
            );
          case '/confirm-info':
            final args = settings.arguments as SignupData;
            return MaterialPageRoute(
              builder: (_) => ConfirmInfoPage(signupData: args),
            );
          default:
            return null;
        }
      },
    );
  }
}
