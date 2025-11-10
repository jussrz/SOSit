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

// Helper functions for background handlers (must be top-level)
String _getChannelId(String alertType) {
  switch (alertType.toUpperCase()) {
    case 'CRITICAL':
      return 'critical_alerts';
    case 'CANCEL':
      return 'cancel_alerts';
    default:
      return 'regular_alerts';
  }
}

String _getChannelName(String alertType) {
  switch (alertType.toUpperCase()) {
    case 'CRITICAL':
      return 'Critical Alerts';
    case 'CANCEL':
      return 'Cancellation Alerts';
    default:
      return 'Regular Alerts';
  }
}

String _getAlertTitle(String alertType) {
  switch (alertType.toUpperCase()) {
    case 'CRITICAL':
      return '🚨 CRITICAL EMERGENCY';
    case 'CANCEL':
      return '✅ Alert Cancelled';
    default:
      return '⚠️ Emergency Alert';
  }
}

String _getAlertBody(Map<String, dynamic> data) {
  final childName = data['child_name'] ?? 'Emergency Contact';
  final time = data['formatted_time'] ?? '';
  return '$childName at $time';
}

// Background message handler must be a top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🔔 Background message received: ${message.messageId}');

  // Initialize local notifications for background handling
  final FlutterLocalNotificationsPlugin localNotifications =
      FlutterLocalNotificationsPlugin();
  
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await localNotifications.initialize(initSettings);

  final messageType = message.data['type'] ?? '';
  
  // Handle different message types in background
  if (messageType == 'parent_alert') {
    await _handleParentAlertBackground(message, localNotifications);
  } else if (messageType == 'station_alert' || 
             messageType == 'police_alert' || 
             messageType == 'tanod_alert') {
    await _handleStationAlertBackground(message, localNotifications);
  } else if (messageType == 'emergency_alert') {
    await _handleEmergencyAlertBackground(message, localNotifications);
  } else {
    // Generic notification handling
    await _handleGenericNotificationBackground(message, localNotifications);
  }
}

// Handle parent alert notification in background
Future<void> _handleParentAlertBackground(RemoteMessage message, FlutterLocalNotificationsPlugin localNotifications) async {
  debugPrint('📩 Background parent alert: ${message.data}');

  final alertType = message.data['alert_type'] ?? '';
  final childName = message.data['child_name'] ?? 'Emergency Contact';
  final formattedTime = message.data['formatted_time'] ?? '';
  final address = message.data['address'] ?? 'Location unavailable';

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

  // Show notification in background
  final title = _getAlertTitle(alertType);
  final body = '$childName at $formattedTime\n$address';
  await _showBackgroundNotification(localNotifications, title, body, message.data, alertType);
}

// Handle station (police/tanod) alert notification in background
Future<void> _handleStationAlertBackground(RemoteMessage message, FlutterLocalNotificationsPlugin localNotifications) async {
  debugPrint('📩 Background station alert: ${message.data}');

  final alertType = message.data['alert_type'] ?? 'REGULAR';
  final childName = message.data['child_name'] ?? 'Citizen';
  final address = message.data['address'] ?? 'Location updating...';
  final distance = message.data['distance_km'] ?? '';

  // Vibrate for CRITICAL alerts
  if (alertType == 'CRITICAL') {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        debugPrint('📳 Vibrating for CRITICAL station alert (background)...');
        await Vibration.vibrate(
          pattern: [0, 500, 200, 500, 200, 500, 200, 500],
        );
      }
    } catch (e) {
      debugPrint('❌ Background vibration error: $e');
    }
  }

  final title = _getAlertTitle(alertType);
  final body = '$childName needs help!\n$address${distance.isNotEmpty ? "\n~$distance km away" : ""}';
  await _showBackgroundNotification(localNotifications, title, body, message.data, alertType);
}

// Handle generic emergency alert in background
Future<void> _handleEmergencyAlertBackground(RemoteMessage message, FlutterLocalNotificationsPlugin localNotifications) async {
  debugPrint('📩 Background emergency alert: ${message.data}');

  final alertType = message.data['alert_type'] ?? 'REGULAR';
  final title = message.notification?.title ?? _getAlertTitle(alertType);
  final body = message.notification?.body ?? 'Emergency alert received';

  // Vibrate for CRITICAL alerts
  if (alertType == 'CRITICAL') {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        await Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
      }
    } catch (e) {
      debugPrint('❌ Background vibration error: $e');
    }
  }

  await _showBackgroundNotification(localNotifications, title, body, message.data, alertType);
}

// Handle generic notification in background
Future<void> _handleGenericNotificationBackground(RemoteMessage message, FlutterLocalNotificationsPlugin localNotifications) async {
  debugPrint('📩 Background generic notification: ${message.data}');

  final title = message.notification?.title ?? 'Notification';
  final body = message.notification?.body ?? 'You have a new notification';
  final alertType = message.data['alert_type'] ?? 'REGULAR';

  await _showBackgroundNotification(localNotifications, title, body, message.data, alertType);
}

// Show notification in background mode
Future<void> _showBackgroundNotification(
  FlutterLocalNotificationsPlugin localNotifications,
  String title,
  String body,
  Map<String, dynamic> data,
  String alertType,
) async {
  final channelId = _getChannelId(alertType);
  
  final androidDetails = AndroidNotificationDetails(
    channelId,
    _getChannelName(alertType),
    importance: alertType == 'CRITICAL' ? Importance.max : Importance.high,
    priority: alertType == 'CRITICAL' ? Priority.max : Priority.high,
    icon: '@mipmap/ic_launcher',
    enableVibration: true,
    enableLights: true,
    ledColor: alertType == 'CRITICAL'
        ? const Color(0xFFFF0000)
        : const Color(0xFFFF9800),
    playSound: true,
    fullScreenIntent: alertType == 'CRITICAL',
    category: AndroidNotificationCategory.alarm,
    // Force heads-up notification display
    visibility: NotificationVisibility.public,
    showWhen: true,
    ticker: title, // Shows in status bar
    autoCancel: false, // Don't dismiss on tap
    ongoing: alertType == 'CRITICAL', // Make critical alerts persistent
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: title,
      summaryText: alertType == 'CRITICAL' ? 'EMERGENCY' : 'Alert',
    ),
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

  await localNotifications.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    notificationDetails,
    payload: data.toString(),
  );
  
  debugPrint('✅ Background notification shown: $title');
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

    // Configure foreground notification presentation (iOS)
    // This tells FCM to NOT automatically show notifications in foreground
    // We'll show them manually using flutter_local_notifications
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground message handling
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📩 Foreground message received: ${message.messageId}');

      final messageType = message.data['type'] ?? '';

      // Handle different message types in foreground
      if (messageType == 'parent_alert') {
        _handleParentAlertForeground(message);
      } else if (messageType == 'station_alert' || 
                 messageType == 'police_alert' || 
                 messageType == 'tanod_alert') {
        _handleStationAlertForeground(message);
      } else if (messageType == 'emergency_alert') {
        _handleEmergencyAlertForeground(message);
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

  /// Handle station (police/tanod) alert in foreground
  static Future<void> _handleStationAlertForeground(
      RemoteMessage message) async {
    debugPrint('📩 Foreground station alert received');
    debugPrint('📦 Station alert data: ${message.data}');

    final alertType = message.data['alert_type'] ?? 'REGULAR';
    final childName = message.data['child_name'] ?? 'Citizen';
    final address = message.data['address'] ?? 'Location updating...';
    final distance = message.data['distance_km'] ?? '';

    debugPrint('🔔 Preparing to show notification for station alert...');
    debugPrint('   Alert Type: $alertType');
    debugPrint('   Child: $childName');
    debugPrint('   Address: $address');

    // Vibrate if CRITICAL
    if (alertType == 'CRITICAL') {
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          debugPrint('📳 Vibrating for CRITICAL station alert...');
          await Vibration.vibrate(
            pattern: [0, 500, 200, 500, 200, 500, 200, 500],
          );
        }
      } catch (e) {
        debugPrint('❌ Vibration error: $e');
      }
    }

    // Show notification
    final title = _getAlertTitle(alertType);
    final body = '$childName needs help!\n$address${distance.isNotEmpty ? "\n~$distance km away" : ""}';
    
    debugPrint('🔔 Calling _showLocalNotification...');
    debugPrint('   Title: $title');
    debugPrint('   Body: $body');
    
    await _showLocalNotification(
      title,
      body,
      message.data,
      alertType: alertType,
    );
    
    debugPrint('✅ _showLocalNotification completed');
  }

  /// Handle emergency alert in foreground
  static Future<void> _handleEmergencyAlertForeground(
      RemoteMessage message) async {
    debugPrint('📩 Foreground emergency alert received');

    final alertType = message.data['alert_type'] ?? 'REGULAR';

    // Vibrate if CRITICAL
    if (alertType == 'CRITICAL') {
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          debugPrint('📳 Vibrating for CRITICAL emergency alert...');
          await Vibration.vibrate(
            pattern: [0, 500, 200, 500, 200, 500],
          );
        }
      } catch (e) {
        debugPrint('❌ Vibration error: $e');
      }
    }

    // Show notification
    final title = message.notification?.title ?? _getAlertTitle(alertType);
    final body = message.notification?.body ?? 'Emergency alert received';
    _showLocalNotification(
      title,
      body,
      message.data,
      alertType: alertType,
    );
  }

  /// Show local notification
  static Future<void> _showLocalNotification(
    String title,
    String body,
    Map<String, dynamic> data, {
    String? alertType,
  }) async {
    debugPrint('🔔 _showLocalNotification called');
    debugPrint('   Title: $title');
    debugPrint('   Body: $body');
    debugPrint('   Alert Type: $alertType');
    
    final type = alertType ?? data['alert_type'] ?? 'REGULAR';
    final channelId = _getChannelId(type);

    debugPrint('   Using channel: $channelId');

    final androidDetails = AndroidNotificationDetails(
      channelId,
      _getChannelName(type),
      importance: type == 'CRITICAL' ? Importance.max : Importance.high,
      priority: type == 'CRITICAL' ? Priority.max : Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      enableLights: true,
      ledColor: type == 'CRITICAL'
          ? const Color(0xFFFF0000)
          : const Color(0xFFFF9800),
      playSound: true,
      fullScreenIntent: type == 'CRITICAL',
      category: AndroidNotificationCategory.alarm,
      // Force heads-up notification display
      visibility: NotificationVisibility.public,
      showWhen: true,
      ticker: title, // Shows in status bar
      autoCancel: false, // Don't dismiss on tap
      ongoing: type == 'CRITICAL', // Make critical alerts persistent
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: type == 'CRITICAL' ? 'EMERGENCY' : 'Alert',
      ),
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

    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    debugPrint('   Notification ID: $notificationId');

    try {
      await _localNotificationsPlugin.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: data.toString(),
      );
      debugPrint('✅ Local notification shown successfully!');
    } catch (e) {
      debugPrint('❌ Error showing local notification: $e');
    }
  }

  /// Notification tapped callback
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('🔔 Notification tapped: ${response.payload}');
    // Handle notification tap if needed
  }

  static Future<String?> getToken() => _messaging.getToken();
}
