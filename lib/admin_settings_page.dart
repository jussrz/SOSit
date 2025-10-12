import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final supabase = Supabase.instance.client;
  bool _isLoading = false;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _adminData;
  bool _isFirstAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        // Load admin-specific data first
        final adminData = await supabase
            .from('admin')
            .select()
            .eq('id', userId)
            .maybeSingle();

        // Try to load user data, but use admin email if user data doesn't exist
        Map<String, dynamic>? userData;
        try {
          userData = await supabase
              .from('user')
              .select()
              .eq('id', userId)
              .single();
        } catch (e) {
          // If no user record exists, create userData with admin email
          userData = {
            'email': supabase.auth.currentUser?.email ?? adminData?['admin_email'],
            'role': 'admin',
          };
        }

        // Check if this is the first admin based on your database structure
        // You can adjust this logic based on how you identify the primary admin
        final isFirst = adminData?['is_primary'] == true || 
                       adminData?['admin_firstname']?.toLowerCase() == 'admin' ||
                       adminData?['admin_email']?.toLowerCase().contains('admin') ||
                       adminData?['admin_email'] == 'admin@sosit.com'; // Add your admin email here

        debugPrint('Admin data: $adminData');
        debugPrint('Is first admin: $isFirst');
        debugPrint('Admin firstname: ${adminData?['admin_firstname']}');
        debugPrint('Admin email: ${adminData?['admin_email']}');
        debugPrint('Is primary field: ${adminData?['is_primary']}');

        setState(() {
          _userData = userData;
          _adminData = adminData;
          _isFirstAdmin = isFirst;
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Sign Out',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade600,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF73D5C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              elevation: 0,
            ),
            child: const Text(
              'Sign Out',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF73D5C)))
          : Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: screenHeight * 0.02),

                    // Profile Section
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(screenWidth * 0.06),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          // Profile Icon
                          Container(
                            width: screenWidth * 0.25,
                            height: screenWidth * 0.25,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF73D5C).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.admin_panel_settings,
                              size: screenWidth * 0.12,
                              color: const Color(0xFFF73D5C),
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.025),

                          // Name
                          Text(
                            '${_adminData?['admin_firstname'] ?? ''} ${_adminData?['admin_lastname'] ?? ''}'.trim().isEmpty 
                                ? 'Administrator' 
                                : '${_adminData?['admin_firstname'] ?? ''} ${_adminData?['admin_lastname'] ?? ''}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: screenWidth * 0.055,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.01),

                          // Badge/Role
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.04,
                              vertical: screenHeight * 0.008,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF73D5C),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _isFirstAdmin ? 'PRIMARY ADMINISTRATOR' : 'ADMINISTRATOR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: screenWidth * 0.035,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.04),

                    // Account Information Section
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.all(screenWidth * 0.04),
                            child: Text(
                              'Account Information',
                              style: TextStyle(
                                fontSize: screenWidth * 0.045,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          _buildInfoTile(
                            Icons.email,
                            'Email',
                            _userData?['email'] ?? 
                            _adminData?['admin_email'] ?? 
                            supabase.auth.currentUser?.email ?? 
                            'Not set',
                            screenWidth,
                          ),
                          if (_userData?['phone'] != null) ...[
                            _buildDivider(),
                            _buildInfoTile(
                              Icons.phone,
                              'Phone',
                              _userData!['phone'],
                              screenWidth,
                            ),
                          ],
                        ],
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.03),

                    // Admin Information Section
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.all(screenWidth * 0.04),
                            child: Text(
                              'Administrative Information',
                              style: TextStyle(
                                fontSize: screenWidth * 0.045,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          _buildInfoTile(
                            Icons.verified_user,
                            'Access Level',
                            _isFirstAdmin ? 'PRIMARY ADMIN' : 'ADMIN',
                            screenWidth,
                            valueColor: _isFirstAdmin ? Colors.red : const Color(0xFFF73D5C),
                          ),
                          if (_adminData?['created_at'] != null) ...[
                            _buildDivider(),
                            _buildInfoTile(
                              Icons.schedule,
                              'Account Created',
                              _adminData!['created_at'].toString().substring(0, 10),
                              screenWidth,
                            ),
                          ],
                        ],
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.04),

                    // Sign Out Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF73D5C),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _showSignOutDialog,
                        child: Text(
                          'Sign Out',
                          style: TextStyle(
                            fontSize: screenWidth * 0.045,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.04),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoTile(
    IconData icon,
    String title,
    String value,
    double screenWidth, {
    Color? valueColor,
  }) {
    return Padding(
      padding: EdgeInsets.all(screenWidth * 0.04),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(screenWidth * 0.025),
            decoration: BoxDecoration(
              color: const Color(0xFFF73D5C).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFF73D5C),
              size: screenWidth * 0.05,
            ),
          ),
          SizedBox(width: screenWidth * 0.04),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: screenWidth * 0.035,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: screenWidth * 0.04,
                    color: valueColor ?? Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        color: Colors.grey.shade200,
        height: 1,
      ),
    );
  }
}