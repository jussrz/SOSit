import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_page.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _deviceStatus = '';
  String _gpsSignal = '';
  String _location = '';
  String _emergencyName = '';
  String _emergencyPhone = '';
  String _relationship = '';
  String _emergencyName2 = '';
  String _emergencyPhone2 = '';
  String _relationship2 = '';
  String _profilePhotoUrl = '';

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
        _deviceStatus = data['device_status'] ?? 'Unknown';
        _gpsSignal = data['gps_signal'] ?? 'Unknown';
        _location = data['location'] ?? 'Unknown';
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

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map background
          const GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(7.0731, 125.6124),
              zoom: 16,
            ),
            myLocationEnabled: true,
            mapType: MapType.normal,
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
                  boxShadow: [
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
                  boxShadow: [
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
                        Text(_deviceStatus, style: TextStyle(color: _deviceStatus.toLowerCase().contains('connected') ? Colors.green : Colors.red)),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('GPS Signal: ', style: TextStyle(fontWeight: FontWeight.w500)),
                        Text(_gpsSignal, style: TextStyle(color: _gpsSignal.toLowerCase() == 'strong' ? Colors.green : Colors.red)),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Location: ', style: TextStyle(fontWeight: FontWeight.w500)),
                        Expanded(
                          child: Text(_location, style: const TextStyle(color: Colors.black87)),
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
