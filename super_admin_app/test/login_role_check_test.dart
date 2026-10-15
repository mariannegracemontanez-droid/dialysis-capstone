import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:super_admin_app/pages/login_page_v2.dart';

User _user({
  Map<String, dynamic> appMetadata = const {},
  Map<String, dynamic>? userMetadata,
}) {
  return User(
    id: 'user-1',
    appMetadata: appMetadata,
    userMetadata: userMetadata,
    aud: 'authenticated',
    createdAt: '2026-10-13T00:00:00Z',
  );
}

void main() {
  group('isSuperAdminAccount', () {
    test('accepts superadmin from profiles.role', () {
      expect(isSuperAdminAccount(_user(), 'superadmin'), isTrue);
      expect(isSuperAdminAccount(_user(), ' SuperAdmin '), isTrue);
    });

    test('accepts superadmin from server-set app_metadata', () {
      expect(
        isSuperAdminAccount(_user(appMetadata: {'role': 'superadmin'}), null),
        isTrue,
      );
    });

    test('ignores self-editable user_metadata', () {
      final user = _user(userMetadata: {'role': 'superadmin'});

      expect(isSuperAdminAccount(user, null), isFalse);
      expect(isSuperAdminAccount(user, 'patient'), isFalse);
    });

    test('rejects other roles and a missing role', () {
      expect(isSuperAdminAccount(_user(), 'admin'), isFalse);
      expect(isSuperAdminAccount(_user(), 'patient'), isFalse);
      expect(isSuperAdminAccount(_user(), null), isFalse);
      expect(isSuperAdminAccount(_user(), ''), isFalse);
    });
  });
}
