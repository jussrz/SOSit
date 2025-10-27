import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'services/ble_service.dart';
import 'services/emergency_service.dart';
import 'main.dart'; // Import for EmergencyAlertHandler
import 'settings_page.dart';
import 'group_page.dart';
import 'emergency_contact_dashboard.dart'; // Import for switch view
import 'package:flutter/services.dart'; // <-- Add this import for rootBundle and MethodChannel

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String _gpsSignal = 'Getting signal...';
  String _cellularSignal = 'no signal';
  String _location = 'Getting location...';
  bool _hasSim = true;
  static const MethodChannel _simChannel = MethodChannel('sosit/sim');
  GoogleMapController? _mapController;
  bool _isLoadingProfile = false;
  bool _isCardExpanded = false;

  // Controllers to display user info
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthdateController = TextEditingController();

  // Connectivity for cellular detection
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // List to store all emergency contacts
  List<Map<String, dynamic>> _emergencyContacts = [];

  RealtimeChannel? _emergencyContactsChannel;
  bool _isSubscriptionActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isLoadingProfile = true;
    _loadUserProfile();
    _getCurrentLocation();
    _checkEmergencyContactStatus();
    _setupRealtimeSubscription();

    // Ensure BLE callback is set up after build completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureBLECallbackSetup();
    });

    // Initialize connectivity listener for cellular state
    _connectivity.checkConnectivity().then((result) {
      _checkSimPresence().then((_) => _updateCellularFromConnectivity(result));
    }).catchError((e) {
      debugPrint('Connectivity check failed: $e');
    });

    _connectivitySubscription = _connectivity.onConnectivityChanged
        .listen((result) => _checkSimPresence().then((_) => _updateCellularFromConnectivity(result)));
  }

  Future<void> _checkSimPresence() async {
    try {
      final hasSim = await _simChannel.invokeMethod<bool>('hasSim');
      if (hasSim != null) {
        if (mounted) {
          setState(() => _hasSim = hasSim);
        } else {
          _hasSim = hasSim;
        }
      }
    } catch (e) {
      // If platform channel fails (e.g., iOS or not implemented), assume SIM present
      debugPrint('SIM check failed or not available: $e');
      if (mounted) setState(() => _hasSim = true);
      else _hasSim = true;
    }
  }

  void _ensureBLECallbackSetup() {
    try {
      final bleService = Provider.of<BLEService>(context, listen: false);
      final emergencyService =
          Provider.of<EmergencyService>(context, listen: false);
      final alertHandler =
          Provider.of<EmergencyAlertHandler>(context, listen: false);

      print('🔥 HOME: Setting up BLE callback manually...');
      debugPrint('🔧 HomeScreen: Setting up BLE callback manually...');
      alertHandler.ensureCallbackSetup(bleService, emergencyService);
      print('🔥 HOME: BLE callback setup attempted');
      debugPrint('🔧 HomeScreen: BLE callback setup attempted');

      // Set up emergency service popup callback
      print('🔥 HOME: Setting up emergency popup callback...');
      emergencyService.setPopupCallback((alertType) {
        if (mounted) {
          print('🔥 HOME: Showing popup for $alertType');
          debugPrint('🎯 HomeScreen: Showing popup for $alertType');
          showPanicPopup(context, alertType);
        } else {
          print(
              '🔥 HOME: Widget not mounted - cannot show popup for $alertType');
        }
      });
      print('🔥 HOME: Emergency popup callback set');
      debugPrint('🎯 HomeScreen: Emergency popup callback set');
    } catch (e) {
      debugPrint('❌ HomeScreen: Failed to set up BLE callback: $e');
    }
  }

  void _updateCellularFromConnectivity(ConnectivityResult result) {
    // Map cellular status based on SIM presence and connectivity:
    // - If no SIM -> No Signal
    // - If SIM present and mobile data active -> Strong
    // - If SIM present and on WiFi (but no mobile) -> Weak (SIM exists but not using cellular)
    // - If SIM present and no connectivity -> No Signal
    String state;
    if (!_hasSim) {
      state = 'No Signal';
    } else {
      if (result == ConnectivityResult.mobile) {
        state = 'Strong';
      } else if (result == ConnectivityResult.wifi) {
        state = 'Weak';
      } else if (result == ConnectivityResult.none) {
        state = 'No Signal';
      } else {
        state = 'No Signal';
      }
    }

    if (mounted) {
      setState(() => _cellularSignal = state);
    } else {
      _cellularSignal = state;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      debugPrint('App resumed - refreshing data');
      refreshData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emergencyContactsChannel?.unsubscribe();
    _connectivitySubscription?.cancel();
    _emailController.dispose();
    _phoneController.dispose();
    _birthdateController.dispose();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId != null && !_isSubscriptionActive) {
      try {
        final channelName =
            'emergency_contacts_${userId}_${DateTime.now().millisecondsSinceEpoch}';
        debugPrint('Setting up realtime subscription: $channelName');

        _emergencyContactsChannel = supabase
            .channel(channelName)
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'emergency_contacts',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (payload) {
                debugPrint('Realtime update received: ${payload.eventType}');
                if (mounted) {
                  _loadUserProfile();
                }
              },
            )
            .subscribe();

        _isSubscriptionActive = true;
        debugPrint('Realtime subscription setup complete');
      } catch (e) {
        debugPrint('Error setting up realtime subscription: $e');
      }
    }
  }

  void refreshData() {
    if (mounted) {
      _loadUserProfile();
      _checkEmergencyContactStatus();
    }
  }

  Future<void> _checkEmergencyContactStatus() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Check if this user is listed as an emergency contact for others
      // Note: Since there's no emergency_contact_user_id column, check by phone/email
      try {
        final currentUserData = await supabase
            .from('user')
            .select('phone, email')
            .eq('id', userId)
            .single();

        await supabase
            .from('emergency_contacts')
            .select('id')
            .or('emergency_contact_phone.eq.${currentUserData['phone'] ?? ''},emergency_contact_phone.eq.${currentUserData['email'] ?? ''}')
            .count(CountOption.exact);

        // Check if this user is in any emergency groups
        await supabase
            .from('group_members')
            .select('id')
            .eq('user_id', userId)
            .count(CountOption.exact);
      } catch (e) {
        debugPrint(
            'Error checking emergency contact status by phone/email: $e');
      }
    } catch (e) {
      debugPrint('Error checking emergency contact status: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _gpsSignal = 'Getting signal...';
      _location = 'Getting location...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsSignal = 'Disabled';
          _location = 'Location services disabled';
        });
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _gpsSignal = 'No Permission';
            _location = 'Location permission denied';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _gpsSignal = 'Permission Denied';
          _location =
              'Location permission permanently denied. Please enable in settings.';
        });
        await Geolocator.openAppSettings();
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        if (position.accuracy <= 5) {
          _gpsSignal = 'Excellent';
        } else if (position.accuracy <= 10) {
          _gpsSignal = 'Good';
        } else if (position.accuracy <= 20) {
          _gpsSignal = 'Fair';
        } else {
          _gpsSignal = 'Poor';
        }
      });

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          String address = '';
          if (place.street != null && place.street!.isNotEmpty) {
            address += '${place.street}, ';
          }
          if (place.locality != null && place.locality!.isNotEmpty) {
            address += '${place.locality}, ';
          }
          if (place.subAdministrativeArea != null &&
              place.subAdministrativeArea!.isNotEmpty) {
            address += '${place.subAdministrativeArea}, ';
          }
          if (place.administrativeArea != null &&
              place.administrativeArea!.isNotEmpty) {
            address += place.administrativeArea!;
          }
          setState(() {
            _location = address.isNotEmpty ? address : 'Address not found';
          });
        }
      } catch (e) {
        setState(() {
          _location =
              'Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}';
        });
      }

      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 16.0,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _gpsSignal = 'Error';
        _location = 'Unable to get location: ${e.toString()}';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Location error: ${e.toString()}'),
              duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  Future<void> _loadUserProfile() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _isLoadingProfile = false;
      });
      return;
    }

    try {
      // Load basic user info
      final userData =
          await supabase.from('user').select().eq('id', userId).single();

      // Load all emergency contacts from correct table
      final emergencyData = await supabase
          .from('emergency_contacts')
          .select('*')
          .eq('user_id', userId)
          .order('created_at');

      // Debug prints
      debugPrint('Current UserId: $userId');
      debugPrint('Emergency Contacts Data: $emergencyData');

      // Log each contact's structure to see what columns exist
      for (var contact in emergencyData) {
        debugPrint('Contact structure: ${contact.keys.toList()}');
        debugPrint(
            'Available columns in emergency_contacts table: ${contact.keys.join(', ')}');
        debugPrint(
            'emergency_contact_name: ${contact['emergency_contact_name']}');
        debugPrint(
            'emergency_contact_phone: ${contact['emergency_contact_phone']}');
      }

      setState(() {
        _isLoadingProfile = false;
        _emailController.text = userData['email'] ?? '';
        _phoneController.text = userData['phone'] ?? '';
        _birthdateController.text = userData['birthdate'] ?? '';
        _emergencyContacts = List<Map<String, dynamic>>.from(emergencyData);
      });

      // Automatically update emergency contacts to link to existing users
      _updateEmergencyContactsWithUserLinks();
    } catch (e) {
      setState(() {
        _isLoadingProfile = false;
        _emergencyContacts = [];
      });
      debugPrint('Error loading profile or emergency contacts: $e');
    }
  }

  // Method to update emergency contacts to link to existing users
  Future<void> _updateEmergencyContactsWithUserLinks() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // First, let's see what columns exist in the emergency_contacts table
      final emergencyData = await supabase
          .from('emergency_contacts')
          .select('*')
          .eq('user_id', userId)
          .limit(1);

      if (emergencyData.isNotEmpty) {
        debugPrint(
            'Emergency contacts table columns: ${emergencyData.first.keys.join(', ')}');

        // Check if we have a user linking column
        bool hasUserIdColumn =
            emergencyData.first.containsKey('emergency_contact_user_id');
        bool hasContactIdColumn =
            emergencyData.first.containsKey('contact_user_id');
        bool hasLinkedUserIdColumn =
            emergencyData.first.containsKey('linked_user_id');

        debugPrint('Has emergency_contact_user_id: $hasUserIdColumn');
        debugPrint('Has contact_user_id: $hasContactIdColumn');
        debugPrint('Has linked_user_id: $hasLinkedUserIdColumn');

        if (!hasUserIdColumn && !hasContactIdColumn && !hasLinkedUserIdColumn) {
          debugPrint(
              '❌ No user linking column found. Emergency contacts can only show initials.');
          debugPrint(
              '💡 To show profile photos, you need to add a user linking column to the emergency_contacts table.');
          return;
        }
      }

      // Since the column doesn't exist, we can't do automatic linking
      debugPrint(
          '❌ Cannot perform automatic user linking - database schema needs to be updated');
      debugPrint(
          '💡 Your emergency contacts table needs an emergency_contact_user_id column to link to users');
    } catch (e) {
      debugPrint('Error checking emergency contact schema: $e');
    }
  }

  Color _getDeviceStatusColor(String status) {
    if (status.toLowerCase().contains('connected') &&
        !status.toLowerCase().contains('not')) {
      return Colors.green;
    } else if (status.toLowerCase().contains('searching') ||
        status.toLowerCase().contains('found')) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  Color _getGpsColor(String signal) {
    switch (signal.toLowerCase()) {
      case 'excellent':
      case 'good':
        return Colors.green;
      case 'fair':
        return Colors.orange;
      case 'poor':
      case 'error':
      case 'disabled':
      case 'no permission':
      case 'permission denied':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getCellularColor(String signal) {
    switch (signal.toLowerCase()) {
      case 'strong':
        return Colors.green;
      case 'weak':
        return Colors.orange;
      case 'no signal':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showSwitchViewDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch View'),
        content: const Text(
            'Do you want to switch to Emergency Contact Dashboard? This view shows alerts from people who have listed you as their emergency contact.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const EmergencyContactDashboard()),
              );
              refreshData();
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF73D5C),
            ),
            child: const Text('Go to Emergency Contact Dashboard'),
          ),
        ],
      ),
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
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(7.0731, 125.6124),
              zoom: 16,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
            compassEnabled: true,
            onMapCreated: (controller) => _mapController = controller,
          ),

          // Top Card: Settings + Logo + Switch View (removed profile button)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.04,
                    vertical: screenHeight * 0.01),
                padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.04,
                    vertical: screenHeight * 0.01),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 2))
                  ],
                ),
                child: Row(
                  children: [
                    // Settings icon
                    GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SettingsPage()));
                        refreshData();
                      },
                      child: Icon(Icons.settings,
                          color: const Color(0xFFF73D5C),
                          size: screenWidth * 0.07),
                    ),

                    // SOSit Logo in the center
                    Expanded(
                      child: Center(
                          child: _buildSositLogo(screenWidth, screenHeight)),
                    ),

                    // Switch View button (moved to the right where profile was)
                    GestureDetector(
                      onTap: _showSwitchViewDialog,
                      child: Icon(
                        Icons.swap_horiz,
                        color: const Color(0xFFF73D5C),
                        size: screenWidth * 0.09,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Group FAB
          Positioned(
            right: screenWidth * 0.05,
            bottom: screenHeight *
                0.45, // moved to previous emergency button position
            child: FloatingActionButton(
              heroTag: 'group_fab',
              backgroundColor: Colors.white,
              elevation: 4,
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GroupPage(),
                  ),
                );
                refreshData();
              },
              child:
                  Icon(Icons.groups, color: const Color(0xFFF73D5C), size: 32),
            ),
          ),

          // Bottom Card: Safety Status & Emergency Contacts
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
                height: _isCardExpanded ? screenHeight * 0.7 : null,
                constraints: _isCardExpanded
                    ? null
                    : BoxConstraints(
                        maxHeight: screenHeight * 0.4,
                        minHeight: screenHeight * 0.2),
                margin: EdgeInsets.symmetric(
                    horizontal: _isCardExpanded ? 0 : screenWidth * 0.04),
                padding: EdgeInsets.symmetric(
                    vertical: screenHeight * 0.02,
                    horizontal: screenWidth * 0.045),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(_isCardExpanded ? 24 : 20),
                    topRight: Radius.circular(_isCardExpanded ? 24 : 20),
                    bottomLeft: Radius.circular(_isCardExpanded ? 0 : 20),
                    bottomRight: Radius.circular(_isCardExpanded ? 0 : 20),
                  ),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, -4))
                  ],
                ),
                child: _isCardExpanded
                    ? _buildExpandedCard(screenWidth, screenHeight)
                    : _buildCollapsedCard(screenWidth, screenHeight),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Add this function to show the correct popup based on the button action
  void showPanicPopup(BuildContext context, String type) {
    String title = '';
    String message = '';
    Color color = const Color(0xFFF73D5C);

    switch (type) {
      case 'regular':
        title = 'Regular Alert';
        message =
            'A regular emergency alert has been sent.\nHelp is on the way.';
        color = const Color(0xFFF73D5C);
        break;
      case 'checkin':
        title = 'Check In/Test';
        message =
            'This is a test/check-in alert.\nNo emergency response will be dispatched.';
        color = Colors.blue;
        break;
      case 'critical':
        title = 'Critical Emergency';
        message =
            'A critical emergency alert has been sent.\nImmediate response is being dispatched!';
        color = Colors.red;
        break;
      case 'cancel':
        title = 'Cancelled / False Alarm';
        message =
            'Your emergency alert has been cancelled.\nNo further action will be taken.';
        color = Colors.green;
        break;
      default:
        title = 'Alert';
        message = '';
        color = const Color(0xFFF73D5C);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Auto-dismiss after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && dialogContext.mounted) {
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          }
        });

        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                // Icon with colored circle
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    type == 'cancel'
                        ? Icons.check_circle
                        : type == 'checkin'
                            ? Icons.info
                            : type == 'critical'
                                ? Icons.warning_amber_rounded
                                : Icons.warning,
                    color: color,
                    size: 54,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollapsedCard(double screenWidth, double screenHeight) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: screenWidth * 0.12,
            height: 4,
            margin: EdgeInsets.only(bottom: screenHeight * 0.015),
            decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2))),
        Text('Your Safety Status',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: screenWidth * 0.045)),
        const SizedBox(height: 12),
        _buildStatusInfo(),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.keyboard_arrow_up,
              color: Colors.grey.shade600, size: screenWidth * 0.05),
          const SizedBox(width: 4),
          Text('Swipe up for Emergency Contacts',
              style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: screenWidth * 0.03,
                  fontStyle: FontStyle.italic)),
        ]),
      ],
    );
  }

  Widget _buildExpandedCard(double screenWidth, double screenHeight) {
    return Column(
      children: [
        Container(
            width: screenWidth * 0.12,
            height: 4,
            margin: EdgeInsets.only(bottom: screenHeight * 0.015),
            decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2))),
        Text('Your Safety Status',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: screenWidth * 0.045)),
        const SizedBox(height: 12),
        _buildStatusInfo(),
        const SizedBox(height: 20),
        Row(children: [
          Text('Emergency Contacts',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: screenWidth * 0.04)),
          const Spacer(),
          Icon(Icons.keyboard_arrow_down,
              color: Colors.grey.shade600, size: screenWidth * 0.05),
        ]),
        const SizedBox(height: 12),
        Expanded(
            child: SingleChildScrollView(child: _buildEmergencyContacts())),
      ],
    );
  }

  Widget _buildStatusInfo() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Consumer2<BLEService, EmergencyService>(
      builder: (context, bleService, emergencyService, child) {
        return Column(
          children: [
            // Panic Button Status
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Device Status: ',
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: screenWidth * 0.035)),
                Expanded(
                    child: Text(bleService.connectionStatus,
                        style: TextStyle(
                            color: _getDeviceStatusColor(
                                bleService.connectionStatus),
                            fontSize: screenWidth * 0.035))),
              ],
            ),
            SizedBox(height: screenHeight * 0.005),

            // Battery Level (if connected)
            if (bleService.isConnected) ...[
              Row(
                children: [
                  Text('Battery: ',
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: screenWidth * 0.035)),
                  Text('${bleService.batteryLevel}%',
                      style: TextStyle(
                          color: bleService.batteryLevel > 20
                              ? Colors.green
                              : Colors.red,
                          fontSize: screenWidth * 0.035)),
                ],
              ),
              SizedBox(height: screenHeight * 0.005),
            ],

            // Emergency Status
            if (emergencyService.isEmergencyActive) ...[
              Row(
                children: [
                  Text('Emergency: ',
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: screenWidth * 0.035)),
                  Text('${emergencyService.activeEmergencyType} ACTIVE',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: screenWidth * 0.035,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              SizedBox(height: screenHeight * 0.005),
            ],

            // Cellular Status
            Row(
              children: [
                Text('Cellular: ',
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: screenWidth * 0.035)),
                Text(_cellularSignal,
                    style: TextStyle(
                        color: _getCellularColor(_cellularSignal),
                        fontSize: screenWidth * 0.035)),
              ],
            ),
            SizedBox(height: screenHeight * 0.005),

            // GPS Status
            Row(
              children: [
                Text('GPS Signal: ',
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: screenWidth * 0.035)),
                Text(_gpsSignal,
                    style: TextStyle(
                        color: _getGpsColor(_gpsSignal),
                        fontSize: screenWidth * 0.035)),
              ],
            ),
            SizedBox(height: screenHeight * 0.005),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Location: ',
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: screenWidth * 0.035)),
                Expanded(
                  child: Text(
                      _location.isNotEmpty ? _location : 'Getting location...',
                      style: TextStyle(
                          color: Colors.black87, fontSize: screenWidth * 0.035),
                      maxLines: _isCardExpanded ? null : 2,
                      overflow: _isCardExpanded ? null : TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmergencyContacts() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    if (_isLoadingProfile) {
      return Padding(
        padding: EdgeInsets.all(screenWidth * 0.05),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // Check if there are no emergency contacts
    if (_emergencyContacts.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(screenWidth * 0.05),
        child: Center(
          child: Text(
            'No emergency contact/s added yet',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final contact in _emergencyContacts)
          Container(
            margin: EdgeInsets.only(bottom: screenHeight * 0.015),
            padding: EdgeInsets.all(screenWidth * 0.04),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: screenWidth * 0.12,
                  height: screenWidth * 0.12,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF73D5C).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _getInitials(contact['emergency_contact_name'] ?? ''),
                      style: TextStyle(
                        color: const Color(0xFFF73D5C),
                        fontSize: screenWidth * 0.035,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: screenWidth * 0.04),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact['emergency_contact_name'] ?? '',
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.002),
                      Text(
                        contact['emergency_contact_relationship'] ?? '',
                        style: TextStyle(
                          fontSize: screenWidth * 0.035,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.002),
                      Text(
                        contact['emergency_contact_phone'] ?? '',
                        style: TextStyle(
                          fontSize: screenWidth * 0.035,
                          color: const Color(0xFF2196F3),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Emergency System Status
        Consumer<EmergencyService>(
          builder: (context, emergencyService, child) {
            return Container(
              margin: EdgeInsets.only(top: screenHeight * 0.02),
              padding: EdgeInsets.all(screenWidth * 0.04),
              decoration: BoxDecoration(
                color: emergencyService.isEmergencySystemReady()
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: emergencyService.isEmergencySystemReady()
                        ? Colors.green.shade200
                        : Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    emergencyService.isEmergencySystemReady()
                        ? Icons.check_circle
                        : Icons.warning,
                    color: emergencyService.isEmergencySystemReady()
                        ? Colors.green
                        : Colors.orange,
                    size: screenWidth * 0.05,
                  ),
                  SizedBox(width: screenWidth * 0.03),
                  Expanded(
                    child: Text(
                      emergencyService.getSystemStatus(),
                      style: TextStyle(
                        fontSize: screenWidth * 0.035,
                        color: emergencyService.isEmergencySystemReady()
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSositLogo(double screenWidth, double screenHeight) {
    return FutureBuilder<bool>(
      future: _checkAssetExists('assets/sositlogo.svg'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: screenWidth * 0.06,
            child: Text(
              'SOSit',
              style: TextStyle(
                fontSize: screenWidth * 0.06,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFF73D5C),
                letterSpacing: 0.5,
              ),
            ),
          );
        }

        if (snapshot.data == true) {
          return SvgPicture.asset(
            'assets/sositlogo.svg',
            height: screenWidth * 0.06,
            width: screenWidth * 0.25,
            placeholderBuilder: (context) =>
                _buildFallbackLogo(screenWidth, screenHeight),
          );
        } else {
          return _buildFallbackLogo(screenWidth, screenHeight);
        }
      },
    );
  }

  Widget _buildFallbackLogo(double screenWidth, double screenHeight) {
    return Text(
      'SOSit',
      style: TextStyle(
        fontSize: screenWidth * 0.06,
        fontWeight: FontWeight.bold,
        color: const Color(0xFFF73D5C),
        letterSpacing: 0.5,
      ),
    );
  }

  // Helper method to get initials from a name
  String _getInitials(String name) {
    if (name.isEmpty) return '?';

    List<String> nameParts = name.trim().split(' ');
    if (nameParts.length == 1) {
      return nameParts[0].substring(0, 1).toUpperCase();
    } else {
      return (nameParts[0].substring(0, 1) +
              nameParts[nameParts.length - 1].substring(0, 1))
          .toUpperCase();
    }
  }

  Future<bool> _checkAssetExists(String assetPath) async {
    try {
      // Try DefaultAssetBundle first (works in widget tree)
      await DefaultAssetBundle.of(context).load(assetPath);
      return true;
    } catch (e) {
      try {
        // Fallback to rootBundle (works outside widget tree)
        await rootBundle.load(assetPath);
        return true;
      } catch (e) {
        debugPrint('Asset not found: $assetPath');
        return false;
      }
    }
  }
}
