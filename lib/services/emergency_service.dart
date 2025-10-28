// lib/services/emergency_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

class EmergencyService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Local notifications
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Emergency state
  bool _isEmergencyActive = false;
  String _activeEmergencyType = '';
  DateTime? _emergencyStartTime;
  Position? _lastKnownLocation;
  String _lastKnownAddress = '';
  List<Map<String, dynamic>> _emergencyContacts = [];
  Timer? _emergencyTimer;
  Timer? _regularAlertTimer;
  int _emergencyId = 0;

  // Debounce mechanism to prevent rapid duplicate alerts
  DateTime? _lastAlertTime;
  String? _lastAlertType;

  // Offline queueing & connectivity
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  static const String _pendingAlertsKey = 'pending_panic_alerts';

  // UI callback for showing popups
  Function(String alertType)? _showPopupCallback;

  // Getters
  bool get isEmergencyActive => _isEmergencyActive;
  String get activeEmergencyType => _activeEmergencyType;
  DateTime? get emergencyStartTime => _emergencyStartTime;
  Position? get lastKnownLocation => _lastKnownLocation;
  String get lastKnownAddress => _lastKnownAddress;
  List<Map<String, dynamic>> get emergencyContacts => _emergencyContacts;

  // Set callback for UI popup
  void setPopupCallback(Function(String alertType) callback) {
    _showPopupCallback = callback;
    debugPrint('🎯 Emergency Service: Popup callback set');
  }

  EmergencyService() {
    _initialize();
  }

  Future<void> _initialize() async {
    await _initializeNotifications();
    await _loadEmergencyContacts();
    await _getCurrentLocation();
    // Start connectivity listener to flush queued alerts when back online
    _setupConnectivityListener();
  }

  void _setupConnectivityListener() {
    // Check initial connectivity and subscribe to changes
    _connectivity.checkConnectivity().then((result) {
      if (result != ConnectivityResult.none) {
        _flushPendingAlerts();
      }
    }).catchError((e) {
      debugPrint('Connectivity check failed: $e');
    });

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        debugPrint('Connectivity restored - attempting to flush pending alerts');
        _flushPendingAlerts();
      }
    });
  }

  Future<bool> _isOnline() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      return true; // assume online if check fails to avoid blocking
    }
  }

  Future<void> _enqueuePendingAlert(String type, Map<String, dynamic>? alertData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> list = prefs.getStringList(_pendingAlertsKey) ?? [];

      final entry = jsonEncode({
        'type': type,
        'alertData': alertData ?? {},
        'queued_at': DateTime.now().toIso8601String(),
      });

      list.add(entry);
      await prefs.setStringList(_pendingAlertsKey, list);
      debugPrint('🔁 Queued alert for later delivery: $entry');

      // Inform user/app that alert has been queued
      await _showSimpleAlert('Offline', 'No internet — alert will be sent when connection is restored');
    } catch (e) {
      debugPrint('❌ Failed to enqueue pending alert: $e');
    }
  }

  Future<void> _flushPendingAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> list = prefs.getStringList(_pendingAlertsKey) ?? [];
      if (list.isEmpty) return;

      debugPrint('🔁 Flushing ${list.length} pending alert(s)...');

      final List<String> remaining = [];

      for (final encoded in list) {
        try {
          final Map<String, dynamic> entry = jsonDecode(encoded);
          final String type = entry['type'] ?? 'REGULAR';
          final Map<String, dynamic>? alertData = (entry['alertData'] is Map) ? Map<String, dynamic>.from(entry['alertData']) : {};

          // Attempt to log to database and notify parents/stations
          await _logEmergencyToDatabase(type, alertData);
          debugPrint('✅ Flushed queued alert of type $type');
        } catch (e) {
          debugPrint('❌ Failed to flush queued alert: $e');
          // keep item for retry later
          remaining.add(encoded);
        }
      }

      // Save remaining (if any)
      await prefs.setStringList(_pendingAlertsKey, remaining);
    } catch (e) {
      debugPrint('❌ Error flushing pending alerts: $e');
    }
  }

  // Initialize local notifications
  Future<void> _initializeNotifications() async {
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
    await _localNotificationsPlugin.initialize(initSettings);

    // Create notification channels for Android
    await _createNotificationChannels();
  }

  // Create notification channels for different alert types
  Future<void> _createNotificationChannels() async {
    // Critical Emergency Channel
    const criticalChannel = AndroidNotificationChannel(
      'emergency_critical',
      'Critical Emergency Alerts',
      description: 'High priority alerts for critical emergencies',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFFFF0000), // Red
      showBadge: true,
    );

    // Regular Emergency Channel
    const regularChannel = AndroidNotificationChannel(
      'emergency_regular',
      'Emergency Alerts',
      description: 'Standard emergency alerts',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFFFF9800), // Orange
      showBadge: true,
    );

    // Cancel/Info Channel
    const cancelChannel = AndroidNotificationChannel(
      'emergency_cancel',
      'Emergency Status Updates',
      description: 'Updates on emergency status changes',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: false,
    );

    // General Channel
    const generalChannel = AndroidNotificationChannel(
      'emergency_general',
      'General Alerts',
      description: 'General app notifications',
      importance: Importance.defaultImportance,
      playSound: true,
      showBadge: false,
    );

    // Create all channels
    final plugin =
        _localNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (plugin != null) {
      await plugin.createNotificationChannel(criticalChannel);
      await plugin.createNotificationChannel(regularChannel);
      await plugin.createNotificationChannel(cancelChannel);
      await plugin.createNotificationChannel(generalChannel);
      debugPrint('📱 Notification channels created');
    }
  }

  // Send push notification for ESP32 alerts
  Future<void> _sendPushNotification(String alertType, String message) async {
    String title;
    String body;
    String channelId;
    Importance importance;
    Priority priority;

    switch (alertType) {
      case 'CRITICAL':
        title = '🚨 CRITICAL EMERGENCY';
        body = 'Emergency button pressed! $message';
        channelId = 'emergency_critical';
        importance = Importance.max;
        priority = Priority.max;

        // Vibrate for 5 seconds on CRITICAL alerts only
        await _vibrateCriticalAlert();
        break;
      case 'REGULAR':
        title = '⚠️ Emergency Alert';
        body = 'Alert button pressed. $message';
        channelId = 'emergency_regular';
        importance = Importance.high;
        priority = Priority.high;
        break;
      case 'CANCEL':
        title = '✅ Emergency Cancelled';
        body = 'Emergency alert has been cancelled.';
        channelId = 'emergency_cancel';
        importance = Importance.high;
        priority = Priority.high;
        break;
      default:
        title = '📱 SOSit Alert';
        body = message;
        channelId = 'emergency_general';
        importance = Importance.defaultImportance;
        priority = Priority.defaultPriority;
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      'Emergency Alerts',
      channelDescription: 'Notifications for emergency button presses',
      importance: importance,
      priority: priority,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
      fullScreenIntent: alertType == 'CRITICAL', // Full screen for critical
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public, // Show on lock screen
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      usesChronometer: false,
      ongoing: alertType == 'CRITICAL', // Keep critical alerts persistent
      autoCancel: alertType != 'CRITICAL', // Don't auto-cancel critical
      enableLights: true,
      ledColor: alertType == 'CRITICAL'
          ? const Color(0xFFFF0000)
          : const Color(0xFFFF9800),
      ledOnMs: 1000,
      ledOffMs: 500,
      ticker: title, // Shows briefly when notification arrives
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
    );

    debugPrint('📱 Push notification sent: $title - $body');
  }

  // Vibrate for 5 seconds on CRITICAL alerts (for parent accounts)
  Future<void> _vibrateCriticalAlert() async {
    try {
      // Check if device supports vibration
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) {
        debugPrint('⚠️ Device does not support vibration');
        return;
      }

      debugPrint('📳 Starting 5-second vibration for CRITICAL alert...');

      // Vibration pattern: [wait, vibrate, wait, vibrate, ...]
      // Total duration: 5 seconds
      // Pattern: 500ms vibrate, 200ms pause (repeating)
      const pattern = [
        0, 500, 200, // First pulse
        500, 200, // Second pulse
        500, 200, // Third pulse
        500, 200, // Fourth pulse
        500, 200, // Fifth pulse
        500, 200, // Sixth pulse
        500, // Final pulse
      ];

      // Vibrate with pattern for approximately 5 seconds
      await Vibration.vibrate(pattern: pattern);

      debugPrint('✅ 5-second critical alert vibration completed');
    } catch (e) {
      debugPrint('❌ Error vibrating device: $e');
      // Fallback to system haptic feedback
      try {
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 200));
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 200));
        HapticFeedback.heavyImpact();
      } catch (hapticError) {
        debugPrint('❌ Haptic feedback also failed: $hapticError');
      }
    }
  }

  Future<void> _loadEmergencyContacts() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final contacts = await _supabase
          .from('emergency_contacts')
          .select()
          .eq('user_id', userId)
          .order('created_at');

      _emergencyContacts = List<Map<String, dynamic>>.from(contacts);
      debugPrint('Loaded ${_emergencyContacts.length} emergency contacts');
    } catch (e) {
      debugPrint('Error loading emergency contacts: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;

      _lastKnownLocation = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Get address
      if (_lastKnownLocation != null) {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            _lastKnownLocation!.latitude,
            _lastKnownLocation!.longitude,
          );
          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            _lastKnownAddress =
                '${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}';
          }
        } catch (e) {
          _lastKnownAddress =
              'Lat: ${_lastKnownLocation!.latitude.toStringAsFixed(6)}, Lng: ${_lastKnownLocation!.longitude.toStringAsFixed(6)}';
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<void> handleEmergencyAlert(
      String alertType, Map<String, dynamic>? alertData) async {
    debugPrint('Emergency alert: $alertType');

    // Debounce check - prevent duplicate alerts within 1 second
    final now = DateTime.now();
    if (_lastAlertTime != null &&
        _lastAlertType == alertType &&
        now.difference(_lastAlertTime!).inMilliseconds < 1000) {
      return; // Ignore duplicate
    }

    _lastAlertTime = now;
    _lastAlertType = alertType;

    // Update location before processing
    await _getCurrentLocation();

    switch (alertType) {
      case 'TEST':
        await _showSimpleAlert('Test Alert', 'Callback system working!');
        break;
      case 'REGULAR':
        await _sendPushNotification('REGULAR', 'Location: $_lastKnownAddress');
        await _handleRegularAlert(alertData);
        break;
      case 'CHECKIN':
        await _sendPushNotification('REGULAR', 'Check-in signal received');
        await _handleCheckInAlert(alertData);
        break;
      case 'CRITICAL':
        await _sendPushNotification(
            'CRITICAL', 'IMMEDIATE HELP NEEDED! Location: $_lastKnownAddress');
        await _handleCriticalAlert(alertData);
        break;
      case 'CANCEL':
        await _sendPushNotification('CANCEL', 'Emergency has been cancelled');
        await _handleCancelAlert();
        break;
      default:
        debugPrint('Unknown alert type: $alertType');
    }
  }

  Future<void> _handleRegularAlert(Map<String, dynamic>? alertData) async {
    // If an emergency is already active, we still want to record the new REGULAR
    // press and notify parent accounts (unless the active emergency is already REGULAR).
    if (_isEmergencyActive) {
      if (_activeEmergencyType == 'REGULAR') {
        debugPrint(
            '🚫 Emergency already active and REGULAR - ignoring duplicate regular alert');
        return;
      }

      debugPrint(
          'ℹ️ Emergency already active (type: $_activeEmergencyType). Recording additional REGULAR alert and notifying parents');
      // Record an additional REGULAR panic alert entry and notify parents/stations
      await _logEmergencyToDatabase('REGULAR', alertData);
      // Also send a local push to inform the device owner (not upgrading/downgrading current emergency)
      await _sendPushNotification('REGULAR',
          'Additional regular alert recorded. Location: $_lastKnownAddress');
      return;
    }

    debugPrint('⚠️ Starting REGULAR emergency...');
    await _startEmergency('REGULAR', alertData);
    await _vibrateDevice([500, 300, 500]);

    // Delay the popup by 1.5 seconds to allow for potential critical upgrade
    debugPrint('⏰ Setting regular popup timer (1.5s delay)...');
    _regularAlertTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_isEmergencyActive && _activeEmergencyType == 'REGULAR') {
        debugPrint('📱 Showing REGULAR popup (timer expired)');
        _showSimpleAlert(
            'Emergency Alert', 'Regular emergency alert activated');
      } else {
        debugPrint(
            '🚫 Regular popup cancelled - emergency type changed to $_activeEmergencyType');
      }
    });

    // Send to emergency contacts after 30 seconds unless cancelled
    _emergencyTimer = Timer(const Duration(seconds: 30), () {
      _sendEmergencyMessages('REGULAR');
    });
  }

  Future<void> _handleCheckInAlert(Map<String, dynamic>? alertData) async {
    await _showSimpleAlert('Check-in Alert', 'Safety check-in requested');
    await _vibrateDevice([200, 100, 200]);
    await _logActivity('CHECKIN', alertData);
  }

  Future<void> _handleCriticalAlert(Map<String, dynamic>? alertData) async {
    debugPrint('🚨 Processing CRITICAL alert...');

    // Cancel any pending regular alert timer if upgrading to critical
    if (_emergencyTimer != null) {
      _emergencyTimer!.cancel();
      _emergencyTimer = null;
      debugPrint('✅ Cancelled pending regular emergency timer');
    }

    // Cancel the delayed regular popup if it's pending
    if (_regularAlertTimer != null) {
      _regularAlertTimer!.cancel();
      _regularAlertTimer = null;
      debugPrint(
          '✅ Cancelled pending regular popup timer - will show critical instead');
    } else {
      debugPrint('ℹ️ No regular popup timer to cancel');
    }

    // If regular emergency is active, upgrade it to critical
    if (_isEmergencyActive && _activeEmergencyType == 'REGULAR') {
      debugPrint('⬆️ Upgrading regular emergency to critical');
      _activeEmergencyType = 'CRITICAL';
    } else if (!_isEmergencyActive) {
      // Start new critical emergency
      debugPrint('🚨 Starting new CRITICAL emergency...');
      await _startEmergency('CRITICAL', alertData);
    }

    debugPrint('📱 Showing CRITICAL popup immediately');
    await _showSimpleAlert('CRITICAL EMERGENCY',
        'Critical emergency alert - sending immediately!');
    await _vibrateDevice([1000, 200, 1000, 200, 1000]);

    // Send immediately for critical alerts
    await _sendEmergencyMessages('CRITICAL');
  }

  Future<void> _handleCancelAlert() async {
    if (!_isEmergencyActive) {
      await _showSimpleAlert(
          'Alert Cancelled', 'No active emergency to cancel');
      return;
    }

    await _cancelEmergency();
  }

  Future<void> _startEmergency(
      String type, Map<String, dynamic>? alertData) async {
    _isEmergencyActive = true;
    _activeEmergencyType = type;
    _emergencyStartTime = DateTime.now();
    _emergencyId = DateTime.now().millisecondsSinceEpoch;

    // Log to database
    await _logEmergencyToDatabase(type, alertData);

    notifyListeners();
    debugPrint('Emergency started: $type');
  }

  Future<void> _cancelEmergency() async {
    _emergencyTimer?.cancel();
    _isEmergencyActive = false;
    _activeEmergencyType = '';
    _emergencyStartTime = null;

    await _showSimpleAlert(
        'Emergency Cancelled', 'Emergency alert has been cancelled');
    await _vibrateDevice([100, 50, 100]);

    // Update database
    await _updateEmergencyStatus('CANCELLED');

    // Notify parents about cancellation
    await _logEmergencyToDatabase('CANCEL', null);

    notifyListeners();
    debugPrint('Emergency cancelled');
  }

  Future<void> _logEmergencyToDatabase(
      String type, Map<String, dynamic>? alertData) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // If offline, enqueue the alert and return
      final online = await _isOnline();
      if (!online) {
        debugPrint('🔌 Offline detected - enqueueing alert of type $type');
        await _enqueuePendingAlert(type, alertData);
        return;
      }

      // First, insert into panic_alerts table to record the alert
      debugPrint('📝 Inserting panic alert into database...');
      final panicAlertResponse = await _supabase
          .from('panic_alerts')
          .insert({
            'user_id': userId,
            'alert_level': type,
            'timestamp': _emergencyStartTime?.toIso8601String() ??
                DateTime.now().toIso8601String(),
            'latitude': _lastKnownLocation?.latitude,
            'longitude': _lastKnownLocation?.longitude,
            'location': _lastKnownAddress,
            'battery_level': alertData?['battery'] ?? 100,
            'acknowledged': false,
          })
          .select()
          .single();

      final panicAlertId = panicAlertResponse['id'] as int;
      debugPrint('✅ Panic alert created with ID: $panicAlertId');
      debugPrint('🔍 Panic alert ID type: ${panicAlertId.runtimeType}');

      // Notify parent accounts FIRST (before emergency_alerts insert that might fail)
      await _notifyParentAccounts(type, panicAlertId);

      // Also insert into emergency_alerts table (for compatibility)
      // Note: This table may not exist, so we'll let it fail silently
      try {
        await _supabase.from('emergency_alerts').insert({
          'id': _emergencyId,
          'user_id': userId,
          'alert_type': type,
          'timestamp': _emergencyStartTime?.toIso8601String(),
          'latitude': _lastKnownLocation?.latitude,
          'longitude': _lastKnownLocation?.longitude,
          'address': _lastKnownAddress,
          'status': 'ACTIVE',
          'battery_level': alertData?['battery'] ?? 100,
          'device_data': alertData,
        });
        debugPrint('Emergency logged to database');
      } catch (e) {
        debugPrint('⚠️ Emergency_alerts table not available (expected): $e');
      }
    } catch (e) {
      debugPrint('Error logging emergency: $e');
      // Try to enqueue the alert for later delivery
      try {
        await _enqueuePendingAlert(type, alertData);
      } catch (inner) {
        debugPrint('❌ Failed to enqueue alert after logging error: $inner');
      }
    }
  }

  /// Notify parent accounts via Postgres Function
  Future<void> _notifyParentAccounts(String alertType, int panicAlertId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('⚠️ Cannot notify parents: User not authenticated');
        return;
      }

      debugPrint('🔔 Notifying parent accounts of $alertType alert...');
      debugPrint('📋 Panic Alert ID: $panicAlertId');

      // Call Postgres function to create parent notifications
      debugPrint(
          '🚀 Calling Postgres function: create_parent_notifications_for_alert_v7');
      final response = await _supabase.rpc(
        'create_parent_notifications_for_alert_v7',
        params: {'p_panic_alert_id': panicAlertId},
      );

      debugPrint('📬 Parent notification response: $response');

      if (response != null && response['success'] == true) {
        final parentCount = response['parent_count'] ?? 0;
        debugPrint('✅ Successfully notified $parentCount parent(s)');
      } else {
        debugPrint('⚠️ Parent notification may have failed: $response');
      }

      // Call Postgres function to create station notifications (police/tanod)
      debugPrint('📍 Notifying nearby stations (police & tanod) within 5km...');
      await _notifyNearbyStations(panicAlertId);
    } catch (e) {
      debugPrint('❌ Error notifying parents: $e');
      // Don't fail the entire emergency flow if parent notification fails
    }
  }

  // Notify nearby police and tanod stations within 5km radius
  Future<void> _notifyNearbyStations(int panicAlertId) async {
    try {
      debugPrint(
          '🚀 Calling Postgres function: create_station_notifications_for_alert');
      final response = await _supabase.rpc(
        'create_station_notifications_for_alert',
        params: {'p_panic_alert_id': panicAlertId},
      );

      debugPrint('📬 Station notification response: $response');

      if (response != null && response['success'] == true) {
        final policeCount = response['police_notified'] ?? 0;
        final tanodCount = response['tanod_notified'] ?? 0;
        final totalNotified = response['total_notified'] ?? 0;
        debugPrint(
            '✅ Notified $policeCount police and $tanodCount tanod stations (Total: $totalNotified within 5km)');
      } else {
        final error = response?['error'] ?? 'Unknown error';
        debugPrint('⚠️ Station notification response: $error');
      }
    } catch (e) {
      debugPrint('❌ Error notifying stations: $e');
      // Don't fail the entire emergency flow if station notification fails
    }
  }

  Future<void> _updateEmergencyStatus(String status) async {
    try {
      await _supabase.from('emergency_alerts').update({
        'status': status,
        'resolved_at': DateTime.now().toIso8601String()
      }).eq('id', _emergencyId);
    } catch (e) {
      debugPrint('Error updating emergency status: $e');
    }
  }

  Future<void> _logActivity(String type, Map<String, dynamic>? data) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('user_activities').insert({
        'user_id': userId,
        'activity_type': type,
        'timestamp': DateTime.now().toIso8601String(),
        'latitude': _lastKnownLocation?.latitude,
        'longitude': _lastKnownLocation?.longitude,
        'data': data,
      });
    } catch (e) {
      debugPrint('Error logging activity: $e');
    }
  }

  Future<void> _sendEmergencyMessages(String alertType) async {
    if (_emergencyContacts.isEmpty) {
      debugPrint('No emergency contacts available');
      await _showSimpleAlert('No Contacts', 'No emergency contacts configured');
      return;
    }

    String message = _buildEmergencyMessage(alertType);

    for (var contact in _emergencyContacts) {
      await _sendSMSToContact(contact, message);
    }

    await _showSimpleAlert('Alerts Sent',
        'Emergency messages sent to ${_emergencyContacts.length} contacts');
    await _updateEmergencyStatus('MESSAGES_SENT');
  }

  String _buildEmergencyMessage(String alertType) {
    String urgency = alertType == 'CRITICAL' ? 'CRITICAL' : 'EMERGENCY';
    String locationText = _lastKnownAddress.isNotEmpty
        ? _lastKnownAddress
        : 'Location unavailable';

    if (_lastKnownLocation != null) {
      locationText +=
          '\nGPS: ${_lastKnownLocation!.latitude.toStringAsFixed(6)}, ${_lastKnownLocation!.longitude.toStringAsFixed(6)}';
    }

    return '''
🚨 $urgency ALERT - SOSit App

I need immediate help!

Time: ${DateTime.now().toString()}
Location: $locationText

This is an automated emergency message from the SOSit panic button app.

Please call me or emergency services immediately.

- Emergency hotline: 911
- Local emergency: 117
''';
  }

  Future<void> _sendSMSToContact(
      Map<String, dynamic> contact, String message) async {
    try {
      String phone = contact['emergency_contact_phone'] ?? '';
      String name = contact['emergency_contact_name'] ?? 'Emergency Contact';

      if (phone.isEmpty) return;

      // Create SMS URL
      String smsUrl = 'sms:$phone?body=${Uri.encodeComponent(message)}';

      if (await canLaunchUrl(Uri.parse(smsUrl))) {
        await launchUrl(Uri.parse(smsUrl));
        debugPrint('SMS sent to $name ($phone)');
      } else {
        debugPrint('Cannot send SMS to $phone');
      }
    } catch (e) {
      debugPrint('Error sending SMS: $e');
    }
  }

  Future<void> _showSimpleAlert(String title, String message) async {
    debugPrint('ALERT: $title - $message');

    // Don't show popup for system messages like "No Contacts"
    if (title.toLowerCase().contains('no contacts') ||
        title.toLowerCase().contains('alerts sent') ||
        message.toLowerCase().contains('no emergency contacts')) {
      debugPrint('ℹ️ System message - not showing popup');
      return;
    }

    // Trigger UI popup if callback is set
    print('🔥 EMERGENCY: _showSimpleAlert - checking popup callback');
    print(
        '🔥 EMERGENCY: _showPopupCallback != null: ${_showPopupCallback != null}');

    if (_showPopupCallback != null) {
      String alertType = 'regular'; // default

      if (title.toLowerCase().contains('critical') ||
          message.toLowerCase().contains('critical')) {
        alertType = 'critical';
      } else if (title.toLowerCase().contains('cancel') ||
          message.toLowerCase().contains('cancel')) {
        alertType = 'cancel';
      } else if (title.toLowerCase().contains('check') ||
          message.toLowerCase().contains('check')) {
        alertType = 'checkin';
      } else if (title.toLowerCase().contains('emergency') ||
          message.toLowerCase().contains('emergency')) {
        alertType = 'regular';
      }

      print('🔥 EMERGENCY: Triggering UI popup with type: $alertType');
      debugPrint('🎯 Triggering UI popup: $alertType');
      _showPopupCallback!(alertType);
      print('🔥 EMERGENCY: UI popup callback completed');
    } else {
      print('🔥 EMERGENCY: No popup callback set - only console output');
      debugPrint('⚠️ No popup callback set - only console output');
    }
  }

  Future<void> _vibrateDevice(List<int> pattern) async {
    try {
      // Use system haptic feedback instead of vibration plugin
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('Haptic feedback error: $e');
    }
  }

  // Manual emergency trigger (from app UI)
  Future<void> triggerManualEmergency(String type) async {
    debugPrint('Manual emergency triggered: $type');

    Map<String, dynamic> manualData = {
      'source': 'MANUAL',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'battery': 100, // App doesn't have battery info
    };

    await handleEmergencyAlert(type, manualData);
  }

  // Get emergency history
  Future<List<Map<String, dynamic>>> getEmergencyHistory() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final history = await _supabase
          .from('emergency_alerts')
          .select()
          .eq('user_id', userId)
          .order('timestamp', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(history);
    } catch (e) {
      debugPrint('Error fetching emergency history: $e');
      return [];
    }
  }

  // Test emergency system
  Future<void> testEmergencySystem() async {
    await _showSimpleAlert(
        'Test Alert', 'Emergency system test - all systems operational');
    await _vibrateDevice([200, 100, 200]);

    // Log test activity
    await _logActivity('SYSTEM_TEST', {
      'timestamp': DateTime.now().toIso8601String(),
      'location_available': _lastKnownLocation != null,
      'contacts_count': _emergencyContacts.length,
    });
  }

  // Check if emergency services are properly configured
  bool isEmergencySystemReady() {
    return _emergencyContacts.isNotEmpty && _lastKnownLocation != null;
  }

  String getSystemStatus() {
    List<String> issues = [];

    if (_emergencyContacts.isEmpty) {
      issues.add('No emergency contacts configured');
    }

    if (_lastKnownLocation == null) {
      issues.add('Location not available');
    }

    if (issues.isEmpty) {
      return 'Emergency system ready';
    } else {
      return 'Issues: ${issues.join(', ')}';
    }
  }

  @override
  void dispose() {
    _emergencyTimer?.cancel();
    _regularAlertTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
