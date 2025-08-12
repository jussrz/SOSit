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
  bool _isCardExpanded = false; // Add this for card expansion state

  @override
  void initState() {
    super.initState();
    setState(() {
      _isLoadingProfile = true;
    });
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
    setState(() {
      _gpsSignal = 'Getting signal...';
      _location = 'Getting location...';
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsSignal = 'Disabled';
          _location = 'Location services disabled';
        });
        // Request to enable location services
        await Geolocator.openLocationSettings();
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
          _location = 'Location permission permanently denied. Please enable in settings.';
        });
        // Open app settings
        await Geolocator.openAppSettings();
        return;
      }

      // Get current position with timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
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
          String address = '';
          if (place.street != null && place.street!.isNotEmpty) {
            address += '${place.street}, ';
          }
          if (place.locality != null && place.locality!.isNotEmpty) {
            address += '${place.locality}, ';
          }
          if (place.subAdministrativeArea != null && place.subAdministrativeArea!.isNotEmpty) {
            address += '${place.subAdministrativeArea}, ';
          }
          if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
            address += place.administrativeArea!;
          }
          
          setState(() {
            _location = address.isNotEmpty ? address : 'Address not found';
          });
        }
      } catch (e) {
        setState(() {
          _location = 'Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}';
        });
        debugPrint('Geocoding error: $e');
      }

      // Move camera to current location
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
      debugPrint('Location error: $e');
      
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location error: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
    if (userId == null) {
      setState(() {
        _isLoadingProfile = false;
      });
      return;
    }

    try {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      setState(() {
        _isLoadingProfile = false;
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
      setState(() {
        _isLoadingProfile = false;
      });
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
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    
    return Scaffold(
      body: Stack(
        children: [
          // Google Map background
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(7.0731, 125.6124), // Default to your location
              zoom: 16,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
            compassEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              debugPrint('Google Map created successfully');
              // Move to current position if available
              if (_currentPosition != null) {
                controller.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      zoom: 16.0,
                    ),
                  ),
                );
              }
              
              // Check if map is loading tiles after a delay
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) {
                  debugPrint('Checking map tile loading status...');
                  // If we reach here and no tiles are visible, likely API key issue
                  debugPrint('Map should have loaded tiles by now. If blank, check API key configuration.');
                }
              });
            },
            onCameraMove: (CameraPosition position) {
              // Optional: Debug camera movements
              debugPrint('Camera moved to: ${position.target}');
            },
            onTap: (LatLng position) {
              debugPrint('Map tapped at: ${position.latitude}, ${position.longitude}');
              // If this prints but no map tiles show, API key is missing
              if (_mapController != null) {
                debugPrint('Map controller is available');
              } else {
                debugPrint('Map controller is null - map not properly initialized');
              }
            },
            // Add this callback to detect when tiles fail to load
            onCameraIdle: () {
              debugPrint('Camera idle - map tiles should be loaded');
              if (_mapController == null) {
                debugPrint('ERROR: Map not fetched - controller is null');
              } else {
                debugPrint('Map controller available - tiles should be visible');
                // Additional check
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    debugPrint('Final check: If you see Google logo but no map tiles, API key is missing or invalid');
                  }
                });
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
                margin: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.02, 
                  vertical: screenHeight * 0.01
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.04, 
                  vertical: screenHeight * 0.015
                ),
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
                  height: screenHeight * 0.06,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Centered logo
                      Align(
                        alignment: Alignment.center,
                        child: SvgPicture.asset(
                          'assets/sositlogo.svg',
                          height: screenHeight * 0.025,
                        ),
                      ),
                      // Settings icon (left)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SettingsPage()),
                            );
                          },
                          child: Container(
                            width: screenWidth * 0.11,
                            height: screenWidth * 0.11,
                            decoration: const BoxDecoration(
                              color: Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.settings, 
                              color: const Color(0xFFF73D5C), 
                              size: screenWidth * 0.09,
                            ),
                          ),
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
                                  radius: screenWidth * 0.055,
                                  backgroundImage: NetworkImage(_profilePhotoUrl),
                                )
                              : Container(
                                  width: screenWidth * 0.11,
                                  height: screenWidth * 0.11,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF73D5C),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.person, 
                                    color: Colors.white, 
                                    size: screenWidth * 0.07,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom Card: Safety Status (Expandable)
          Positioned(
            left: 0,
            right: 0,
            bottom: _isCardExpanded ? 0 : screenHeight * 0.03,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isCardExpanded = !_isCardExpanded;
                });
              },
              onPanUpdate: (details) {
                // Detect upward swipe to expand
                if (details.delta.dy < -5 && !_isCardExpanded) {
                  setState(() {
                    _isCardExpanded = true;
                  });
                }
                // Detect downward swipe to collapse
                else if (details.delta.dy > 5 && _isCardExpanded) {
                  setState(() {
                    _isCardExpanded = false;
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _isCardExpanded ? screenHeight * 0.7 : null,
                constraints: _isCardExpanded 
                    ? null 
                    : BoxConstraints(
                        maxHeight: screenHeight * 0.4,
                        minHeight: screenHeight * 0.2,
                      ),
                margin: EdgeInsets.symmetric(
                  horizontal: _isCardExpanded ? 0 : screenWidth * 0.04
                ),
                padding: EdgeInsets.symmetric(
                  vertical: screenHeight * 0.02, 
                  horizontal: screenWidth * 0.045
                ),
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
                      offset: Offset(0, -4),
                    )
                  ],
                ),
                child: _isCardExpanded 
                    ? Column(
                        children: [
                          // Drag Handle
                          Container(
                            width: screenWidth * 0.12,
                            height: 4,
                            margin: EdgeInsets.only(bottom: screenHeight * 0.015),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade400,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          
                          Text(
                            'Your Safety Status',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: screenWidth * 0.045,
                            ),
                          ),
                          SizedBox(height: screenHeight * 0.015),
                          
                          // Status info in expanded view
                          _buildStatusInfo(),
                          
                          SizedBox(height: screenHeight * 0.025),
                          Row(
                            children: [
                              Text('Emergency Contacts',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    fontSize: screenWidth * 0.04
                                  )),
                              const Spacer(),
                              Icon(
                                Icons.keyboard_arrow_down,
                                color: Colors.grey.shade600,
                                size: screenWidth * 0.05,
                              ),
                            ],
                          ),
                          SizedBox(height: screenHeight * 0.015),
                          
                          // Emergency contacts content
                          Expanded(
                            child: SingleChildScrollView(
                              child: _buildEmergencyContacts(),
                            ),
                          ),
                        ],
                      )
                    : IntrinsicHeight(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Drag Handle
                            Container(
                              width: screenWidth * 0.12,
                              height: 4,
                              margin: EdgeInsets.only(bottom: screenHeight * 0.015),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            
                            Text(
                              'Your Safety Status',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: screenWidth * 0.045,
                              ),
                            ),
                            SizedBox(height: screenHeight * 0.015),
                            
                            // Status info in collapsed view
                            _buildStatusInfo(),
                            
                            SizedBox(height: screenHeight * 0.015),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.keyboard_arrow_up,
                                  color: Colors.grey.shade600,
                                  size: screenWidth * 0.05,
                                ),
                                SizedBox(width: screenWidth * 0.01),
                                Text(
                                  'Swipe up for Emergency Contacts',
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
                      ),
              ),
            ),
          ),
        ],
      ),
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
            Text('Device Status: ', 
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: screenWidth * 0.035
                )),
            Expanded(
              child: Text(_deviceStatus, 
                  style: TextStyle(
                    color: _getDeviceStatusColor(_deviceStatus),
                    fontSize: screenWidth * 0.035
                  )),
            ),
          ],
        ),
        SizedBox(height: screenHeight * 0.005),
        Row(
          children: [
            Text('GPS Signal: ', 
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: screenWidth * 0.035
                )),
            Text(_gpsSignal, 
                style: TextStyle(
                  color: _getGpsColor(_gpsSignal),
                  fontSize: screenWidth * 0.035
                )),
          ],
        ),
        SizedBox(height: screenHeight * 0.005),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Location: ', 
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: screenWidth * 0.035
                )),
            Expanded(
              child: Text(_location.isNotEmpty ? _location : 'Getting location...', 
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: screenWidth * 0.035
                  ),
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
    
    return Column(
      children: [
        // Loading state for contacts
        if (_isLoadingProfile) ...[
          Container(
            padding: EdgeInsets.all(screenHeight * 0.025),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: screenWidth * 0.05,
                  height: screenWidth * 0.05,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF73D5C)),
                  ),
                ),
                SizedBox(width: screenWidth * 0.03),
                Text(
                  'Loading contacts...',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: screenWidth * 0.035,
                  ),
                ),
              ],
            ),
          ),
        ]
        // Show contacts when loaded
        else ...[
          // First Emergency Contact
          if (_emergencyName.isNotEmpty || _emergencyPhone.isNotEmpty) ...[
            Container(
              padding: EdgeInsets.all(screenWidth * 0.03),
              margin: EdgeInsets.only(bottom: screenHeight * 0.01),
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
                      Icon(Icons.person, 
                          size: screenWidth * 0.04, 
                          color: Colors.grey),
                      SizedBox(width: screenWidth * 0.02),
                      Text(_emergencyName.isNotEmpty ? _emergencyName : 'No name provided',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: screenWidth * 0.035
                          )),
                    ],
                  ),
                  if (_relationship.isNotEmpty) ...[
                    SizedBox(height: screenHeight * 0.005),
                    Row(
                      children: [
                        Icon(Icons.family_restroom, 
                            size: screenWidth * 0.04, 
                            color: Colors.grey),
                        SizedBox(width: screenWidth * 0.02),
                        Text(_relationship, 
                            style: TextStyle(
                              color: Colors.grey.shade600, 
                              fontSize: screenWidth * 0.03
                            )),
                      ],
                    ),
                  ],
                  if (_emergencyPhone.isNotEmpty) ...[
                    SizedBox(height: screenHeight * 0.005),
                    Row(
                      children: [
                        Icon(Icons.phone, 
                            size: screenWidth * 0.04, 
                            color: Colors.grey),
                        SizedBox(width: screenWidth * 0.02),
                        Text(_emergencyPhone, 
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: screenWidth * 0.035
                            )),
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
              padding: EdgeInsets.all(screenWidth * 0.03),
              margin: EdgeInsets.only(bottom: screenHeight * 0.01),
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
                      Icon(Icons.person, 
                          size: screenWidth * 0.04, 
                          color: Colors.grey),
                      SizedBox(width: screenWidth * 0.02),
                      Text(_emergencyName2.isNotEmpty ? _emergencyName2 : 'No name provided',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: screenWidth * 0.035
                          )),
                    ],
                  ),
                  if (_relationship2.isNotEmpty) ...[
                    SizedBox(height: screenHeight * 0.005),
                    Row(
                      children: [
                        Icon(Icons.family_restroom, 
                            size: screenWidth * 0.04, 
                            color: Colors.grey),
                        SizedBox(width: screenWidth * 0.02),
                        Text(_relationship2, 
                            style: TextStyle(
                              color: Colors.grey.shade600, 
                              fontSize: screenWidth * 0.03
                            )),
                      ],
                    ),
                  ],
                  if (_emergencyPhone2.isNotEmpty) ...[
                    SizedBox(height: screenHeight * 0.005),
                    Row(
                      children: [
                        Icon(Icons.phone, 
                            size: screenWidth * 0.04, 
                            color: Colors.grey),
                        SizedBox(width: screenWidth * 0.02),
                        Text(_emergencyPhone2, 
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: screenWidth * 0.035
                            )),
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
              padding: EdgeInsets.all(screenWidth * 0.03),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, 
                      color: Colors.orange.shade600, 
                      size: screenWidth * 0.04),
                  SizedBox(width: screenWidth * 0.02),
                  Expanded(
                    child: Text('No emergency contacts added yet',
                        style: TextStyle(fontSize: screenWidth * 0.03)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
