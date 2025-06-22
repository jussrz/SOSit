import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_page.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _emergencyName = '';
  String _emergencyPhone = '';
  String _relationship = '';

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
        _emergencyName = data['emergency_contact_name'] ?? '';
        _emergencyPhone = data['emergency_phone'] ?? '';
        _relationship = data['relationship'] ?? '';
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
          // Google Map
          const GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(7.0731, 125.6124),
              zoom: 16,
            ),
            myLocationEnabled: true,
            mapType: MapType.normal,
          ),

          // Top Safe-area Card with Logo/Profile
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    )
                  ],
                ),
                child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.settings, color: Colors.black),
                    const Text(
                      'SoSit!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
GestureDetector(
  onTap: () {
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const ProfilePage()),
).then((_) => _loadUserProfile());

  },
  child: const CircleAvatar(
    radius: 18,
    backgroundImage: AssetImage('assets/11ce59cd-c4a8-4287-91a8-79e33605870c.jfif'),
  ),
),

                  ],
                ),
              ),
            ),
          ),

          // Bottom Draggable Safety Status
          DraggableScrollableSheet(
            initialChildSize: 0.25,
            minChildSize: 0.1,
            maxChildSize: 0.5,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    )
                  ],
                ),
child: ListView(
  controller: scrollController,
  padding: EdgeInsets.zero, // Remove default ListView padding
  children: [
    const SizedBox(height: 4),
    const Center(
      child: Icon(Icons.drag_handle, size: 24, color: Colors.grey),
    ),
    const SizedBox(height: 4),
    const Text('Device Status: ', style: TextStyle(fontSize: 14)),
    const Text('GPS Signal: ', style: TextStyle(fontSize: 14)),
    const Text('Location: ', style: TextStyle(fontSize: 14)),
    const SizedBox(height: 16),
    const Text('Emergency Contact Details',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    const SizedBox(height: 8),
    Text('Name: $_emergencyName', 
        style: const TextStyle(fontSize: 14)),
    Text('Phone: $_emergencyPhone', 
        style: const TextStyle(fontSize: 14)),
    Text('Relationship: $_relationship', 
        style: const TextStyle(fontSize: 14)),
  ],
),
              );
            },
          ),
        ],
      ),
    );
  }
}
