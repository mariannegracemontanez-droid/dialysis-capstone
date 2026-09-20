import 'package:shared_preferences/shared_preferences.dart';

/// Per-device notification preferences (e.g. from the Privacy & Security
/// page's "Login Notifications" toggle). Stored locally, not per-account,
/// since it's just a noise preference rather than a security setting.
class NotificationPreferencesService {
  static const _loginNotificationsKey = 'login_notifications_enabled';

  Future<bool> isLoginNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loginNotificationsKey) ?? false;
  }

  Future<void> setLoginNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loginNotificationsKey, enabled);
  }
}
