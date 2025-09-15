import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'services/emergency_service.dart';
import 'profile_page.dart';
import 'settings_page.dart';
import 'group_page.dart';
import 'emergency_contact_dashboard.dart'; // Import for switch view
import 'package:flutter/services.dart'; // <-- Add this import for rootBundle

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _gpsSignal = 'Getting signal...';
  String _location = 'Getting location...';
  String _emergencyName = '';
  String _emergencyPhone = '';
  String _relationship = '';
  String _emergencyName2 = '';
  String _emergencyPhone2 = '';
  String _relationship2 = '';
  String _profilePhotoUrl = '';
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _isLoadingProfile = false;
  bool _isCardExpanded = false;

  // Track if user has emergency contact status
  bool _isEmergencyContactForOthers = false;
  bool _checkingEmergencyContactStatus = true;

  // Controllers to display user info
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthdateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isLoadingProfile = true;
    _loadUserProfile();
    _getCurrentLocation();
    _checkEmergencyContactStatus();
  }

  Future<void> _checkEmergencyContactStatus() async {
    setState(() => _checkingEmergencyContactStatus = true);

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Check if this user is listed as an emergency contact for others
      final emergencyContactCount = await supabase
          .from('emergency_contacts')
          .select('id')
          .eq('emergency_contact_user_id', userId)
          .count(CountOption.exact);

      // Check if this user is in any emergency groups
      final groupMembershipCount = await supabase
          .from('group_memberships')
          .select('id')
          .eq('user_id', userId)
          .count(CountOption.exact);

      setState(() {
        _isEmergencyContactForOthers =
            (emergencyContactCount.data.length > 0) ||
                (groupMembershipCount.data.length > 0);
        _checkingEmergencyContactStatus = false;
      });
    } catch (e) {
      debugPrint('Error checking emergency contact status: $e');
      setState(() {
        _isEmergencyContactForOthers = false;
        _checkingEmergencyContactStatus = false;
      });
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
        _currentPosition = position;
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

      // Load emergency contacts (limit 2)
      final emergencyData = await supabase
          .from('emergency_contacts')
          .select()
          .eq('user_id', userId)
          .order('created_at')
          .limit(2);

      setState(() {
        _isLoadingProfile = false;

        // Basic profile info
        _profilePhotoUrl = userData['profile_photo_url'] ?? '';
        _emailController.text = userData['email'] ?? '';
        _phoneController.text = userData['phone'] ?? '';
        _birthdateController.text = userData['birthdate'] ?? '';

        // Clear previous emergency contact data
        _emergencyName = '';
        _emergencyPhone = '';
        _relationship = '';
        _emergencyName2 = '';
        _emergencyPhone2 = '';
        _relationship2 = '';

        // Emergency contacts
        if (emergencyData.isNotEmpty) {
          _emergencyName = emergencyData[0]['emergency_contact_name'] ?? '';
          _emergencyPhone = emergencyData[0]['emergency_contact_phone'] ?? '';
          _relationship =
              emergencyData[0]['emergency_contact_relationship'] ?? '';
        }
        if (emergencyData.length > 1) {
          _emergencyName2 = emergencyData[1]['emergency_contact_name'] ?? '';
          _emergencyPhone2 = emergencyData[1]['emergency_contact_phone'] ?? '';
          _relationship2 =
              emergencyData[1]['emergency_contact_relationship'] ?? '';
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingProfile = false;
      });
      debugPrint('Error loading profile or emergency contacts: $e');
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
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                    builder: (_) => const EmergencyContactDashboard()),
              );
            },
            child: const Text('Go to Emergency Contact Dashboard'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF73D5C),
            ),
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

          // Top Card: Settings + Logo + Profile + Switch View
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
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsPage())),
                      child: Icon(Icons.settings,
                          color: const Color(0xFFF73D5C),
                          size: screenWidth * 0.07),
                    ),

                    // SOSit Logo in the center
                    Expanded(
                      child: Center(
                          child: _buildSositLogo(screenWidth, screenHeight)),
                    ),

                    // Switch View button (always visible)
                    GestureDetector(
                      onTap: _showSwitchViewDialog,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF73D5C).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.swap_horiz,
                          color: const Color(0xFFF73D5C),
                          size: screenWidth * 0.06,
                        ),
                      ),
                    ),
                    SizedBox(width: screenWidth * 0.02),

                    // Profile avatar
                    GestureDetector(
                      onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ProfilePage()))
                          .then((_) => _loadUserProfile()),
                      child: _profilePhotoUrl.isNotEmpty
                          ? CircleAvatar(
                              radius: screenWidth * 0.045,
                              backgroundImage: NetworkImage(_profilePhotoUrl))
                          : CircleAvatar(
                              radius: screenWidth * 0.045,
                              backgroundColor: const Color(0xFFF73D5C),
                              child: Icon(Icons.person,
                                  color: Colors.white,
                                  size: screenWidth * 0.05),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Group FAB above emergency alert button
          Positioned(
            right: screenWidth * 0.05,
            bottom: screenHeight * 0.58, // adjust as needed
            child: FloatingActionButton(
              heroTag: 'group_fab',
              backgroundColor: Colors.white,
              elevation: 4,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GroupPage(),
                ),
              ),
              child:
                  Icon(Icons.groups, color: const Color(0xFFF73D5C), size: 32),
            ),
          ),

          // Floating Emergency Button
          Positioned(
            right: screenWidth * 0.05,
            bottom: screenHeight * 0.45,
            child: Consumer<EmergencyService>(
              builder: (context, emergencyService, child) {
                return FloatingActionButton(
                  onPressed: emergencyService.isEmergencyActive
                      ? () =>
                          emergencyService.handleEmergencyAlert('CANCEL', null)
                      : () => _showEmergencyDialog(emergencyService),
                  backgroundColor: emergencyService.isEmergencyActive
                      ? Colors.orange
                      : const Color(0xFFF73D5C),
                  child: Icon(
                    emergencyService.isEmergencyActive
                        ? Icons.stop
                        : Icons.warning,
                    color: Colors.white,
                    size: 30,
                  ),
                );
              },
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

  void _showEmergencyDialog(EmergencyService emergencyService) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Emergency Alert'),
          content: const Text('Choose emergency type:'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                emergencyService.triggerManualEmergency('CHECKIN');
              },
              child: const Text('Check-in'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                emergencyService.triggerManualEmergency('REGULAR');
              },
              child: const Text('Regular'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                emergencyService.triggerManualEmergency('CRITICAL');
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('CRITICAL'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showSosPopup(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isHolding = false;
        late DateTime holdStart;

        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Stack(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    // SOS Button with concentric circles
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF73D5C).withOpacity(0.2),
                          ),
                        ),
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF73D5C).withOpacity(0.4),
                          ),
                        ),
                        GestureDetector(
                          onLongPressStart: (_) {
                            isHolding = true;
                            holdStart = DateTime.now();
                          },
                          onLongPressEnd: (_) {
                            isHolding = false;
                            if (DateTime.now()
                                    .difference(holdStart)
                                    .inSeconds >=
                                3) {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              }
                            }
                          },
                          child: Container(
                            width: 90,
                            height: 90,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFF73D5C),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'SOS',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 28,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'You have pressed the panic button!',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    RichText(
                      textAlign: TextAlign.center,
                      text: const TextSpan(
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                        ),
                        children: [
                          TextSpan(text: 'add text pa'),
                          TextSpan(
                            text: 'SOS',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF73D5C),
                            ),
                          ),
                          TextSpan(text: ' for cancel'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // No countdown
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              // Close button
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  child: const Icon(Icons.close, color: Colors.grey, size: 26),
                ),
              ),
            ],
          ),
        );
      },
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
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Stack(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                        color: color.withOpacity(0.15),
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
              // Close button
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  child: const Icon(Icons.close, color: Colors.grey, size: 26),
                ),
              ),
            ],
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
    if (_emergencyName.isEmpty && _emergencyName2.isEmpty) {
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
        // First Emergency Contact
        if (_emergencyName.isNotEmpty)
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
                // Person Icon
                Container(
                  padding: EdgeInsets.all(screenWidth * 0.025),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF73D5C).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    color: const Color(0xFFF73D5C),
                    size: screenWidth * 0.06,
                  ),
                ),
                SizedBox(width: screenWidth * 0.04),
                // Contact Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _emergencyName,
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.002),
                      Text(
                        _relationship,
                        style: TextStyle(
                          fontSize: screenWidth * 0.035,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.002),
                      Text(
                        _emergencyPhone,
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

        // Second Emergency Contact
        if (_emergencyName2.isNotEmpty)
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
                // Person Icon
                Container(
                  padding: EdgeInsets.all(screenWidth * 0.025),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF73D5C).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    color: const Color(0xFFF73D5C),
                    size: screenWidth * 0.06,
                  ),
                ),
                SizedBox(width: screenWidth * 0.04),
                // Contact Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _emergencyName2,
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.002),
                      Text(
                        _relationship2,
                        style: TextStyle(
                          fontSize: screenWidth * 0.035,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.002),
                      Text(
                        _emergencyPhone2,
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
