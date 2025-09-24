// lib/services/emergency_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

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
    await _loadEmergencyContacts();
    await _getCurrentLocation();
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
    debugPrint('Handling emergency alert: $alertType');

    // Debounce check - prevent duplicate alerts within 1 second
    final now = DateTime.now();
    if (_lastAlertTime != null &&
        _lastAlertType == alertType &&
        now.difference(_lastAlertTime!).inMilliseconds < 1000) {
      debugPrint(
          '🚫 Ignoring duplicate $alertType alert (debounced - ${now.difference(_lastAlertTime!).inMilliseconds}ms ago)');
      return;
    }

    debugPrint('🎯 Processing $alertType alert');
    _lastAlertTime = now;
    _lastAlertType = alertType; // Update location before processing
    await _getCurrentLocation();

    switch (alertType) {
      case 'REGULAR':
        await _handleRegularAlert(alertData);
        break;
      case 'CHECKIN':
        await _handleCheckInAlert(alertData);
        break;
      case 'CRITICAL':
        await _handleCriticalAlert(alertData);
        break;
      case 'CANCEL':
        await _handleCancelAlert();
        break;
      default:
        debugPrint('Unknown alert type: $alertType');
    }
  }

  Future<void> _handleRegularAlert(Map<String, dynamic>? alertData) async {
    if (_isEmergencyActive) {
      debugPrint('🚫 Emergency already active, ignoring regular alert');
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

    notifyListeners();
    debugPrint('Emergency cancelled');
  }

  Future<void> _logEmergencyToDatabase(
      String type, Map<String, dynamic>? alertData) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

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
      debugPrint('Error logging emergency: $e');
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

      debugPrint('🎯 Triggering UI popup: $alertType');
      _showPopupCallback!(alertType);
    } else {
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
    super.dispose();
  }
}
