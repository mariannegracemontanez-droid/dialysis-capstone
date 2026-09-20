
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
  bool _localNotificationsReady = false;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _initializeLocalNotifications();
    await _requestPermission();
    await _notificationService.saveFcmToken();

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      await _notificationService.saveFcmToken(token: token);
    });

    FirebaseMessaging.onMessage.listen((message) async {
      await _showLocalNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Notification tapped: ${message.messageId}');
    });
  }

  /// Shows a system notification directly, without needing an incoming FCM
  /// [RemoteMessage] — used for notifications this app creates for the
  /// current device itself (e.g. water intake alerts, schedule reminders),
  /// so the user sees a real phone notification, not just an in-app row.
  Future<void> showLocalNotification({
    required String title,
    required String body,
  }) async {
    await initialize();

    try {
      await _localNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
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

    // Android 13+ requires this separate runtime permission for any
    // notification (local or push) to actually be allowed to show.
    try {
      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Android notification permission request error: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsReady) return;
    _localNotificationsReady = true;

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
