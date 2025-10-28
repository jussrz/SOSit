import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParentNotificationService {
  static final ParentNotificationService _instance =
      ParentNotificationService._internal();
  factory ParentNotificationService() => _instance;
  ParentNotificationService._internal();

  final supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  RealtimeChannel? _notificationChannel;

  bool _isInitialized = false;
  Function()? _onNewNotificationCallback;
  
  // Connectivity & offline polling
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _pollingTimer;
  DateTime? _lastFetchTime;
  static const String _lastFetchKey = 'parent_last_notification_fetch';

  /// Initialize notification service and start listening
  Future<void> initialize({Function()? onNewNotification}) async {
    _onNewNotificationCallback = onNewNotification;
    if (_isInitialized) {
      debugPrint('🔔 Parent Notification Service already initialized');
      return;
    }

    debugPrint('🔔 Initializing Parent Notification Service...');

    // Load last fetch time
    await _loadLastFetchTime();

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

    await _notifications.initialize(initSettings);

    // Start listening for notifications
    await _startRealtimeSubscription();
    
    // Setup connectivity listener for offline recovery
    _setupConnectivityListener();
    
    // Fetch any missed notifications immediately
    await _fetchMissedNotifications();

    _isInitialized = true;
    debugPrint('Parent Notification Service initialized');
  }

  /// Start Supabase Realtime subscription for parent_notifications
  Future<void> _startRealtimeSubscription() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('Cannot start notification subscription: No user logged in');
      return;
    }

    debugPrint('Starting Realtime subscription for user: $userId');

    // Create channel name with user ID
    final channelName = 'parent_notifications_$userId';

    // Remove existing channel if any
    if (_notificationChannel != null) {
      await supabase.removeChannel(_notificationChannel!);
      _notificationChannel = null;
    }

    // Create new channel
    _notificationChannel = supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'parent_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'parent_user_id',
            value: userId,
          ),
          callback: (payload) {
            debugPrint('NEW NOTIFICATION RECEIVED FROM REALTIME!!! 🔔🔔🔔');
            debugPrint('Event Type: ${payload.eventType}');
            debugPrint('Table: ${payload.table}');
            debugPrint('Schema: ${payload.schema}');
            debugPrint('Old Record: ${payload.oldRecord}');
            debugPrint('New Record: ${payload.newRecord}');
            debugPrint('Commit Timestamp: ${payload.commitTimestamp}');

            if (payload.newRecord.isNotEmpty) {
              debugPrint('Calling _handleNewNotification...');
              _handleNewNotification(payload.newRecord);
            } else {
              debugPrint('WARNING: payload.newRecord is EMPTY!');
            }
          },
        )
        .subscribe((status, error) {
      debugPrint('Realtime subscription status: $status');
      if (error != null) {
        debugPrint('REALTIME ERROR: $error');
      }
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint('SUCCESSFULLY SUBSCRIBED to parent_notifications!');
      } else if (status == RealtimeSubscribeStatus.channelError) {
        debugPrint('REALTIME SUBSCRIPTION ERROR!');
      }
    });

    debugPrint('Realtime subscription active on channel: $channelName');
  }
  
  /// Setup connectivity listener to fetch missed notifications when back online
  void _setupConnectivityListener() {
    _connectivity.checkConnectivity().then((result) {
      if (result != ConnectivityResult.none) {
        _fetchMissedNotifications();
      }
    }).catchError((e) {
      debugPrint('Connectivity check failed: $e');
    });

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        debugPrint('🌐 Connection restored - fetching missed notifications');
        _fetchMissedNotifications();
      }
    });
  }
  
  /// Load last fetch timestamp from storage
  Future<void> _loadLastFetchTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getString(_lastFetchKey);
      if (timestamp != null) {
        _lastFetchTime = DateTime.parse(timestamp);
        debugPrint('📅 Last notification fetch: $_lastFetchTime');
      } else {
        // Default to 24 hours ago if no previous fetch
        _lastFetchTime = DateTime.now().subtract(const Duration(hours: 24));
      }
    } catch (e) {
      debugPrint('Error loading last fetch time: $e');
      _lastFetchTime = DateTime.now().subtract(const Duration(hours: 24));
    }
  }
  
  /// Save last fetch timestamp
  Future<void> _saveLastFetchTime(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastFetchKey, time.toIso8601String());
      _lastFetchTime = time;
    } catch (e) {
      debugPrint('Error saving last fetch time: $e');
    }
  }
  
  /// Fetch notifications that were missed while offline
  Future<void> _fetchMissedNotifications() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('Cannot fetch notifications: No user logged in');
        return;
      }

      final fetchTime = DateTime.now();
      
      debugPrint('🔄 Fetching missed notifications since $_lastFetchTime');

      // Query parent_notifications table for unread notifications
      final response = await supabase
          .from('parent_notifications')
          .select()
          .eq('parent_user_id', userId)
          .gte('created_at', _lastFetchTime!.toIso8601String())
          .order('created_at', ascending: false);

      final List<dynamic> notifications = response as List<dynamic>;
      
      if (notifications.isEmpty) {
        debugPrint('✅ No missed notifications');
      } else {
        debugPrint('📬 Found ${notifications.length} missed notification(s)');
        
        // Show each missed notification
        for (final notification in notifications.reversed) {
          final notificationMap = notification as Map<String, dynamic>;
          _handleNewNotification(notificationMap);
          
          // Small delay between notifications to avoid overwhelming user
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      
      // Update last fetch time
      await _saveLastFetchTime(fetchTime);
      
    } catch (e) {
      debugPrint('❌ Error fetching missed notifications: $e');
    }
  }

  /// Handle incoming notification from Realtime
  void _handleNewNotification(Map<String, dynamic> notification) {
    debugPrint('_handleNewNotification CALLED!');
    debugPrint('Processing notification: ${notification['id']}');
    debugPrint('Notification data: $notification');

    final alertType = notification['alert_type'] as String;
    final title = notification['notification_title'] as String;
    final body = notification['notification_body'] as String;
    // final data = notification['notification_data'] as Map<String, dynamic>;

    debugPrint('Alert Type: $alertType');
    debugPrint('Title: $title');
    debugPrint('Body: $body');

    // Show local notification
    debugPrint('Calling _showLocalNotification...');
    _showLocalNotification(
      id: notification['id'].hashCode,
      title: title,
      body: body,
      isCritical: alertType == 'CRITICAL',
    );

    // If critical, trigger vibration
    if (alertType == 'CRITICAL') {
      debugPrint('CRITICAL ALERT - Triggering vibration');
      // Vibration will be handled by local notification channel
    }

    debugPrint('Notification displayed: $title');

    // Notify dashboard to refresh
    if (_onNewNotificationCallback != null) {
      debugPrint('Calling dashboard refresh callback...');
      _onNewNotificationCallback!();
    }
  }

  /// Show local notification
  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    required bool isCritical,
  }) async {
    debugPrint('_showLocalNotification CALLED!');
    debugPrint('ID: $id');
    debugPrint('Title: $title');
    debugPrint('Body: $body');
    debugPrint('Is Critical: $isCritical');

    final androidDetails = AndroidNotificationDetails(
      isCritical ? 'critical_alerts' : 'regular_alerts',
      isCritical ? 'Critical Alerts' : 'Regular Alerts',
      channelDescription: isCritical
          ? 'Critical emergency alerts requiring immediate attention'
          : 'Regular emergency notifications',
      importance: isCritical ? Importance.max : Importance.high,
      priority: isCritical ? Priority.max : Priority.high,
      enableVibration: true,
      vibrationPattern: isCritical
          ? Int64List.fromList(
              [0, 1000, 500, 1000, 500, 1000, 500, 1000, 500, 1000])
          : Int64List.fromList([0, 500, 250, 500]),
      playSound: true,
      // Using default notification sound (no custom sound file needed)
    );

    debugPrint('Android notification details created');

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    debugPrint('📱 Showing notification now...');

    try {
      await _notifications.show(
        id,
        title,
        body,
        notificationDetails,
      );
      debugPrint('NOTIFICATION SHOWN SUCCESSFULLY!');
    } catch (e) {
      debugPrint('ERROR SHOWING NOTIFICATION: $e');
    }
  }

  /// Stop listening for notifications
  Future<void> dispose() async {
    debugPrint('🔔 Stopping Parent Notification Service...');

    if (_notificationChannel != null) {
      await supabase.removeChannel(_notificationChannel!);
      _notificationChannel = null;
    }
    
    _connectivitySubscription?.cancel();
    _pollingTimer?.cancel();

    _isInitialized = false;
    debugPrint('Parent Notification Service stopped');
  }

  /// Restart subscription (useful after login/logout)
  Future<void> restart() async {
    debugPrint('Restarting Parent Notification Service...');
    await dispose();
    await initialize();
  }
}
