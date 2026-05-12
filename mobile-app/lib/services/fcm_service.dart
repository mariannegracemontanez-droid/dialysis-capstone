
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

class FcmService {
  static final FcmService _instance = FcmService._internal();

  factory FcmService() => _instance;

  FcmService._internal();

  final NotificationService _notificationService = NotificationService();
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  AndroidNotificationChannel? _channel;

  Future<void> initialize() async {
    await _requestPermission();
    await _initializeLocalNotifications();
    await _notificationService.saveFcmToken();

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      await _notificationService.saveFcmToken(token: token);
    });

    FirebaseMessaging.onMessage.listen((message) async {
      await _showLocalNotification(message);
    });
  }

  Future<void> _requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint('FCM permission status: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('FCM request permission error: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    try {
      await _localNotificationsPlugin.initialize(settings);
    } catch (e) {
      debugPrint('Local notifications initialization error: $e');
    }

    _channel = const AndroidNotificationChannel(
      'cure_nurture_notifications',
      'CureNurture Notifications',
      description: 'Notification channel for CureNurture FCM messages',
      importance: Importance.high,
    );

    try {
      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel!);
    } catch (e) {
      debugPrint('Create notification channel error: $e');
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final title = message.notification?.title ?? 'New notification';
    final body =
        message.notification?.body ?? message.data['message']?.toString() ?? '';

    try {
      await _localNotificationsPlugin.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel?.id ?? 'cure_nurture_notifications',
            _channel?.name ?? 'CureNurture Notifications',
            channelDescription: _channel?.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Show local notification error: $e');
    }
  }
}
