// ignore_for_file: unused_element, unused_field, unused_local_variable

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';
import 'tanod_settings_page.dart';

class TanodDashboard extends StatefulWidget {
  const TanodDashboard({super.key});

  @override
  State<TanodDashboard> createState() => _TanodDashboardState();
}

class _TanodDashboardState extends State<TanodDashboard> {
  final supabase = Supabase.instance.client;
  GoogleMapController? _mapController;
  bool _isCardExpanded = false;
  List<Map<String, dynamic>> _incidents = [];
  bool _isLoadingIncidents = false;
  Set<Marker> _markers = {};
  List<Map<String, dynamic>> _incidentHistory = [];
  bool _isLoadingHistory = false;

  // Tracking state
  Marker? _userLocationMarker;
  // Realtime subscription for tracking a specific user
  RealtimeChannel? _userLocationChannel;
  StreamSubscription? _userLocationStreamSub;

  // Local notifications
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Connectivity & offline polling
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  DateTime? _lastFetchTime;
  static const String _lastFetchKey = 'tanod_last_notification_fetch';

  // Current position for distance calculation
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _initializeLocalNotifications();
    _getCurrentLocation();
    _loadIncidents();
    _loadUserProfile();
    _loadIncidentHistory();
    _loadLastFetchTime();
    // NOTE: Do NOT load old unread notifications on login to prevent multiple modals/notifications
    // Old notifications from initial station detection are not relevant emergencies
    // Real panic alerts are handled by _listenForStationNotifications() in real-time
    // _loadUnreadStationNotifications(); // DISABLED - was causing 11 modals on login
    _listenForStationNotifications();
    _startLocationTracking();
    _setupConnectivityListener(); // Setup offline recovery
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotificationsPlugin.initialize(initSettings,
        onDidReceiveNotificationResponse: (response) {
      debugPrint(
          'TanodDashboard: notification tapped with payload: ${response.payload}');
    });

    final androidPlugin =
        _localNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin
          .createNotificationChannel(const AndroidNotificationChannel(
        'station_critical',
        'Station Critical Alerts',
        description: 'Critical alerts for police/tanod stations',
        importance: Importance.max,
      ));

      await androidPlugin
          .createNotificationChannel(const AndroidNotificationChannel(
        'station_regular',
        'Station Alerts',
        description: 'Regular alerts for police/tanod stations',
        importance: Importance.high,
      ));
    }
  }

  // Load existing unread notifications on dashboard open
  Future<void> _loadUnreadStationNotifications() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      debugPrint('📋 Loading unread station notifications for user: $userId');

      final response = await supabase
          .from('station_notifications')
          .select()
          .eq('station_user_id', userId)
          .eq('read', false)
          .order('created_at', ascending: false);

      debugPrint('📬 Found ${response.length} unread notifications');

      if (response.isNotEmpty) {
        // Show the most recent unread notification
        final mostRecent = response.first;
        debugPrint('🚨 Showing most recent notification: ${mostRecent['id']}');
        _handleNewStationNotification(mostRecent);
      }
    } catch (e) {
      debugPrint('❌ Error loading unread notifications: $e');
    }
  }

  /// Setup connectivity listener to fetch missed notifications when back online
  void _setupConnectivityListener() {
    // Do NOT fetch on initial check during login - this prevents loading old notifications
    // Only fetch when connection is RESTORED after being offline
    // _connectivity.checkConnectivity().then((result) {
    //   if (result != ConnectivityResult.none) {
    //     _fetchMissedNotifications();
    //   }
    // }).catchError((e) {
    //   debugPrint('Connectivity check failed: $e');
    // });

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        debugPrint(
            '🌐 Connection restored - fetching missed station notifications');
        _fetchMissedNotifications();
      }
    });
  }

  /// Load last fetch timestamp from storage
  Future<void> _loadLastFetchTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getString(_lastFetchKey);

      // Always use NOW as the baseline to prevent fetching old notifications
      // This ensures only NEW notifications created after login are fetched
      _lastFetchTime = DateTime.now();
      await _saveLastFetchTime(_lastFetchTime!);

      if (timestamp != null) {
        debugPrint('📅 Previous fetch time was: $timestamp');
        debugPrint(
            '📅 Reset to NOW: $_lastFetchTime (prevents old notifications)');
      } else {
        debugPrint('📅 First login - initialized last fetch time to NOW');
      }
    } catch (e) {
      debugPrint('Error loading last fetch time: $e');
      _lastFetchTime = DateTime.now();
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

      debugPrint(
          '🔄 Fetching missed station notifications since $_lastFetchTime');

      final response = await supabase
          .from('station_notifications')
          .select()
          .eq('station_user_id', userId)
          .gte('created_at', _lastFetchTime!.toIso8601String())
          .order('created_at', ascending: false)
          .limit(1); // Only fetch the latest notification

      final List<dynamic> notifications = response as List<dynamic>;

      if (notifications.isEmpty) {
        debugPrint('✅ No missed station notifications');
      } else {
        debugPrint(
            '📬 Found ${notifications.length} missed station notification(s) - showing only the latest');

        // Only show the latest (most recent) notification
        final latestNotification = notifications.first as Map<String, dynamic>;
        _handleNewStationNotification(latestNotification);
      }

      await _saveLastFetchTime(fetchTime);
    } catch (e) {
      debugPrint('❌ Error fetching missed station notifications: $e');
    }
  }

  // Listen for station notifications instead of panic_alerts
  Future<void> _listenForStationNotifications() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint(
          '❌ TANOD: No user ID found for station notifications subscription');
      return;
    }

    debugPrint('🔔 TANOD: Setting up Realtime subscription for user: $userId');

    supabase
        .channel('tanod_station_notifications:$userId')
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'station_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'station_user_id',
              value: userId,
            ),
            callback: (payload) {
              debugPrint('🔥 TANOD: NEW REALTIME NOTIFICATION RECEIVED!');
              debugPrint('📦 TANOD Payload: $payload');
              debugPrint('📦 TANOD newRecord: ${payload.newRecord}');
              _handleNewStationNotification(payload.newRecord);
            })
        .subscribe((status, error) {
      debugPrint('📡 TANOD Subscription status: $status');
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint(
            '✅ TANOD: Successfully subscribed to station notifications!');
      } else if (status == RealtimeSubscribeStatus.channelError) {
        debugPrint('❌ TANOD: Channel error occurred');
      }
      if (error != null) {
        debugPrint('❌ TANOD Subscription error: $error');
      }
    });
  }

  // Start periodic location tracking (every 5 minutes)
  Future<void> _startLocationTracking() async {
    // Update location immediately
    await _updateDeviceLocation();

    // Then update every 5 minutes
    Future.delayed(const Duration(minutes: 5), () {
      if (mounted) {
        _startLocationTracking();
      }
    });
  }

  // Update device location in database
  Future<void> _updateDeviceLocation() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Store current position for distance calculations
      setState(() {
        _currentPosition = position;
      });

      // Update location in database
      await supabase.rpc('update_user_location', params: {
        'p_user_id': userId,
        'p_latitude': position.latitude,
        'p_longitude': position.longitude,
      });

      debugPrint(
          '📍 Location updated: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  void _handleNewStationNotification(Map<String, dynamic> notification) {
    debugPrint('🚨 TANOD: _handleNewStationNotification called!');
    debugPrint('🚨 TANOD: Notification data: $notification');
    debugPrint('🚨 TANOD: mounted = $mounted');

    if (!mounted) {
      debugPrint('❌ TANOD: Widget not mounted, skipping notification display');
      return;
    }

    debugPrint('✅ TANOD: Showing notification dialog...');

    // Refresh incidents list to show the new alert
    _loadIncidents();

    // Vibrate on CRITICAL alerts
    if (notification['alert_type'] == 'CRITICAL') {
      _vibrateCriticalAlert();
    }

    // Show alert dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildStationNotificationDialog(notification),
    );
    _showLocalNotificationForStation(notification);
  }

  Future<void> _showLocalNotificationForStation(
      Map<String, dynamic> notification) async {
    try {
      final notificationData =
          notification['notification_data'] as Map<String, dynamic>? ?? {};
      final title = notification['alert_type'] == 'CRITICAL'
          ? '🚨 CRITICAL Emergency'
          : notification['alert_type'] == 'CANCEL'
              ? '✅ Alert Cancelled'
              : '⚠️ Emergency Alert';
      final body = notificationData['address'] ?? 'Location updating...';

      final androidDetails = AndroidNotificationDetails(
        notification['alert_type'] == 'CRITICAL'
            ? 'station_critical'
            : 'station_regular',
        'Station Alerts',
        channelDescription: 'Station alert notifications',
        importance: notification['alert_type'] == 'CRITICAL'
            ? Importance.max
            : Importance.high,
        priority: notification['alert_type'] == 'CRITICAL'
            ? Priority.max
            : Priority.high,
        fullScreenIntent: notification['alert_type'] == 'CRITICAL',
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
      );

      final iosDetails = DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.critical);

      await _localNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        payload: notification['id']?.toString(),
      );
    } catch (e) {
      debugPrint('Error showing local station notification: $e');
    }
  }

  // Vibrate for 5 seconds on CRITICAL alerts (for police/tanod accounts)
  Future<void> _vibrateCriticalAlert() async {
    try {
      // Check if device supports vibration
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) {
        debugPrint('⚠️ TANOD: Device does not support vibration');
        return;
      }

      debugPrint('📳 TANOD: Starting 5-second vibration for CRITICAL alert...');

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

      debugPrint('✅ TANOD: 5-second critical alert vibration completed');
    } catch (e) {
      debugPrint('❌ TANOD: Error during vibration: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 14.0,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Widget _buildStationNotificationDialog(Map<String, dynamic> notification) {
    // Extract notification data from JSONB field
    final notificationData =
        notification['notification_data'] as Map<String, dynamic>? ?? {};

    // DEBUG: Print full notification data to see what's available
    debugPrint('🔍 TANOD MODAL - Full notification: $notification');
    debugPrint('🔍 TANOD MODAL - Notification data: $notificationData');

    final childUserId = notification['child_user_id'];
    final childName = notificationData['child_name'] ?? 'Unknown User';
    final address = notificationData['address'] ?? 'Location unavailable';

    // Calculate real-time distance asynchronously
    final alertLat = notificationData['latitude'] as double?;
    final alertLon = notificationData['longitude'] as double?;

    // Use FutureBuilder to fetch parent names and calculate distance
    return FutureBuilder<Map<String, String>>(
      future: _fetchModalData(childUserId, alertLat, alertLon),
      builder: (context, snapshot) {
        final parentNames = snapshot.data?['parentNames'] ??
            (notificationData['parent_names'] ?? 'Loading...');
        final distanceKm = snapshot.data?['distance'] ??
            ((notification['distance_km'] is num)
                ? (notification['distance_km'] as num).toStringAsFixed(2)
                : 'Calculating...');

        return _buildModalContent(
          notification,
          notificationData,
          childName,
          parentNames,
          address,
          distanceKm,
        );
      },
    );
  }

  /// Fetch parent names and calculate real-time distance
  Future<Map<String, String>> _fetchModalData(
    String? childUserId,
    double? alertLat,
    double? alertLon,
  ) async {
    final result = <String, String>{};

    // Fetch parent names
    result['parentNames'] = await _fetchParentNames(childUserId);

    // Calculate real-time distance
    try {
      if (alertLat != null && alertLon != null) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          alertLat,
          alertLon,
        );
        result['distance'] = (distance / 1000).toStringAsFixed(2);
      }
    } catch (e) {
      debugPrint('❌ Error calculating real-time distance: $e');
    }

    return result;
  }

  /// Fetch parent/guardian names for a child user
  ///
  /// CORRECT DATABASE RELATIONSHIP:
  /// emergency_contacts.user_id = The USER who added the contact (Joshua)
  /// emergency_contacts.emergency_contact_name = The EMERGENCY CONTACT name (Leyden Dondon)
  ///
  /// To find emergency contacts for a user:
  /// Query emergency_contacts WHERE user_id = childUserId
  /// Then get the emergency_contact_name field
  Future<String> _fetchParentNames(String? childUserId) async {
    if (childUserId == null) {
      debugPrint('🔍 Parent fetch: childUserId is null');
      return 'No parents listed';
    }

    try {
      debugPrint('🔍 Fetching emergency contacts for user: $childUserId');

      // Get emergency contacts that this user added
      final emergencyContactRecords = await supabase
          .from('emergency_contacts')
          .select('emergency_contact_name, emergency_contact_relationship')
          .eq('user_id', childUserId);

      debugPrint(
          '🔍 Found ${emergencyContactRecords.length} emergency contacts for this user');

      if (emergencyContactRecords.isEmpty) {
        debugPrint('⚠️ No emergency contacts found for user $childUserId');
        return 'No parents listed';
      }

      // Extract the contact names
      final contactNames = emergencyContactRecords
          .map((record) => record['emergency_contact_name'])
          .where((name) => name != null && name.toString().isNotEmpty)
          .toList();

      if (contactNames.isEmpty) {
        debugPrint('⚠️ Emergency contacts exist but have no names');
        return 'No parents listed';
      }

      final parentNames = contactNames.join(', ');
      debugPrint('✅ Emergency contact names: $parentNames');
      return parentNames;
    } catch (e) {
      debugPrint('❌ Error fetching emergency contact names: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
      return 'Error loading parents';
    }
  }

  Widget _buildModalContent(
    Map<String, dynamic> notification,
    Map<String, dynamic> notificationData,
    String childName,
    String parentNames,
    String address,
    String distanceKm,
  ) {
    // Parse timestamp from notification_data (REAL-TIME timestamp from panic_alerts)
    final timestampStr = notificationData['timestamp'] as String?;
    final timestamp = timestampStr != null
        ? DateTime.tryParse(timestampStr) ?? DateTime.now()
        : DateTime.now();

    // Format date and time separately
    final formattedDate =
        '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    final hour = timestamp.hour > 12
        ? timestamp.hour - 12
        : (timestamp.hour == 0 ? 12 : timestamp.hour);
    final period = timestamp.hour >= 12 ? 'PM' : 'AM';
    final formattedTime =
        '$hour:${timestamp.minute.toString().padLeft(2, '0')} $period';

    final latitude = notificationData['latitude'] as double?;
    final longitude = notificationData['longitude'] as double?;
    final userId = notification['child_user_id'];
    final alertType = notification['alert_type'] ?? 'REGULAR';

    // Set icon, title and color based on alert type
    IconData alertIcon;
    String title;
    Color alertColor;

    if (alertType == 'CANCEL') {
      alertIcon = Icons.check_circle;
      title = 'Emergency Cancelled';
      alertColor = Colors.green;
    } else if (alertType == 'CRITICAL') {
      alertIcon = Icons.emergency;
      title = 'CRITICAL EMERGENCY';
      alertColor = const Color(0xFFDC143C); // Crimson
    } else {
      alertIcon = Icons.warning_amber;
      title = 'Emergency Alert';
      alertColor = Colors.orange;
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 680),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: alertColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: alertColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        alertIcon,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: alertColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Panic Button Pressed',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              // Details Card
              Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(Icons.person, 'Name', childName),
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.family_restroom, 'Parent/Guardian',
                          parentNames),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                          Icons.calendar_today, 'Date', formattedDate),
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.access_time, 'Time', formattedTime),
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.location_on, 'Location', address),
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.social_distance, 'Distance',
                          '$distanceKm km away'),
                    ],
                  ),
                ),
              ),

              // Map Preview
              if (latitude != null && longitude != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(latitude, longitude),
                        zoom: 15,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId('alert_location'),
                          position: LatLng(latitude, longitude),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            alertType == 'CRITICAL'
                                ? BitmapDescriptor.hueRed
                                : BitmapDescriptor.hueOrange,
                          ),
                          infoWindow: InfoWindow(
                            title: childName,
                            snippet: address,
                          ),
                        ),
                      },
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                    ),
                  ),
                ),
              const SizedBox(height: 12),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    if (alertType != 'CANCEL') ...[
                      // Track User Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _trackUser(
                                userId, latitude, longitude, childName, 'N/A');
                          },
                          icon:
                              const Icon(Icons.navigation, color: Colors.white),
                          label: const Text(
                            'Track User',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4A90E2),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Dismiss Button
              Padding(
                padding: const EdgeInsets.all(20),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Dismiss',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[700]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openMapToLocation(
      double latitude, double longitude, String childName) async {
    // Create Google Maps URL
    final url = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open maps'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening maps: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _trackUser(String? userId, double? latitude, double? longitude,
      String userName, String contactNumber) {
    if (userId == null || latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot track user: location data unavailable'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Update state to track this user
    setState(() {
      // Add marker for user's location
      _userLocationMarker = Marker(
        markerId: MarkerId('user_$userId'),
        position: LatLng(latitude, longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Emergency: $userName',
          snippet: 'Panic button pressed',
        ),
      );

      // Add the marker to the map
      _markers = {..._markers, _userLocationMarker!};
    });

    // Animate camera to user's location
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(latitude, longitude),
          16.0,
        ),
      );
    }

    // Start realtime subscription to track updates for this user
    _subscribeToUserLocation(userId.toString());

    // Removed the tracking bottom sheet popup - now goes directly to map
    // _showTrackingBottomSheet(userName, contactNumber);
  }

  void _subscribeToUserLocation(String? userId) {
    // Unsubscribe existing
    try {
      if (_userLocationChannel != null) {
        _userLocationChannel?.unsubscribe();
        _userLocationChannel = null;
      }
    } catch (_) {}

    if (userId == null) return;

    _userLocationChannel = supabase
        .channel('user_locations:$userId')
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'user_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              final rec = payload.newRecord as Map<String, dynamic>?;
              if (rec != null) {
                final lat = (rec['latitude'] as num?)?.toDouble();
                final lng = (rec['longitude'] as num?)?.toDouble();
                if (lat != null && lng != null) {
                  setState(() {
                    _userLocationMarker = Marker(
                      markerId: MarkerId('user_$userId'),
                      position: LatLng(lat, lng),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueRed),
                      infoWindow: InfoWindow(title: 'Tracking: $userId'),
                    );
                    _markers = {..._markers, _userLocationMarker!};
                  });
                  _mapController
                      ?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
                }
              }
            })
        .subscribe();

    // Fallback to panic_alerts updates
    supabase
        .channel('panic_alerts:$userId')
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'panic_alerts',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              final rec = payload.newRecord as Map<String, dynamic>?;
              if (rec != null) {
                final lat = (rec['latitude'] as num?)?.toDouble();
                final lng = (rec['longitude'] as num?)?.toDouble();
                final alertType = rec['alert_level'] ?? rec['alert_type'];
                final ts = rec['timestamp'] ?? rec['created_at'];
                if (lat != null && lng != null) {
                  setState(() {
                    _userLocationMarker = Marker(
                      markerId: MarkerId('user_$userId'),
                      position: LatLng(lat, lng),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueRed),
                      infoWindow: InfoWindow(
                          title: 'Alert: $alertType', snippet: ts?.toString()),
                    );
                    _markers = {..._markers, _userLocationMarker!};
                  });
                  _mapController
                      ?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
                }
              }
            })
        .subscribe();
  }

  void _unsubscribeFromUserLocation() {
    try {
      if (_userLocationChannel != null) {
        _userLocationChannel?.unsubscribe();
        _userLocationChannel = null;
      }
    } catch (_) {}
  }

  Future<void> _loadUserProfile() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        await supabase.from('user').select().eq('id', userId).single();
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _loadIncidents() async {
    setState(() => _isLoadingIncidents = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoadingIncidents = false);
        return;
      }

      debugPrint('🔍 TANOD: Loading active incidents for user: $userId');

      // Load unread station notifications (active incidents)
      final incidents = await supabase
          .from('station_notifications')
          .select()
          .eq('station_user_id', userId)
          .eq('read', false)
          .order('created_at', ascending: false)
          .limit(10);

      debugPrint('📊 TANOD: Found ${incidents.length} active incidents');

      Set<Marker> markers = {};

      for (var incident in incidents) {
        final notificationData =
            incident['notification_data'] as Map<String, dynamic>? ?? {};
        final latitude = notificationData['latitude'] as double?;
        final longitude = notificationData['longitude'] as double?;
        final childName = notificationData['child_name'] ?? 'Unknown';
        final alertType = incident['alert_type'] ?? 'REGULAR';

        if (latitude != null && longitude != null) {
          markers.add(
            Marker(
              markerId: MarkerId(incident['id'].toString()),
              position: LatLng(latitude, longitude),
              infoWindow: InfoWindow(
                title: '$alertType ALERT',
                snippet: childName,
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                alertType == 'CRITICAL'
                    ? BitmapDescriptor.hueRed
                    : BitmapDescriptor.hueOrange,
              ),
            ),
          );
        }
      }

      setState(() {
        _incidents = incidents;
        _markers = markers;
        _isLoadingIncidents = false;
      });
    } catch (e) {
      setState(() => _isLoadingIncidents = false);
      debugPrint('❌ Error loading incidents: $e');
    }
  }

  Future<void> _loadIncidentHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoadingHistory = false);
        return;
      }

      debugPrint('📚 TANOD: Loading incident history for user: $userId');

      // Load read station notifications (incident history)
      final history = await supabase
          .from('station_notifications')
          .select()
          .eq('station_user_id', userId)
          .eq('read', true)
          .order('created_at', ascending: false)
          .limit(20);

      debugPrint('📜 TANOD: Found ${history.length} history records');

      setState(() {
        _incidentHistory = history;
        _isLoadingHistory = false;
      });
    } catch (e) {
      setState(() => _isLoadingHistory = false);
      debugPrint('❌ TANOD: Error loading incident history: $e');
    }
  }

  Future<void> _respondToIncident(
      String incidentId, String responseType) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase.from('incident_responses').insert({
        'incident_id': incidentId,
        'responder_id': userId,
        'response_type': responseType,
        'responded_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Response recorded: $responseType'),
          backgroundColor: Colors.green,
        ),
      );

      _loadIncidents(); // Refresh incidents
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to record response: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showIncidentHistoryDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: screenWidth * 0.85,
            height: screenHeight * 0.65,
            padding: EdgeInsets.all(screenWidth * 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history,
                        color: Colors.orange, size: screenWidth * 0.07),
                    SizedBox(width: screenWidth * 0.02),
                    Text(
                      'Incident History',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: screenWidth * 0.045,
                        color: Colors.black,
                      ),
                    ),
                    Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                SizedBox(height: screenHeight * 0.01),
                Expanded(
                  child: _isLoadingHistory
                      ? Center(child: CircularProgressIndicator())
                      : _incidentHistory.isEmpty
                          ? Center(
                              child: Text(
                                'No incident history found.',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: screenWidth * 0.035,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _incidentHistory.length,
                              itemBuilder: (context, index) {
                                final incident = _incidentHistory[index];
                                return _buildHistoryCard(
                                  incident,
                                  screenWidth,
                                  screenHeight,
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTrackingBottomSheet(String userName, String contactNumber) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: screenHeight * 0.25,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: screenWidth * 0.1,
                height: 4,
                margin: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(screenWidth * 0.02),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: screenWidth * 0.05,
                          ),
                        ),
                        SizedBox(width: screenWidth * 0.03),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: screenWidth * 0.045,
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 5),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Text(
                                  '3 min away',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: screenWidth * 0.035,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Spacer(),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              if (_userLocationMarker != null) {
                                _markers = Set.from(_markers)
                                  ..removeWhere((m) =>
                                      m.markerId ==
                                      _userLocationMarker!.markerId);
                              }
                            });
                          },
                          child: const Text('Exit',
                              style: TextStyle(color: Colors.white)),
                        )
                      ],
                    ),
                    Divider(height: screenHeight * 0.03),
                    Row(
                      children: [
                        Icon(Icons.phone,
                            color: Colors.blue, size: screenWidth * 0.05),
                        SizedBox(width: screenWidth * 0.02),
                        Text(
                          'Contact: $contactNumber',
                          style: TextStyle(
                            fontSize: screenWidth * 0.04,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: screenHeight * 0.015),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.phone, color: Colors.white),
                          label: const Text('Call',
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.08,
                              vertical: screenHeight * 0.01,
                            ),
                          ),
                          onPressed: () {
                            // Call emergency services
                          },
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.message, color: Colors.white),
                          label: const Text('Message',
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.08,
                              vertical: screenHeight * 0.01,
                            ),
                          ),
                          onPressed: () {
                            // Send message
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    return Scaffold(
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(7.0731, 125.6124), // Davao City
              zoom: 14,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
            markers: _markers,
            onMapCreated: (controller) => _mapController = controller,
          ),

          // Top Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: EdgeInsets.all(screenWidth * 0.04),
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.04,
                  vertical: screenHeight * 0.015,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Settings
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TanodSettingsPage()),
                      ),
                      child: Icon(
                        Icons.settings,
                        color: Colors.orange,
                        size: screenWidth * 0.07,
                      ),
                    ),

                    // Tanod Badge and Title
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.security,
                            color: Colors.orange,
                            size: screenWidth * 0.06,
                          ),
                          SizedBox(width: screenWidth * 0.02),
                          Text(
                            'Tanod Dashboard',
                            style: TextStyle(
                              fontSize: screenWidth * 0.045,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // History Icon (incident history)
                    GestureDetector(
                      onTap: _showIncidentHistoryDialog,
                      child: Icon(
                        Icons.history,
                        color: Colors.orange,
                        size: screenWidth * 0.07,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Panel
          Positioned(
            left: 0,
            right: 0,
            bottom: _isCardExpanded ? 0 : screenHeight * 0.03,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (details.delta.dy < -5 && !_isCardExpanded) {
                  setState(() => _isCardExpanded = true);
                } else if (details.delta.dy > 5 && _isCardExpanded) {
                  setState(() => _isCardExpanded = false);
                }
              },
              onTap: () => setState(() => _isCardExpanded = !_isCardExpanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _isCardExpanded ? screenHeight * 0.6 : null,
                constraints: _isCardExpanded
                    ? null
                    : BoxConstraints(
                        maxHeight: screenHeight * 0.3,
                        minHeight: screenHeight * 0.15,
                      ),
                margin: EdgeInsets.symmetric(
                  horizontal: _isCardExpanded ? 0 : screenWidth * 0.04,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(_isCardExpanded ? 24 : 20),
                    topRight: Radius.circular(_isCardExpanded ? 24 : 20),
                    bottomLeft: Radius.circular(_isCardExpanded ? 0 : 20),
                    bottomRight: Radius.circular(_isCardExpanded ? 0 : 20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: _isCardExpanded
                    ? _buildExpandedPanel(screenWidth, screenHeight)
                    : _buildCollapsedPanel(screenWidth, screenHeight),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedPanel(double screenWidth, double screenHeight) {
    return Padding(
      padding: EdgeInsets.all(screenWidth * 0.045),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: screenWidth * 0.12,
            height: 4,
            margin: EdgeInsets.only(bottom: screenHeight * 0.015),
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title and status
          Row(
            children: [
              Icon(
                Icons.security,
                color: Colors.orange,
                size: screenWidth * 0.06,
              ),
              SizedBox(width: screenWidth * 0.03),
              Text(
                'Active Incidents',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: screenWidth * 0.045,
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.03,
                  vertical: screenHeight * 0.005,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'ON DUTY',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: screenWidth * 0.03,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: screenHeight * 0.015),

          // Swipe up indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.keyboard_arrow_up,
                color: Colors.grey.shade600,
                size: screenWidth * 0.05,
              ),
              SizedBox(width: screenWidth * 0.02),
              Text(
                'Swipe up to view incidents',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: screenWidth * 0.03,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedPanel(double screenWidth, double screenHeight) {
    return Padding(
      padding: EdgeInsets.all(screenWidth * 0.045),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: screenWidth * 0.12,
            height: 4,
            margin: EdgeInsets.only(bottom: screenHeight * 0.015),
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Row(
            children: [
              Text(
                'Emergency Reports',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: screenWidth * 0.045,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadIncidents,
                icon: Icon(
                  Icons.refresh,
                  color: Colors.orange,
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down,
                color: Colors.grey.shade600,
                size: screenWidth * 0.05,
              ),
            ],
          ),

          SizedBox(height: screenHeight * 0.015),

          // Incidents list
          Expanded(
            child: _isLoadingIncidents
                ? const Center(child: CircularProgressIndicator())
                : _incidents.isEmpty
                    ? _buildEmptyState(screenWidth, screenHeight)
                    : ListView.builder(
                        itemCount: _incidents.length,
                        itemBuilder: (context, index) {
                          final incident = _incidents[index];
                          return _buildIncidentCard(
                              incident, screenWidth, screenHeight);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(double screenWidth, double screenHeight) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.security,
            size: screenWidth * 0.15,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: screenHeight * 0.02),
          Text(
            'No Active Incidents',
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: screenHeight * 0.01),
          Text(
            'All clear in your area',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentCard(
      Map<String, dynamic> incident, double screenWidth, double screenHeight) {
    final notificationData =
        incident['notification_data'] as Map<String, dynamic>? ?? {};
    // Get child_user_id from root notification object (same as modal)
    final childUserId = incident['child_user_id'] as String?;

    return FutureBuilder<String>(
      future: _fetchParentNames(childUserId),
      builder: (context, parentSnapshot) {
        final parentNames = parentSnapshot.data ?? 'Loading...';

        // Extract comprehensive details from notification_data
        final childName = notificationData['child_name'] ?? 'Unknown';
        final address = notificationData['address'] ?? 'Unknown location';
        final latitude = notificationData['latitude'] as double?;
        final longitude = notificationData['longitude'] as double?;
        final timestamp = notificationData['timestamp'] as String?;
        final alertType = incident['alert_type'] ?? 'REGULAR';

        // Format date and time
        DateTime? dateTime;
        String formattedDate = 'Unknown date';
        String formattedTime = 'Unknown time';
        String timeAgo = 'Just now';

        if (timestamp != null) {
          try {
            dateTime = DateTime.parse(timestamp);
            formattedDate = DateFormat('MMMM d, yyyy').format(dateTime);
            formattedTime = DateFormat('h:mm a').format(dateTime);
            timeAgo = _getTimeAgo(dateTime);
          } catch (e) {
            debugPrint('Error parsing timestamp: $e');
          }
        }

        // Calculate distance if coordinates available
        String distance = 'Unknown distance';
        if (latitude != null && longitude != null && _currentPosition != null) {
          final distanceInMeters = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            latitude,
            longitude,
          );
          if (distanceInMeters < 1000) {
            distance = '${distanceInMeters.toStringAsFixed(0)}m away';
          } else {
            distance = '${(distanceInMeters / 1000).toStringAsFixed(2)}km away';
          }
        }

        return Container(
          margin: EdgeInsets.only(bottom: screenHeight * 0.015),
          padding: EdgeInsets.all(screenWidth * 0.04),
          decoration: BoxDecoration(
            color: alertType == 'CRITICAL'
                ? Colors.red.shade50
                : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: alertType == 'CRITICAL'
                  ? Colors.red.shade200
                  : Colors.orange.shade200,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(screenWidth * 0.02),
                    decoration: BoxDecoration(
                      color: alertType == 'CRITICAL'
                          ? Colors.red.shade100
                          : Colors.orange.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      alertType == 'CRITICAL' ? Icons.warning : Icons.emergency,
                      color: alertType == 'CRITICAL'
                          ? Colors.red.shade700
                          : Colors.orange.shade700,
                      size: screenWidth * 0.05,
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.03),
                  Expanded(
                    child: Text(
                      '$alertType ALERT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: screenWidth * 0.04,
                        color: alertType == 'CRITICAL'
                            ? Colors.red.shade700
                            : Colors.orange.shade700,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.025,
                      vertical: screenHeight * 0.005,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'PENDING',
                      style: TextStyle(
                        fontSize: screenWidth * 0.025,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: screenHeight * 0.015),

              // Child name
              Row(
                children: [
                  Icon(Icons.person,
                      size: screenWidth * 0.04, color: Colors.blue.shade700),
                  SizedBox(width: screenWidth * 0.02),
                  Expanded(
                    child: Text(
                      childName,
                      style: TextStyle(
                        fontSize: screenWidth * 0.038,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.008),

              // Parent/Guardian
              Row(
                children: [
                  Icon(Icons.family_restroom,
                      size: screenWidth * 0.04, color: Colors.green.shade700),
                  SizedBox(width: screenWidth * 0.02),
                  Expanded(
                    child: Text(
                      'Parent: $parentNames',
                      style: TextStyle(
                        fontSize: screenWidth * 0.035,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.008),

              // Date and Time
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: screenWidth * 0.035, color: Colors.grey.shade600),
                  SizedBox(width: screenWidth * 0.02),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      fontSize: screenWidth * 0.033,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.03),
                  Icon(Icons.access_time,
                      size: screenWidth * 0.035, color: Colors.grey.shade600),
                  SizedBox(width: screenWidth * 0.02),
                  Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: screenWidth * 0.033,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.008),

              // Location
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on,
                      size: screenWidth * 0.04, color: Colors.red.shade600),
                  SizedBox(width: screenWidth * 0.02),
                  Expanded(
                    child: Text(
                      address,
                      style: TextStyle(
                        fontSize: screenWidth * 0.035,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.008),

              // Distance
              Row(
                children: [
                  Icon(Icons.social_distance,
                      size: screenWidth * 0.04, color: Colors.purple.shade600),
                  SizedBox(width: screenWidth * 0.02),
                  Text(
                    distance,
                    style: TextStyle(
                      fontSize: screenWidth * 0.035,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              SizedBox(height: screenHeight * 0.015),

              // Mark as Handled Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _markIncidentAsHandled(incident['id']);
                  },
                  icon: Icon(Icons.check_circle_outline,
                      size: screenWidth * 0.045),
                  label: Text(
                    'Mark as Handled',
                    style: TextStyle(fontSize: screenWidth * 0.038),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding:
                        EdgeInsets.symmetric(vertical: screenHeight * 0.012),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _markIncidentAsHandled(String incidentId) async {
    try {
      debugPrint('🔄 TANOD: Marking incident as handled: $incidentId');

      await supabase
          .from('station_notifications')
          .update({'read': true}).eq('id', incidentId);

      debugPrint('✅ TANOD: Incident marked as handled successfully');

      // Reload both active incidents and history
      await _loadIncidents();
      await _loadIncidentHistory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Incident marked as handled'),
            backgroundColor: Colors.green.shade600,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ TANOD: Error marking incident as handled: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark incident as handled'),
            backgroundColor: Colors.red.shade600,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildHistoryCard(
      Map<String, dynamic> incident, double screenWidth, double screenHeight) {
    final notificationData =
        incident['notification_data'] as Map<String, dynamic>? ?? {};
    // Get child_user_id from root notification object (same as active incidents)
    final childUserId = incident['child_user_id'] as String?;

    return FutureBuilder<String>(
      future: _fetchParentNames(childUserId),
      builder: (context, parentSnapshot) {
        final parentNames = parentSnapshot.data ?? 'Loading...';

        // Extract comprehensive details from notification_data
        final childName = notificationData['child_name'] ?? 'Unknown';
        final address = notificationData['address'] ?? 'Unknown location';
        final latitude = notificationData['latitude'] as double?;
        final longitude = notificationData['longitude'] as double?;
        final timestamp = notificationData['timestamp'] as String?;
        final alertType = incident['alert_type'] ?? 'REGULAR';

        // Format date and time
        DateTime? dateTime;
        String formattedDate = 'Unknown date';
        String formattedTime = 'Unknown time';

        if (timestamp != null) {
          try {
            dateTime = DateTime.parse(timestamp);
            formattedDate = DateFormat('MMMM d, yyyy').format(dateTime);
            formattedTime = DateFormat('h:mm a').format(dateTime);
          } catch (e) {
            debugPrint('Error parsing timestamp: $e');
          }
        }

        // Calculate distance if coordinates available
        String distance = 'Unknown distance';
        if (latitude != null && longitude != null && _currentPosition != null) {
          final distanceInMeters = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            latitude,
            longitude,
          );
          if (distanceInMeters < 1000) {
            distance = '${distanceInMeters.toStringAsFixed(0)}m away';
          } else {
            distance = '${(distanceInMeters / 1000).toStringAsFixed(2)}km away';
          }
        }

        return Container(
          margin: EdgeInsets.only(bottom: screenHeight * 0.015),
          padding: EdgeInsets.all(screenWidth * 0.04),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.green.shade200,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(screenWidth * 0.02),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade700,
                      size: screenWidth * 0.05,
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.03),
                  Expanded(
                    child: Text(
                      '$alertType ALERT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: screenWidth * 0.04,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.025,
                      vertical: screenHeight * 0.005,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'HANDLED',
                      style: TextStyle(
                        fontSize: screenWidth * 0.025,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: screenHeight * 0.015),

              // Child name
              Row(
                children: [
                  Icon(Icons.person,
                      size: screenWidth * 0.04, color: Colors.blue.shade700),
                  SizedBox(width: screenWidth * 0.02),
                  Expanded(
                    child: Text(
                      childName,
                      style: TextStyle(
                        fontSize: screenWidth * 0.038,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.008),

              // Parent/Guardian
              Row(
                children: [
                  Icon(Icons.family_restroom,
                      size: screenWidth * 0.04, color: Colors.green.shade700),
                  SizedBox(width: screenWidth * 0.02),
                  Expanded(
                    child: Text(
                      'Parent: $parentNames',
                      style: TextStyle(
                        fontSize: screenWidth * 0.035,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.008),

              // Date and Time
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: screenWidth * 0.035, color: Colors.grey.shade600),
                  SizedBox(width: screenWidth * 0.02),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      fontSize: screenWidth * 0.033,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.03),
                  Icon(Icons.access_time,
                      size: screenWidth * 0.035, color: Colors.grey.shade600),
                  SizedBox(width: screenWidth * 0.02),
                  Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: screenWidth * 0.033,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.008),

              // Location
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on,
                      size: screenWidth * 0.04, color: Colors.red.shade600),
                  SizedBox(width: screenWidth * 0.02),
                  Expanded(
                    child: Text(
                      address,
                      style: TextStyle(
                        fontSize: screenWidth * 0.035,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.008),

              // Distance
              Row(
                children: [
                  Icon(Icons.social_distance,
                      size: screenWidth * 0.04, color: Colors.purple.shade600),
                  SizedBox(width: screenWidth * 0.02),
                  Text(
                    distance,
                    style: TextStyle(
                      fontSize: screenWidth * 0.035,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inSeconds}s ago';
    }
  }

  @override
  void dispose() {
    _unsubscribeFromUserLocation();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
