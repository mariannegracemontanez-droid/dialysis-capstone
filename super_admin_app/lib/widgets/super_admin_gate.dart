import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../pages/login_page_v2.dart';

/// Builds [child] only once the restored session is confirmed to belong to a
/// superadmin; otherwise shows [fallback] (Login).
///
/// The `/dashboard` route is reachable directly by URL on web, and a stored
/// session only proves that SOME user signed in -- a center admin, patient or
/// donor of the same Supabase project would pass a bare session check. The
/// login form verifies the role, but restoring a session skips the form, so
/// the same check is repeated here.
///
/// This is a UI guard only. What the account can actually read or change is
/// decided by the database's RLS policies.
class SuperAdminGate extends StatefulWidget {
  const SuperAdminGate({
    super.key,
    required this.child,
    required this.fallback,
    this.verify = verifyCurrentUserIsSuperAdmin,
  });

  final Widget child;
  final Widget fallback;

  /// Resolves to true for a superadmin, false for any other account. A thrown
  /// error (e.g. network failure) also shows [fallback], without signing out.
  final Future<bool> Function() verify;

  @override
  State<SuperAdminGate> createState() => _SuperAdminGateState();
}

class _SuperAdminGateState extends State<SuperAdminGate> {
  late final Future<bool> _verified = widget.verify();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _verified,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return snapshot.data == true ? widget.child : widget.fallback;
      },
    );
  }
}

/// Default [SuperAdminGate.verify]: reads the signed-in user's
/// `profiles.role` and applies the same rule as the login form. A confirmed
/// non-superadmin session is signed out so it is not kept around.
Future<bool> verifyCurrentUserIsSuperAdmin() async {
  final client = SupabaseConfig.client;
  final user = client.auth.currentUser;
  if (user == null) return false;

  final profile = await client
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();

  if (isSuperAdminAccount(user, profile?['role'])) return true;

  await client.auth.signOut();
  return false;
}
