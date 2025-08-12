import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_details_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black, size: screenWidth * 0.06),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text('Settings', style: TextStyle(
          color: Colors.black, 
          fontWeight: FontWeight.w500, 
          fontSize: screenWidth * 0.045
        )),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(screenWidth * 0.04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Account Section
            Text('Account', style: TextStyle(
              fontWeight: FontWeight.w600, 
              fontSize: screenWidth * 0.04, 
              color: Colors.black
            )),
            SizedBox(height: screenHeight * 0.015),
            
            _buildSettingsItem(
              icon: Icons.person_outline,
              title: 'Login Details',
              subtitle: 'Update your email and password',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginDetailsPage()),
                );
              },
            ),
            
            _buildSettingsItem(
              icon: Icons.security,
              title: 'Privacy & Security',
              subtitle: 'Manage your privacy settings',
              onTap: () {
                // Navigate to privacy settings
              },
            ),
            
            SizedBox(height: screenHeight * 0.025),
            
            // Emergency Section
            Text('Emergency', style: TextStyle(
              fontWeight: FontWeight.w600, 
              fontSize: screenWidth * 0.04, 
              color: Colors.black
            )),
            SizedBox(height: screenHeight * 0.015),
            
            _buildSettingsItem(
              icon: Icons.contacts,
              title: 'Emergency Contacts',
              subtitle: 'Manage your emergency contacts',
              onTap: () {
                // Navigate to emergency contacts
              },
            ),
            
            _buildSettingsItem(
              icon: Icons.bluetooth,
              title: 'Panic Button',
              subtitle: 'Manage panic button connection',
              onTap: () {
                // Navigate to panic button settings
              },
            ),
            
            SizedBox(height: screenHeight * 0.025),
            
            // App Section
            Text('App', style: TextStyle(
              fontWeight: FontWeight.w600, 
              fontSize: screenWidth * 0.04, 
              color: Colors.black
            )),
            SizedBox(height: screenHeight * 0.015),
            
            _buildSettingsItem(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Manage notification preferences',
              onTap: () {
                // Navigate to notification settings
              },
            ),
            
            _buildSettingsItem(
              icon: Icons.help_outline,
              title: 'Help & Support',
              subtitle: 'Get help and contact support',
              onTap: () {
                // Navigate to help page
              },
            ),
            
            _buildSettingsItem(
              icon: Icons.info_outline,
              title: 'About',
              subtitle: 'App version and information',
              onTap: () {
                // Show about dialog
              },
            ),
            
            SizedBox(height: screenHeight * 0.025),
            
            // Logout Button
            Container(
              width: double.infinity,
              height: screenHeight * 0.05,
              margin: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF73D5C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                onPressed: () async {
                  final confirmed = await _showLogoutConfirmationDialog();
                  if (confirmed) {
                    await _logout();
                  }
                },
                child: Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: screenWidth * 0.04,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.01),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFF73D5C), size: screenWidth * 0.055),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: screenWidth * 0.038,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: screenWidth * 0.03,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios, color: Colors.grey, size: screenWidth * 0.035),
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.035, 
          vertical: MediaQuery.of(context).size.height * 0.008
        ),
      ),
    );
  }

  Future<bool> _showLogoutConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  Future<void> _logout() async {
    try {
      await supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: $e')),
        );
      }
    }
  }
}
