import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart'; // Add this import back
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'profile_page.dart';
import 'settings_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _deviceStatus = 'Panic Button Not Connected';
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
    _simulateDeviceStatus();
  }

  // Simulate device status
  void _simulateDeviceStatus() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _deviceStatus = 'Searching for Panic Button...';
        });
      }
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _deviceStatus = 'Panic Button Not Found';
        });
      }
    });
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
          _location = 'Location permission permanently denied. Please enable in settings.';
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
        if (position.accuracy <= 5) _gpsSignal = 'Excellent';
        else if (position.accuracy <= 10) _gpsSignal = 'Good';
        else if (position.accuracy <= 20) _gpsSignal = 'Fair';
        else _gpsSignal = 'Poor';
      });

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          String address = '';
          if (place.street != null && place.street!.isNotEmpty) address += '${place.street}, ';
          if (place.locality != null && place.locality!.isNotEmpty) address += '${place.locality}, ';
          if (place.subAdministrativeArea != null && place.subAdministrativeArea!.isNotEmpty)
            address += '${place.subAdministrativeArea}, ';
          if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty)
            address += place.administrativeArea!;
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
          SnackBar(content: Text('Location error: ${e.toString()}'), duration: const Duration(seconds: 3)),
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
    final userData = await supabase.from('user').select().eq('id', userId).single();

    // Load emergency contacts (limit 2 for this example)
    final emergencyData = await supabase
        .from('emergency_contacts')
        .select()
        .eq('user_id', userId)
        .order('created_at')
        .limit(2);

    // Add debugging
    debugPrint('Emergency contacts from home_screen: $emergencyData');
    debugPrint('Number of contacts found: ${emergencyData.length}');

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
        _relationship = emergencyData[0]['emergency_contact_relationship'] ?? '';
        debugPrint('First contact loaded: $_emergencyName');
      }
      if (emergencyData.length > 1) {
        _emergencyName2 = emergencyData[1]['emergency_contact_name'] ?? '';
        _emergencyPhone2 = emergencyData[1]['emergency_contact_phone'] ?? '';
        _relationship2 = emergencyData[1]['emergency_contact_relationship'] ?? '';
        debugPrint('Second contact loaded: $_emergencyName2');
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
    if (status.toLowerCase().contains('connected') && !status.toLowerCase().contains('not')) {
      return Colors.green;
    } else if (status.toLowerCase().contains('searching')) {
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

          // Top Card: Profile + Settings
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.04, vertical: screenHeight * 0.01),
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04, vertical: screenHeight * 0.01),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: Row(
                  children: [
                    // Settings icon
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
                      child: Icon(Icons.settings, color: const Color(0xFFF73D5C), size: screenWidth * 0.07),
                    ),
                    // SOSit Logo in the center
                    Expanded(
                      child: Center(
                        child: _buildSositLogo(screenWidth, screenHeight),
                      ),
                    ),
                    // Profile avatar
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()))
                          .then((_) => _loadUserProfile()),
                      child: _profilePhotoUrl.isNotEmpty
                          ? CircleAvatar(radius: screenWidth * 0.045, backgroundImage: NetworkImage(_profilePhotoUrl))
                          : CircleAvatar(
                              radius: screenWidth * 0.045,
                              backgroundColor: const Color(0xFFF73D5C),
                              child: Icon(Icons.person, color: Colors.white, size: screenWidth * 0.05),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Card: Safety Status & Emergency Contacts
          Positioned(
            left: 0,
            right: 0,
            bottom: _isCardExpanded ? 0 : screenHeight * 0.03,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                // Detect upward swipe
                if (details.delta.dy < -5 && !_isCardExpanded) {
                  setState(() => _isCardExpanded = true);
                }
                // Detect downward swipe
                else if (details.delta.dy > 5 && _isCardExpanded) {
                  setState(() => _isCardExpanded = false);
                }
              },
              onTap: () => setState(() => _isCardExpanded = !_isCardExpanded), // Keep tap as backup
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _isCardExpanded ? screenHeight * 0.7 : null,
                constraints: _isCardExpanded
                    ? null
                    : BoxConstraints(maxHeight: screenHeight * 0.4, minHeight: screenHeight * 0.2),
                margin: EdgeInsets.symmetric(horizontal: _isCardExpanded ? 0 : screenWidth * 0.04),
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02, horizontal: screenWidth * 0.045),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(_isCardExpanded ? 24 : 20),
                    topRight: Radius.circular(_isCardExpanded ? 24 : 20),
                    bottomLeft: Radius.circular(_isCardExpanded ? 0 : 20),
                    bottomRight: Radius.circular(_isCardExpanded ? 0 : 20),
                  ),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, -4))],
                ),
                child: _isCardExpanded ? _buildExpandedCard(screenWidth, screenHeight) : _buildCollapsedCard(screenWidth, screenHeight),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedCard(double screenWidth, double screenHeight) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: screenWidth * 0.12, height: 4, margin: EdgeInsets.only(bottom: screenHeight * 0.015), decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
        Text('Your Safety Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: screenWidth * 0.045)),
        const SizedBox(height: 12),
        _buildStatusInfo(),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.keyboard_arrow_up, color: Colors.grey.shade600, size: screenWidth * 0.05),
          const SizedBox(width: 4),
          Text('Swipe up for Emergency Contacts', style: TextStyle(color: Colors.grey.shade600, fontSize: screenWidth * 0.03, fontStyle: FontStyle.italic)),
        ]),
      ],
    );
  }

  Widget _buildExpandedCard(double screenWidth, double screenHeight) {
    return Column(
      children: [
        Container(width: screenWidth * 0.12, height: 4, margin: EdgeInsets.only(bottom: screenHeight * 0.015), decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
        Text('Your Safety Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: screenWidth * 0.045)),
        const SizedBox(height: 12),
        _buildStatusInfo(),
        const SizedBox(height: 20),
        Row(children: [
          Text('Emergency Contacts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: screenWidth * 0.04)),
          const Spacer(),
          Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600, size: screenWidth * 0.05),
        ]),
        const SizedBox(height: 12),
        Expanded(child: SingleChildScrollView(child: _buildEmergencyContacts())),
      ],
    );
  }

  Widget _buildStatusInfo() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device Status: ', style: TextStyle(fontWeight: FontWeight.w500, fontSize: screenWidth * 0.035)),
            Expanded(child: Text(_deviceStatus, style: TextStyle(color: _getDeviceStatusColor(_deviceStatus), fontSize: screenWidth * 0.035))),
          ],
        ),
        SizedBox(height: screenHeight * 0.005),
        Row(
          children: [
            Text('GPS Signal: ', style: TextStyle(fontWeight: FontWeight.w500, fontSize: screenWidth * 0.035)),
            Text(_gpsSignal, style: TextStyle(color: _getGpsColor(_gpsSignal), fontSize: screenWidth * 0.035)),
          ],
        ),
        SizedBox(height: screenHeight * 0.005),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Location: ', style: TextStyle(fontWeight: FontWeight.w500, fontSize: screenWidth * 0.035)),
            Expanded(
              child: Text(_location.isNotEmpty ? _location : 'Getting location...',
                  style: TextStyle(color: Colors.black87, fontSize: screenWidth * 0.035),
                  maxLines: _isCardExpanded ? null : 2,
                  overflow: _isCardExpanded ? null : TextOverflow.ellipsis),
            ),
          ],
        ),
      ],
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
      ],
    );
  }

  Widget _buildSositLogo(double screenWidth, double screenHeight) {
    return FutureBuilder<bool>(
      future: _checkAssetExists('assets/sositlogo.svg'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: screenWidth * 0.06, // Increased size
            child: Text(
              'SOSit',
              style: TextStyle(
                fontSize: screenWidth * 0.06, // Increased size
                fontWeight: FontWeight.bold,
                color: const Color(0xFFF73D5C),
                letterSpacing: 0.5,
              ),
            ),
          );
        }
        
        if (snapshot.data == true) {
          // SVG exists, try to load it
          return SvgPicture.asset(
            'assets/sositlogo.svg',
            height: screenWidth * 0.06, // Increased size
            width: screenWidth * 0.25, // Increased width
            placeholderBuilder: (context) => _buildFallbackLogo(screenWidth, screenHeight),
          );
        } else {
          // SVG doesn't exist, show fallback
          return _buildFallbackLogo(screenWidth, screenHeight);
        }
      },
    );
  }

  Widget _buildFallbackLogo(double screenWidth, double screenHeight) {
    return Text(
      'SOSit',
      style: TextStyle(
        fontSize: screenWidth * 0.06, // Increased size
        fontWeight: FontWeight.bold,
        color: const Color(0xFFF73D5C),
        letterSpacing: 0.5,
      ),
    );
  }

  Future<bool> _checkAssetExists(String assetPath) async {
    try {
      await DefaultAssetBundle.of(context).load(assetPath);
      return true;
    } catch (e) {
      debugPrint('Asset not found: $assetPath');
      return false;
    }
  }
}