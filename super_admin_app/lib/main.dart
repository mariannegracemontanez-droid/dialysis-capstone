import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'pages/dashboard_page.dart';
import 'pages/login_page_v2.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "assets/.env");
  await SupabaseConfig.initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  final String? initError;

  const MyApp({super.key, this.initError});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  /// Owned by the app itself so the auth listener below can navigate without
  /// borrowing any page's BuildContext -- the page that was open when the
  /// session died may be gone by the time we react.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<AuthState>? _authSubscription;

  /// Stops a burst of sign-out events from each pushing their own redirect.
  /// Cleared again as soon as a real session exists, so a later sign-out still
  /// redirects.
  bool _redirectingToLogin = false;

  @override
  void initState() {
    super.initState();

    // Subscribed once here, never in build(), so a rebuild cannot stack up a
    // second listener. Skipped entirely when Supabase failed to initialise --
    // that build has no routes to navigate to.
    if (widget.initError == null) {
      _listenForSignOut();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Sends the Super Admin back to Login when the session actually ends, so a
  /// dashboard that is ALREADY OPEN cannot keep sitting there after the
  /// session is gone -- previously nothing noticed, and the page stayed up
  /// while its queries quietly started failing.
  ///
  /// Only `signedOut` is acted on. `signedIn`, `tokenRefreshed`, `userUpdated`
  /// and `initialSession` are ignored on purpose, which is what keeps this
  /// clear of the R3 account-creation mitigation: creating a head nurse emits
  /// `signedIn` (from signUp) and then `signedIn`/`tokenRefreshed` (from the
  /// setSession restore), so the Super Admin is never bounced mid-creation.
  ///
  /// GoTrue emits `signedOut` both on an explicit signOut() and when a token
  /// refresh fails non-retryably -- i.e. genuine session loss -- which is
  /// exactly the set of cases that should land on Login.
  void _listenForSignOut() {
    _authSubscription = SupabaseConfig.client.auth.onAuthStateChange.listen((
      authState,
    ) {
      if (authState.event == AuthChangeEvent.signedOut) {
        _redirectToLogin();
      } else if (authState.session != null) {
        _redirectingToLogin = false;
      }
    });
  }

  void _redirectToLogin() {
    if (_redirectingToLogin) return;

    // Null before the first frame, or once the app is torn down.
    final navigator = _navigatorKey.currentState;
    if (navigator == null || !mounted) return;

    _redirectingToLogin = true;

    // Clears the whole stack, so the protected dashboard cannot be reached by
    // going Back, and exactly one Login route remains.
    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  /// The dashboard route's precondition. `currentSession` is a plain stored
  /// value in the SDK and does NOT consider expiry, so a session that has
  /// lapsed but not yet been cleared would still have satisfied a bare null
  /// check. Session.isExpired covers that (it also treats a token expiring
  /// within the next few seconds as expired).
  bool _hasUsableSession() {
    final session = SupabaseConfig.client.auth.currentSession;
    return session != null && !session.isExpired;
  }

  @override
  Widget build(BuildContext context) {
    final initError = widget.initError;

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
  navigatorKey: _navigatorKey,
  initialRoute: '/login',
  routes: {
    '/login': (context) => const LoginPage(),
    // Route-level session guard. This named route is reachable directly by
    // URL on web (default hash strategy, e.g. #/dashboard) and nothing
    // previously checked for a session there, so the dashboard could be
    // built unauthenticated. Building LoginPage instead closes that entry
    // point.
    //
    // The check now also rejects an EXPIRED session, not just a missing one
    // (see _hasUsableSession). This guard still only runs when the route is
    // built -- a session lost while the dashboard is already open is handled
    // by the auth listener in initState instead.
    '/dashboard': (context) =>
        _hasUsableSession() ? const DashboardPage() : const LoginPage(),
  },
);
  }
}
