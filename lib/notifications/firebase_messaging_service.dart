import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import '../services/fcm_service.dart';
import '../widgets/parent_alert_modal.dart';

// Global navigator key for showing modals from background
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Background message handler must be a top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🔔 Background message received: ${message.messageId}');

  // Handle parent alert in background
  if (message.data['type'] == 'parent_alert') {
    await _handleParentAlertBackground(message);
  }
}

// Handle parent alert notification in background
Future<void> _handleParentAlertBackground(RemoteMessage message) async {
  debugPrint('📩 Background parent alert: ${message.data}');

  final alertType = message.data['alert_type'] ?? '';

  // Vibrate if CRITICAL
  if (alertType == 'CRITICAL') {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        debugPrint('📳 Vibrating for CRITICAL alert (background)...');
        await Vibration.vibrate(
          pattern: [
            0,
            500,
            200,
            500,
            200,
            500,
            200,
            500,
            200,
            500,
            200,
            500,
            200,
            500
          ],
        );
      }
    } catch (e) {
      debugPrint('❌ Background vibration error: $e');
    }
  }
}

class FirebaseMessagingService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static final FCMService _fcmService = FCMService();

  static Future<void> initialize() async {
    // Initialize local notifications
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create Android notification channels
    await _createNotificationChannels();

    // Set background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize FCM Service (token management)
    await _fcmService.initialize();

    // Request notification permission on Android 13+
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    }

    // iOS permissions (safe to call on Android)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    // Foreground message handling
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📩 Foreground message received: ${message.messageId}');

      // Handle parent alert notifications
      if (message.data['type'] == 'parent_alert') {
        _handleParentAlertForeground(message);
      } else {
        // Default notification handling
        final notification = message.notification;
        if (notification != null) {
          _showLocalNotification(
            notification.title ?? 'Notification',
            notification.body ?? '',
            message.data,
          );
        }
      }
    });

    // Handle tap when app opened from terminated state
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔔 Message opened app: ${message.messageId}');
      if (message.data['type'] == 'parent_alert') {
        _showParentAlertModal(message);
      }
    });

    // Check for initial message (opened from terminated state)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint(
          '🔔 App opened from notification: ${initialMessage.messageId}');
      if (initialMessage.data['type'] == 'parent_alert') {
        // Delay modal to ensure app is fully loaded
        Future.delayed(const Duration(seconds: 1), () {
          _showParentAlertModal(initialMessage);
        });
      }
    }
  }

  /// Create Android notification channels
  static Future<void> _createNotificationChannels() async {
    // Critical alerts channel
    const criticalChannel = AndroidNotificationChannel(
      'critical_alerts',
      'Critical Alerts',
      description: 'High priority critical emergency alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFFFF0000),
      showBadge: true,
    );

    // Regular alerts channel
    const regularChannel = AndroidNotificationChannel(
      'regular_alerts',
      'Regular Alerts',
      description: 'Standard emergency alerts',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    // Cancel alerts channel
    const cancelChannel = AndroidNotificationChannel(
      'cancel_alerts',
      'Cancellation Alerts',
      description: 'Emergency cancellation notifications',
      importance: Importance.defaultImportance,
      playSound: true,
      showBadge: true,
    );

    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(criticalChannel);

    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(regularChannel);

    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(cancelChannel);
  }

  /// Handle parent alert in foreground
  static Future<void> _handleParentAlertForeground(
      RemoteMessage message) async {
    debugPrint('📩 Foreground parent alert received');

    final alertType = message.data['alert_type'] ?? '';

    // Vibrate if CRITICAL
    if (alertType == 'CRITICAL') {
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          debugPrint('📳 Vibrating for CRITICAL alert...');
          await Vibration.vibrate(
            pattern: [
              0,
              500,
              200,
              500,
              200,
              500,
              200,
              500,
              200,
              500,
              200,
              500,
              200,
              500
            ],
          );
        }
      } catch (e) {
        debugPrint('❌ Vibration error: $e');
      }
    }

    // Show modal immediately
    _showParentAlertModal(message);

    // Also show system notification
    _showLocalNotification(
      message.notification?.title ?? _getAlertTitle(alertType),
      message.notification?.body ?? _getAlertBody(message.data),
      message.data,
      alertType: alertType,
    );
  }

  /// Show parent alert modal
  static void _showParentAlertModal(RemoteMessage message) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('⚠️ No context available for modal');
      return;
    }

    final data = message.data;
    final alertType = data['alert_type'] ?? 'REGULAR';
    final childName = data['child_name'] ?? 'Emergency Contact';
    final formattedDate = data['formatted_date'] ?? '';
    final formattedTime = data['formatted_time'] ?? '';
    final address = data['address'] ?? 'Location unavailable';
    final latitude = double.tryParse(data['latitude'] ?? '');
    final longitude = double.tryParse(data['longitude'] ?? '');
    final childPhone = data['child_phone'] ?? '';

    debugPrint('🎯 Showing parent alert modal for $alertType');

    showDialog(
      context: context,
      barrierDismissible: alertType != 'CRITICAL',
      builder: (context) => ParentAlertModal(
        alertType: alertType,
        childName: childName,
        formattedDate: formattedDate,
        formattedTime: formattedTime,
        address: address,
        latitude: latitude,
        longitude: longitude,
        childPhone: childPhone,
      ),
    );
  }

  /// Show local notification
  static Future<void> _showLocalNotification(
    String title,
    String body,
    Map<String, dynamic> data, {
    String? alertType,
  }) async {
    final type = alertType ?? data['alert_type'] ?? 'REGULAR';
    final channelId = _getChannelId(type);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      _getChannelName(type),
      importance: type == 'CRITICAL' ? Importance.max : Importance.high,
      priority: type == 'CRITICAL' ? Priority.max : Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: type == 'CRITICAL',
      enableLights: true,
      ledColor: type == 'CRITICAL'
          ? const Color(0xFFFF0000)
          : const Color(0xFFFF9800),
      playSound: true,
      fullScreenIntent: type == 'CRITICAL',
      category: AndroidNotificationCategory.alarm,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
      payload: data.toString(),
    );
  }

  /// Notification tapped callback
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('🔔 Notification tapped: ${response.payload}');
    // Handle notification tap if needed
  }

  /// Get channel ID based on alert type
  static String _getChannelId(String alertType) {
    switch (alertType.toUpperCase()) {
      case 'CRITICAL':
        return 'critical_alerts';
      case 'CANCEL':
        return 'cancel_alerts';
      default:
        return 'regular_alerts';
    }
  }

  /// Get channel name
  static String _getChannelName(String alertType) {
    switch (alertType.toUpperCase()) {
      case 'CRITICAL':
        return 'Critical Alerts';
      case 'CANCEL':
        return 'Cancellation Alerts';
      default:
        return 'Regular Alerts';
    }
  }

  /// Get alert title
  static String _getAlertTitle(String alertType) {
    switch (alertType.toUpperCase()) {
      case 'CRITICAL':
        return '🚨 CRITICAL EMERGENCY';
      case 'CANCEL':
        return '✅ Alert Cancelled';
      default:
        return '⚠️ Emergency Alert';
    }
  }

  /// Get alert body
  static String _getAlertBody(Map<String, dynamic> data) {
    final childName = data['child_name'] ?? 'Emergency Contact';
    final time = data['formatted_time'] ?? '';
    return '$childName at $time';
  }

  static Future<String?> getToken() => _messaging.getToken();
}
