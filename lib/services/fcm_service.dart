import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// FCM Service - Handles Firebase Cloud Messaging for push notifications
///
/// This service manages:
/// - FCM token registration and updates
/// - Notification permissions
/// - Token storage in Supabase
/// - Parent account token retrieval
class FCMService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  String? _currentToken;
  String? get currentToken => _currentToken;

  /// Initialize FCM and request permissions
  Future<void> initialize() async {
    try {
      debugPrint('🔔 Initializing FCM Service...');

      // Request notification permissions
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true, // iOS critical alerts
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ Notification permissions granted');

        // Get FCM token
        String? token = await _fcm.getToken();
        _currentToken = token;
        if (token != null) {
          await _saveFCMToken(token);
          final preview = token.length > 20 ? token.substring(0, 20) : token;
          debugPrint('FCM token registered: $preview...');
        }

        // Listen for token refresh
        _fcm.onTokenRefresh.listen((newToken) {
          debugPrint('🔄 FCM token refreshed');
          _currentToken = newToken;
          _saveFCMToken(newToken);
        });

        // Configure foreground notification presentation (iOS)
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        debugPrint('⚠️ Provisional notification permissions granted');
      } else {
        debugPrint('❌ Notification permissions denied');
      }
    } catch (e) {
      debugPrint('❌ Error initializing FCM: $e');
    }
  }

  /// Save FCM token to Supabase database
  Future<void> _saveFCMToken(String token) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('⚠️ Cannot save FCM token: User not authenticated');
        return;
      }

      final deviceId = await _getDeviceId();
      final deviceName = await _getDeviceName();
      final platform = Platform.isAndroid ? 'android' : 'ios';

      debugPrint('💾 Saving FCM token to database...');

      await _supabase.from('user_fcm_tokens').upsert({
        'user_id': userId,
        'fcm_token': token,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'updated_at': DateTime.now().toIso8601String(),
        'last_used_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,device_id');

      debugPrint('✅ FCM token saved successfully');
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }

  /// Get unique device ID
  Future<String> _getDeviceId() async {
    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.id; // Android ID
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'unknown_ios';
      }
    } catch (e) {
      debugPrint('⚠️ Error getting device ID: $e');
    }
    return 'unknown_device';
  }

  /// Get device name
  Future<String> _getDeviceName() async {
    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        return '${iosInfo.name} (${iosInfo.model})';
      }
    } catch (e) {
      debugPrint('⚠️ Error getting device name: $e');
    }
    return 'Unknown Device';
  }

  /// Get parent account FCM tokens for a child user
  Future<List<Map<String, dynamic>>> getParentFCMTokens(
      String childUserId) async {
    try {
      debugPrint('🔍 Fetching parent FCM tokens for child: $childUserId');

      final result = await _supabase
          .rpc('get_parent_fcm_tokens', params: {'child_user_id': childUserId});

      if (result is List) {
        debugPrint('✅ Found ${result.length} parent device(s)');
        return List<Map<String, dynamic>>.from(result);
      }

      debugPrint('⚠️ No parent FCM tokens found');
      return [];
    } catch (e) {
      debugPrint('❌ Error getting parent FCM tokens: $e');
      return [];
    }
  }

  /// Delete current device's FCM token
  Future<void> deleteFCMToken() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final deviceId = await _getDeviceId();

      await _supabase
          .from('user_fcm_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('device_id', deviceId);

      // Delete FCM token from Firebase
      await _fcm.deleteToken();

      _currentToken = null;
      debugPrint('✅ FCM token deleted');
    } catch (e) {
      debugPrint('❌ Error deleting FCM token: $e');
    }
  }

  /// Update last_used_at timestamp
  Future<void> updateLastUsed() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final deviceId = await _getDeviceId();

      await _supabase
          .from('user_fcm_tokens')
          .update({'last_used_at': DateTime.now().toIso8601String()})
          .eq('user_id', userId)
          .eq('device_id', deviceId);
    } catch (e) {
      debugPrint('⚠️ Error updating last_used_at: $e');
    }
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    try {
      NotificationSettings settings = await _fcm.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      debugPrint('❌ Error checking notification settings: $e');
      return false;
    }
  }

  /// Request notification permissions (can be called again if denied)
  Future<bool> requestPermissions() async {
    try {
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );

      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      debugPrint('❌ Error requesting permissions: $e');
      return false;
    }
  }
}
