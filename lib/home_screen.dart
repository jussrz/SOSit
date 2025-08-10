import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'profile_page.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _getCurrentLocation();
    _simulateDeviceStatus();
  }

  // Simulate device status for demonstration
  void _simulateDeviceStatus() {
    // This simulates checking for a panic button device
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
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsSignal = 'Disabled';
          _location = 'Location services disabled';
        });
        return;
      }

      // Check location permissions
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
          _location = 'Location permission permanently denied';
        });
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        // Determine GPS signal strength based on accuracy
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

      // Get address from coordinates
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          setState(() {
            _location = '${place.street ?? ''}, ${place.locality ?? ''}, ${place.subAdministrativeArea ?? ''}, ${place.administrativeArea ?? ''}';
          });
        }
      } catch (e) {
        setState(() {
          _location = '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }

      // Move camera to current location
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(position.latitude, position.longitude),
          ),
        );
      }

    } catch (e) {
      setState(() {
        _gpsSignal = 'Error';
        _location = 'Unable to get location';
      });
      debugPrint('Error getting location: $e');
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

  Future<void> _loadUserProfile() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      setState(() {
        // Keep device status as not connected until actual Bluetooth implementation
        _emergencyName = data['emergency_contact_name'] ?? '';
        _emergencyPhone = data['emergency_phone'] ?? '';
        _relationship = data['relationship'] ?? '';
        _emergencyName2 = data['emergency_contact_name2'] ?? '';
        _emergencyPhone2 = data['emergency_phone2'] ?? '';
        _relationship2 = data['relationship2'] ?? '';
        _profilePhotoUrl = data['profile_photo_url'] ?? '';
      });
    } catch (e) {
      debugPrint('Error loading emergency info: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map background
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(7.0731, 125.6124),
              zoom: 16,
            ),
            myLocationEnabled: true,
            mapType: MapType.normal,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              // If we already have current position, move camera to it
              if (_currentPosition != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLng(
                    LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  ),
                );
              }
            },
          ),

          // Top Card: Logo, Settings, Profile
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    )
                  ],
                ),
                child: SizedBox(
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Centered logo
                      Align(
                        alignment: Alignment.center,
                        child: SvgPicture.asset(
                          'assets/sositlogo.svg',
                          height: 18.73,
                        ),
                      ),
                      // Settings icon (left)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(Icons.settings, color: Colors.black),
                          onPressed: () {},
                        ),
                      ),
                      // Profile avatar (right)
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ProfilePage()),
                            ).then((_) => _loadUserProfile());
                          },
                          child: _profilePhotoUrl.isNotEmpty
                              ? CircleAvatar(
                                  radius: 22,
                                  backgroundImage: NetworkImage(_profilePhotoUrl),
                                )
                              : const CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Colors.grey,
                                  child: Icon(Icons.person, color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom Card: Safety Status
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        'Your Safety Status',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Device Status: ', style: TextStyle(fontWeight: FontWeight.w500)),
                        Text(_deviceStatus, style: TextStyle(color: _getDeviceStatusColor(_deviceStatus))),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('GPS Signal: ', style: TextStyle(fontWeight: FontWeight.w500)),
                        Text(_gpsSignal, style: TextStyle(color: _getGpsColor(_gpsSignal))),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Location: ', style: TextStyle(fontWeight: FontWeight.w500)),
                        Expanded(
                          child: Text(_location.isNotEmpty ? _location : 'Getting location...', 
                              style: const TextStyle(color: Colors.black87)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Emergency Contacts',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    
                    // First Emergency Contact
                    if (_emergencyName.isNotEmpty || _emergencyPhone.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person, size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(_emergencyName.isNotEmpty ? _emergencyName : 'No name provided',
                                    style: const TextStyle(fontWeight: FontWeight.w500)),
                              ],
                            ),
                            if (_relationship.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.family_restroom, size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(_relationship, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                ],
                              ),
                            ],
                            if (_emergencyPhone.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.phone, size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(_emergencyPhone, style: const TextStyle(color: Colors.blue)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    
                    // Second Emergency Contact
                    if (_emergencyName2.isNotEmpty || _emergencyPhone2.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person, size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(_emergencyName2.isNotEmpty ? _emergencyName2 : 'No name provided',
                                    style: const TextStyle(fontWeight: FontWeight.w500)),
                              ],
                            ),
                            if (_relationship2.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.family_restroom, size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(_relationship2, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                ],
                              ),
                            ],
                            if (_emergencyPhone2.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.phone, size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(_emergencyPhone2, style: const TextStyle(color: Colors.blue)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    
                    // Show message if no emergency contacts
                    if ((_emergencyName.isEmpty && _emergencyPhone.isEmpty) && 
                        (_emergencyName2.isEmpty && _emergencyPhone2.isEmpty)) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.orange.shade600, size: 16),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('No emergency contacts added yet',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
