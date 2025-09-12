import 'package:flutter/material.dart';
import 'home_screen.dart';

class EmergencyContactDashboard extends StatefulWidget {
  const EmergencyContactDashboard({super.key});

  @override
  State<EmergencyContactDashboard> createState() => _EmergencyContactDashboardState();
}

class _EmergencyContactDashboardState extends State<EmergencyContactDashboard> {
  int _selectedIndex = 0;

  final List<Map<String, dynamic>> _sosAlerts = [
    {
      'name': 'Juan Dela Cruz',
      'time': DateTime.now().subtract(const Duration(minutes: 5)),
      'location': 'Ateneo de Davao University',
      'status': 'active',
      'userId': 'user1',
    },
    {
      'name': 'Maria Santos',
      'time': DateTime.now().subtract(const Duration(days: 1)),
      'location': 'Roxas Avenue',
      'status': 'resolved',
      'userId': 'user2',
    },
  ];

  final Map<String, dynamic> _profile = {
    'name': 'Parent/Guardian',
    'relationship': 'Parent',
    'phone': '+63 912 345 6789',
    'email': 'parent@email.com',
    'notifPref': 'Push + SMS',
  };

  void _onTabTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (route) => false,
            );
          },
        ),
        title: const Text('Emergency Contact', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboard(screenWidth, screenHeight),
          _buildHistory(screenWidth, screenHeight),
          _buildProfileSettings(screenWidth, screenHeight),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFF73D5C),
        unselectedItemColor: Colors.grey.shade600,
        backgroundColor: Colors.white,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(double screenWidth, double screenHeight) {
    return ListView(
      padding: EdgeInsets.all(screenWidth * 0.05),
      children: [
        const Text('Latest SOS Alerts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
        SizedBox(height: screenHeight * 0.015),
        ..._sosAlerts.map((alert) => Container(
          margin: EdgeInsets.only(bottom: screenHeight * 0.015),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: alert['status'] == 'active' ? const Color(0xFFF73D5C).withOpacity(0.15) : Colors.green.withOpacity(0.15),
              child: Icon(alert['status'] == 'active' ? Icons.warning : Icons.check_circle, color: alert['status'] == 'active' ? const Color(0xFFF73D5C) : Colors.green),
            ),
            title: Text(alert['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 2),
                Text(alert['location'], style: TextStyle(fontSize: screenWidth * 0.035, color: Colors.grey.shade700)),
                Text(_formatDate(alert['time']), style: TextStyle(fontSize: screenWidth * 0.032, color: Colors.grey.shade500)),
              ],
            ),
            trailing: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: alert['status'] == 'active' ? const Color(0xFFF73D5C).withOpacity(0.1) : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(alert['status'].toUpperCase(), style: TextStyle(color: alert['status'] == 'active' ? const Color(0xFFF73D5C) : Colors.green, fontWeight: FontWeight.w600, fontSize: screenWidth * 0.032)),
            ),
            onTap: () => _showAlertDetails(alert, screenWidth, screenHeight),
          ),
        )),
      ],
    );
  }

  Widget _buildHistory(double screenWidth, double screenHeight) {
    return ListView(
      padding: EdgeInsets.all(screenWidth * 0.05),
      children: [
        const Text('SOS History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
        SizedBox(height: screenHeight * 0.015),
        ..._sosAlerts.map((alert) => Container(
          margin: EdgeInsets.only(bottom: screenHeight * 0.015),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.grey.withOpacity(0.13),
              child: Icon(Icons.history, color: Colors.grey.shade700),
            ),
            title: Text(alert['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 2),
                Text(alert['location'], style: TextStyle(fontSize: screenWidth * 0.035, color: Colors.grey.shade700)),
                Text(_formatDate(alert['time']), style: TextStyle(fontSize: screenWidth * 0.032, color: Colors.grey.shade500)),
              ],
            ),
            trailing: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: alert['status'] == 'active' ? const Color(0xFFF73D5C).withOpacity(0.1) : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(alert['status'].toUpperCase(), style: TextStyle(color: alert['status'] == 'active' ? const Color(0xFFF73D5C) : Colors.green, fontWeight: FontWeight.w600, fontSize: screenWidth * 0.032)),
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildProfileSettings(double screenWidth, double screenHeight) {
    return ListView(
      padding: EdgeInsets.all(screenWidth * 0.05),
      children: [
        const Text('Profile Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
        SizedBox(height: screenHeight * 0.02),
        Container(
          padding: EdgeInsets.all(screenWidth * 0.04),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFF73D5C).withOpacity(0.13),
                    child: const Icon(Icons.person, color: Color(0xFFF73D5C)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_profile['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Relationship: ${_profile['relationship']}', style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.phone, color: Colors.grey, size: 20),
                  const SizedBox(width: 8),
                  Text(_profile['phone'], style: const TextStyle(fontSize: 15)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.email, color: Colors.grey, size: 20),
                  const SizedBox(width: 8),
                  Text(_profile['email'], style: const TextStyle(fontSize: 15)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.notifications, color: Colors.grey, size: 20),
                  const SizedBox(width: 8),
                  Text('Notification Preferences:', style: TextStyle(fontSize: 15, color: Colors.black)),
                  const SizedBox(width: 6),
                  Text(_profile['notifPref'], style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAlertDetails(Map<String, dynamic> alert, double screenWidth, double screenHeight) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: EdgeInsets.all(screenWidth * 0.06),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFF73D5C),
                      radius: screenWidth * 0.07,
                      child: const Icon(Icons.person, color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(alert['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: screenWidth * 0.05)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.access_time, color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Text(_formatDate(alert['time']), style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(alert['location'], style: const TextStyle(fontSize: 15))),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Text('Status: ', style: TextStyle(fontSize: 15, color: Colors.black)),
                    Text(alert['status'], style: TextStyle(fontSize: 15, color: alert['status'] == 'active' ? const Color(0xFFF73D5C) : Colors.green)),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF73D5C),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Mark as Acknowledged', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
