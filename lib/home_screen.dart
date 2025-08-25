import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

    setState(() {
      _isLoadingProfile = false;

      // Basic profile info
      _profilePhotoUrl = userData['profile_photo_url'] ?? '';
      _emailController.text = userData['email'] ?? '';
      _phoneController.text = userData['phone'] ?? '';
      _birthdateController.text = userData['birthdate'] ?? '';

      // Emergency contacts
      if (emergencyData.isNotEmpty) {
        _emergencyName = emergencyData[0]['emergency_contact_name'] ?? '';
        _emergencyPhone = emergencyData[0]['emergency_contact_phone'] ?? '';
        _relationship = emergencyData[0]['emergency_contact_relationship'] ?? '';
      }
      if (emergencyData.length > 1) {
        _emergencyName2 = emergencyData[1]['emergency_contact_name'] ?? '';
        _emergencyPhone2 = emergencyData[1]['emergency_contact_phone'] ?? '';
        _relationship2 = emergencyData[1]['emergency_contact_relationship'] ?? '';
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
                margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.02, vertical: screenHeight * 0.01),
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04, vertical: screenHeight * 0.015),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Settings icon
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
                          child: Icon(Icons.settings, color: const Color(0xFFF73D5C), size: screenWidth * 0.09),
                        ),
                        const Spacer(),
                        // Profile avatar
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()))
                              .then((_) => _loadUserProfile()),
                          child: _profilePhotoUrl.isNotEmpty
                              ? CircleAvatar(radius: screenWidth * 0.055, backgroundImage: NetworkImage(_profilePhotoUrl))
                              : CircleAvatar(
                                  radius: screenWidth * 0.055,
                                  backgroundColor: const Color(0xFFF73D5C),
                                  child: Icon(Icons.person, color: Colors.white, size: screenWidth * 0.07),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Display basic profile info
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Email: ${_emailController.text}', style: TextStyle(fontSize: screenWidth * 0.035)),
                        Text('Phone: ${_phoneController.text}', style: TextStyle(fontSize: screenWidth * 0.035)),
                        Text('Birthdate: ${_birthdateController.text}', style: TextStyle(fontSize: screenWidth * 0.035)),
                      ],
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
              onTap: () => setState(() => _isCardExpanded = !_isCardExpanded),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_emergencyName.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: screenHeight * 0.01),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Name: $_emergencyName', style: TextStyle(fontSize: screenWidth * 0.035)),
              Text('Phone: $_emergencyPhone', style: TextStyle(fontSize: screenWidth * 0.035)),
              Text('Relationship: $_relationship', style: TextStyle(fontSize: screenWidth * 0.035)),
            ]),
          ),
        if (_emergencyName2.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: screenHeight * 0.01),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Name: $_emergencyName2', style: TextStyle(fontSize: screenWidth * 0.035)),
              Text('Phone: $_emergencyPhone2', style: TextStyle(fontSize: screenWidth * 0.035)),
              Text('Relationship: $_relationship2', style: TextStyle(fontSize: screenWidth * 0.035)),
            ]),
          ),
      ],
    );
  }
}
