import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class NotificationService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  String? get _userId => _supabase.auth.currentUser?.id;

  Future<List<Map<String, dynamic>>> getNotifications() async {
    final userId = _userId;
    if (userId == null) return [];

    try {
      final response = await _supabase
          .from('notifications')
          .select(
            'id, recipient_id, sender_id, title, message, type, is_read, created_at',
          )
          .eq('recipient_id', userId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
        } catch (e) {
      debugPrint('Get notifications error: $e');
    }

    return [];
  }

  Future<void> markAsRead(String notificationId) async {
    final userId = _userId;
    if (userId == null) return;

    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId)
          .eq('recipient_id', userId);
    } catch (e) {
      debugPrint('Mark notification as read error: $e');
    }
  }

  Future<void> createNotification({
    required String title,
    required String message,
    required String type,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    try {
      await _supabase.from('notifications').insert({
        'recipient_id': userId,
        'sender_id': null,
        'title': title,
        'message': message,
        'type': type,
      });
    } catch (e) {
      debugPrint('Create notification error: $e');
    }
  }

  Future<bool> hasNotificationOfTypeSince(String type, DateTime since) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('recipient_id', userId)
          .eq('type', type)
          .gte('created_at', since.toIso8601String())
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('Notification duplicate check error: $e');
      return false;
    }
  }

  Future<void> saveFcmToken({String? token}) async {
    final userId = _userId;
    if (userId == null) return;

    try {
      final fcmToken = token ?? await FirebaseMessaging.instance.getToken();
      if (fcmToken == null || fcmToken.isEmpty) return;

      await _supabase.from('device_tokens').upsert({
        'token': fcmToken,
        'user_id': userId,
        'platform': 'android',
      }, onConflict: 'token');
    } catch (e) {
      debugPrint('Save FCM token error: $e');
    }
  }
}
