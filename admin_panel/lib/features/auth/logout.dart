import 'package:flutter/material.dart';

import 'login_page.dart';

/// Signs the admin out of the panel.
///
/// This is the Dashboard's existing logout, lifted into one place so the
/// Patients page can use the *same* implementation rather than growing a
/// second one. The behaviour is unchanged: it clears the navigation stack
/// back to the login page with a fade. No authentication logic lives here
/// and none was added - the Supabase session is handled exactly as it was
/// before.
void adminLogout(BuildContext context) {
  Navigator.pushAndRemoveUntil(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          const LoginPage(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
    (route) => false,
  );
}
