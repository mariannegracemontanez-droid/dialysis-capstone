import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/login_history.dart';
import 'device_info_service.dart';

class LoginHistoryService {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final DeviceInfoService _deviceInfoService = DeviceInfoService();

  /// Record a login attempt with device information
  Future<void> recordLogin(String userId) async {
    try {
      final deviceInfo = await _deviceInfoService.getDeviceInfo();

      await _supabase.from('login_history').insert({
        'user_id': userId,
        'login_time': DateTime.now().toIso8601String(),
        'device_brand': deviceInfo['brand'],
        'device_model': deviceInfo['model'],
        'device_type': deviceInfo['type'],
      });
    } catch (e) {
      // Silently fail to not interrupt login process
      print('Failed to record login: $e');
    }
  }

  /// Get login history for a user
  Future<List<LoginHistory>> getLoginHistory(String userId) async {
    try {
      final data = await _supabase
          .from('login_history')
          .select()
          .eq('user_id', userId)
          .order('login_time', ascending: false)
          .limit(50);

      return List<LoginHistory>.from(
        data.map((item) => LoginHistory.fromJson(item)),
      );
    } catch (e) {
      throw Exception('Failed to fetch login history: $e');
    }
  }

  /// Get the current device information formatted for display
  Future<String> getCurrentDeviceDisplayName() async {
    final deviceInfo = await _deviceInfoService.getDeviceInfo();
    return deviceInfo['displayName'] ?? 'Unknown Device';
  }
}
