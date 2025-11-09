import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'police_settings_page.dart';

class PoliceDashboard extends StatefulWidget {
  const PoliceDashboard({super.key});

  @override
  State<PoliceDashboard> createState() => _PoliceDashboardState();
}

class _PoliceDashboardState extends State<PoliceDashboard> {
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
  static const String _lastFetchKey = 'police_last_notification_fetch';

  @override
  void initState() {
    super.initState();
    _initializeLocalNotifications();
    _getCurrentLocation();
    _loadIncidents();
    _loadUserProfile();
    _loadIncidentHistory();
    _loadLastFetchTime();
    _loadUnreadStationNotifications(); // Load existing unread notifications
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
      // Optionally handle notification taps
      debugPrint(
          'PoliceDashboard: notification tapped with payload: ${response.payload}');
    });

    // Create channels (duplicate of EmergencyService channels but safe here)
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
      if (timestamp != null) {
        _lastFetchTime = DateTime.parse(timestamp);
        debugPrint('📅 Last notification fetch: $_lastFetchTime');
      } else {
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

      debugPrint(
          '🔄 Fetching missed station notifications since $_lastFetchTime');

      final response = await supabase
          .from('station_notifications')
          .select()
          .eq('station_user_id', userId)
          .gte('created_at', _lastFetchTime!.toIso8601String())
          .order('created_at', ascending: false);

      final List<dynamic> notifications = response as List<dynamic>;

      if (notifications.isEmpty) {
        debugPrint('✅ No missed station notifications');
      } else {
        debugPrint(
            '📬 Found ${notifications.length} missed station notification(s)');

        for (final notification in notifications.reversed) {
          final notificationMap = notification as Map<String, dynamic>;
          _handleNewStationNotification(notificationMap);
          await Future.delayed(const Duration(milliseconds: 500));
        }
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
      debugPrint('❌ No user ID found for station notifications subscription');
      return;
    }

    debugPrint('🔔 Setting up Realtime subscription for user: $userId');

    supabase
        .channel('station_notifications:$userId')
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
              debugPrint('🔥 NEW REALTIME NOTIFICATION RECEIVED!');
              debugPrint('📦 Payload: $payload');
              _handleNewStationNotification(payload.newRecord);
            })
        .subscribe((status, error) {
      debugPrint('📡 Subscription status: $status');
      if (error != null) {
        debugPrint('❌ Subscription error: $error');
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
    if (!mounted) return;

    // Play alert sound or vibration here

    // Show alert dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildStationNotificationDialog(notification),
    );
    // Also show a local notification so it appears on device (home/lock screen)
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Extract notification data from JSONB field
    final notificationData =
        notification['notification_data'] as Map<String, dynamic>? ?? {};
    final childName = notificationData['child_name'] ?? 'Unknown User';
    final parentNames = notificationData['parent_names'] ?? 'No parents listed';
    final address = notificationData['address'] ?? 'Location unavailable';
    final distanceKm = (notification['distance_km'] is num)
        ? (notification['distance_km'] as num).toStringAsFixed(2)
        : 'N/A';

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

    // Set title and color based on alert type
    String title = 'Emergency Alert Received';
    Color alertColor = const Color(0xFFF73D5C);
    if (alertType == 'CRITICAL') {
      title = '🚨 CRITICAL EMERGENCY';
      alertColor = Colors.red;
    } else if (alertType == 'CANCEL') {
      title = '✅ Emergency Cancelled';
      alertColor = Colors.green;
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: EdgeInsets.zero,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: alertColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            width: double.infinity,
            child: Column(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Panic Button Pressed',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SOS Button visual
                Center(
                  child: Container(
                    width: screenWidth * 0.3,
                    height: screenWidth * 0.3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: alertColor,
                      border: Border.all(
                        color: alertColor.withOpacity(0.3),
                        width: 8,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'SOS',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'A user has activated the panic button.',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 20),

                // User Information
                _buildInfoRow('User Name:', childName),
                _buildInfoRow('Parent/Guardian:', parentNames),
                _buildInfoRow('Date:', formattedDate),
                _buildInfoRow('Time:', formattedTime),
                _buildInfoRow('Location:', address),
                _buildInfoRow('Distance:', '$distanceKm km away'),

                // Map preview if coordinates available
                if (latitude != null && longitude != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    height: screenHeight * 0.25,
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
                          markerId: MarkerId('alert_location'),
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
                ],
              ],
            ),
          ),
          if (alertType != 'CANCEL')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: alertColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _trackUser(userId, latitude, longitude, childName, 'N/A');
                  },
                  child: const Text(
                    'Track User',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          if (alertType == 'CANCEL')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
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

    // Show bottom sheet with tracking info
    _showTrackingBottomSheet(userName, contactNumber);
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
      // Load recent incidents/emergency reports
      final incidents = await supabase
          .from('emergency_reports')
          .select('*, user!inner(*)')
          .order('created_at', ascending: false)
          .limit(10);

      Set<Marker> markers = {};

      for (var incident in incidents) {
        if (incident['latitude'] != null && incident['longitude'] != null) {
          markers.add(
            Marker(
              markerId: MarkerId(incident['id'].toString()),
              position: LatLng(
                incident['latitude'].toDouble(),
                incident['longitude'].toDouble(),
              ),
              infoWindow: InfoWindow(
                title: 'Emergency Report',
                snippet: incident['emergency_type'] ?? 'Unknown',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed),
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
      debugPrint('Error loading incidents: $e');
    }
  }

  Future<void> _loadIncidentHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Load incidents where this police responded
      final history = await supabase
          .from('incident_responses')
          .select('*, incident:emergency_reports(*, user!inner(email))')
          .eq('responder_id', userId)
          .order('responded_at', ascending: false)
          .limit(20);

      setState(() {
        _incidentHistory = history;
        _isLoadingHistory = false;
      });
    } catch (e) {
      setState(() => _isLoadingHistory = false);
      debugPrint('Error loading incident history: $e');
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
                        color: Colors.blue, size: screenWidth * 0.07),
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
                                final item = _incidentHistory[index];
                                final incident = item['incident'] ?? {};
                                final type =
                                    incident['emergency_type'] ?? 'Unknown';
                                final location = incident['location'] ??
                                    'Location not available';
                                final reporter =
                                    incident['user']?['email'] ?? 'Unknown';
                                final responseType =
                                    item['response_type'] ?? '';
                                final respondedAt = item['responded_at'] != null
                                    ? DateTime.tryParse(item['responded_at'])
                                    : null;
                                final timeAgo = respondedAt != null
                                    ? _getTimeAgo(respondedAt)
                                    : '';

                                return Container(
                                  margin: EdgeInsets.only(
                                      bottom: screenHeight * 0.012),
                                  padding: EdgeInsets.all(screenWidth * 0.03),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border:
                                        Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.warning,
                                              color: Colors.red,
                                              size: screenWidth * 0.05),
                                          SizedBox(width: screenWidth * 0.02),
                                          Text(
                                            type.toUpperCase(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red.shade700,
                                              fontSize: screenWidth * 0.037,
                                            ),
                                          ),
                                          Spacer(),
                                          Text(
                                            responseType.toUpperCase(),
                                            style: TextStyle(
                                              color: Colors.blue,
                                              fontWeight: FontWeight.w600,
                                              fontSize: screenWidth * 0.032,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: screenHeight * 0.004),
                                      Text(
                                        'Reporter: $reporter',
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.033,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        'Location: $location',
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.033,
                                          color: Colors.black87,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: screenHeight * 0.004),
                                      Text(
                                        timeAgo,
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.03,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
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

  void _subscribeToUserLocation(String? userId) {
    // Unsubscribe existing
    try {
      if (_userLocationChannel != null) {
        _userLocationChannel?.unsubscribe();
        _userLocationChannel = null;
      }
    } catch (_) {}

    if (userId == null) return;

    // Primary: subscribe to a user_locations table if available
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
                  // Update marker
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

    // Fallback: also listen for updates to panic_alerts for this user
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
                // update marker and optionally show small info
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
                            builder: (_) => const PoliceSettingsPage()),
                      ),
                      child: Icon(
                        Icons.settings,
                        color: const Color(0xFF2196F3),
                        size: screenWidth * 0.07,
                      ),
                    ),

                    // Police Badge and Title
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.local_police,
                            color: const Color(0xFF2196F3),
                            size: screenWidth * 0.06,
                          ),
                          SizedBox(width: screenWidth * 0.02),
                          Text(
                            'Police Dashboard',
                            style: TextStyle(
                              fontSize: screenWidth * 0.045,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // History Icon (incident history) - bigger and same color as settings
                    GestureDetector(
                      onTap: _showIncidentHistoryDialog,
                      child: Icon(
                        Icons.history,
                        color: const Color(0xFF2196F3),
                        size: screenWidth * 0.07, // same as settings icon
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
                Icons.local_police,
                color: const Color(0xFF2196F3),
                size: screenWidth * 0.06,
              ),
              SizedBox(width: screenWidth * 0.03),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Incidents',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: screenWidth * 0.045,
                    ),
                  ),
                  Text(
                    '${_incidents.length} reports',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: screenWidth * 0.035,
                    ),
                  ),
                ],
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
                  color: const Color(0xFF2196F3),
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
    final user = incident['user'];
    final emergencyType = incident['emergency_type'] ?? 'Unknown';
    final location = incident['location'] ?? 'Location not available';
    final timestamp = DateTime.parse(incident['created_at']);
    final timeAgo = _getTimeAgo(timestamp);

    return Container(
      margin: EdgeInsets.only(bottom: screenHeight * 0.015),
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
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
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning,
                  color: Colors.red.shade700,
                  size: screenWidth * 0.05,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emergencyType.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: screenWidth * 0.04,
                        color: Colors.red.shade700,
                      ),
                    ),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: screenWidth * 0.03,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
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

          SizedBox(height: screenHeight * 0.01),

          // Details
          Text(
            'Reporter: ${user['email'] ?? 'Unknown'}',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: screenHeight * 0.005),
          Text(
            'Location: $location',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: Colors.black87,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          SizedBox(height: screenHeight * 0.015),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding:
                        EdgeInsets.symmetric(vertical: screenHeight * 0.01),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _respondToIncident(
                    incident['id'].toString(),
                    'dispatched',
                  ),
                  child: Text(
                    'Dispatch',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: screenWidth * 0.035,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(width: screenWidth * 0.02),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding:
                        EdgeInsets.symmetric(vertical: screenHeight * 0.01),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _respondToIncident(
                    incident['id'].toString(),
                    'responding',
                  ),
                  child: Text(
                    'Respond',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: screenWidth * 0.035,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
      return 'Just now';
    }
  }

  @override
  void dispose() {
    _unsubscribeFromUserLocation();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
