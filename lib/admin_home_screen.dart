import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'settings_page.dart' hide MaterialPageRoute;
import 'login_page.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  
  List<Map<String, dynamic>> pendingTanods = [];
  List<Map<String, dynamic>> pendingPolice = [];
  bool _isLoading = true;
  String _adminName = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAdminData();
    _loadPendingAccounts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminData() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final adminData = await supabase
            .from('admin')
            .select('admin_firstname, admin_lastname')
            .eq('id', userId)
            .single();
        
        setState(() {
          _adminName = '${adminData['admin_firstname']} ${adminData['admin_lastname']}';
        });
      }
    } catch (e) {
      debugPrint('Error loading admin data: $e');
    }
  }

  Future<void> _loadPendingAccounts() async {
    setState(() => _isLoading = true);
    
    try {
      // Load pending tanod accounts from pending_tanod table
      final tanodData = await supabase
          .from('pending_tanod')
          .select('*')
          .order('created_at', ascending: false);

      // Load pending police accounts from pending_police table
      final policeData = await supabase
          .from('pending_police')
          .select('*')
          .order('created_at', ascending: false);

      setState(() {
        pendingTanods = List<Map<String, dynamic>>.from(tanodData);
        pendingPolice = List<Map<String, dynamic>>.from(policeData);
        _isLoading = false;
      });

      debugPrint('Loaded ${pendingTanods.length} pending tanod accounts');
      debugPrint('Loaded ${pendingPolice.length} pending police accounts');
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading pending accounts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading pending accounts: $e')),
        );
      }
    }
  }

  Future<void> _approveAccount(String table, String userId, String userEmail) async {
    try {
      if (table == 'tanod') {
        // Move from pending_tanod to tanod table
        final pendingData = await supabase
            .from('pending_tanod')
            .select('*')
            .eq('user_id', userId)
            .single();

        // Insert into tanod table with approved status
        await supabase.from('tanod').insert({
          'user_id': pendingData['user_id'],
          'id_number': pendingData['id_number'],
          'credentials_url': pendingData['credentials_url'],
          'status': 'approved',
        });

        // Update user role
        await supabase.from('user').update({
          'role': 'tanod'
        }).eq('id', userId);

        // Delete from pending table
        await supabase
            .from('pending_tanod')
            .delete()
            .eq('user_id', userId);

      } else if (table == 'police') {
        // Move from pending_police to police table
        final pendingData = await supabase
            .from('pending_police')
            .select('*')
            .eq('user_id', userId)
            .single();

        // Insert into police table with approved status
        await supabase.from('police').insert({
          'user_id': pendingData['user_id'],
          'station_name': pendingData['station_name'],
          'credentials_url': pendingData['credentials_url'],
          'status': 'approved',
        });

        // Update user role
        await supabase.from('user').update({
          'role': 'police'
        }).eq('id', userId);

        // Delete from pending table
        await supabase
            .from('pending_police')
            .delete()
            .eq('user_id', userId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account for $userEmail approved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      _loadPendingAccounts(); // Refresh the lists
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectAccount(String table, String userId, String userEmail) async {
    try {
      // Simply delete from pending table (rejection)
      if (table == 'tanod') {
        await supabase
            .from('pending_tanod')
            .delete()
            .eq('user_id', userId);
      } else if (table == 'police') {
        await supabase
            .from('pending_police')
            .delete()
            .eq('user_id', userId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account for $userEmail rejected and removed'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      _loadPendingAccounts(); // Refresh the lists
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Icon(Icons.admin_panel_settings, color: const Color(0xFFF73D5C), size: screenWidth * 0.07),
            SizedBox(width: screenWidth * 0.03),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin Dashboard',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: screenWidth * 0.045,
                    ),
                  ),
                  if (_adminName.isNotEmpty)
                    Text(
                      'Welcome, $_adminName',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: screenWidth * 0.035,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.settings, color: const Color(0xFFF73D5C), size: screenWidth * 0.06),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFF73D5C),
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: const Color(0xFFF73D5C),
          tabs: [
            Tab(
              icon: Icon(Icons.security),
              text: 'Tanod (${pendingTanods.length})',
            ),
            Tab(
              icon: Icon(Icons.local_police),
              text: 'Police (${pendingPolice.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPendingList('tanod', pendingTanods),
                _buildPendingList('police', pendingPolice),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFF73D5C),
        onPressed: _loadPendingAccounts,
        child: Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }

  Widget _buildPendingList(String type, List<Map<String, dynamic>> accounts) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    if (accounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == 'tanod' ? Icons.security : Icons.local_police,
              size: screenWidth * 0.2,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: screenHeight * 0.02),
            Text(
              'No pending ${type} accounts',
              style: TextStyle(
                fontSize: screenWidth * 0.045,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: screenHeight * 0.01),
            Text(
              'All ${type} applications have been processed',
              style: TextStyle(
                fontSize: screenWidth * 0.035,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPendingAccounts,
      child: ListView.builder(
        padding: EdgeInsets.all(screenWidth * 0.04),
        itemCount: accounts.length,
        itemBuilder: (context, index) {
          final account = accounts[index];
          
          return Container(
            margin: EdgeInsets.only(bottom: screenHeight * 0.015),
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
            child: Padding(
              padding: EdgeInsets.all(screenWidth * 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with icon and type
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFF73D5C).withOpacity(0.1),
                        child: Icon(
                          type == 'tanod' ? Icons.security : Icons.local_police,
                          color: const Color(0xFFF73D5C),
                        ),
                      ),
                      SizedBox(width: screenWidth * 0.03),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${type.toUpperCase()} Application',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: screenWidth * 0.04,
                              ),
                            ),
                            Text(
                              account['email'] ?? 'No email',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: screenWidth * 0.035,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.025,
                          vertical: screenHeight * 0.005,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'PENDING',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: screenWidth * 0.03,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: screenHeight * 0.015),
                  
                  // Account details
                  _buildDetailRow('Email', account['email'] ?? 'N/A'),
                  _buildDetailRow('Phone', account['phone'] ?? 'N/A'),
                  
                  if (type == 'tanod') ...[
                    _buildDetailRow('ID Number', account['id_number'] ?? 'N/A'),
                  ] else ...[
                    _buildDetailRow('Station Name', account['station_name'] ?? 'N/A'),
                  ],
                  
                  if (account['credentials_url'] != null) ...[
                    SizedBox(height: screenHeight * 0.01),
                    GestureDetector(
                      onTap: () {
                        // TODO: Open credentials image/document
                      },
                      child: Container(
                        padding: EdgeInsets.all(screenWidth * 0.03),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.file_present, color: Colors.blue.shade700, size: screenWidth * 0.04),
                            SizedBox(width: screenWidth * 0.02),
                            Text(
                              'View Credentials',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: screenWidth * 0.035,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  
                  SizedBox(height: screenHeight * 0.02),
                  
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade500,
                            padding: EdgeInsets.symmetric(vertical: screenHeight * 0.012),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _rejectAccount(
                            type,
                            account['user_id'],
                            account['email'] ?? 'Unknown',
                          ),
                          child: Text(
                            'Reject',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: screenWidth * 0.035,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: screenWidth * 0.03),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade500,
                            padding: EdgeInsets.symmetric(vertical: screenHeight * 0.012),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _approveAccount(
                            type,
                            account['user_id'],
                            account['email'] ?? 'Unknown',
                          ),
                          child: Text(
                            'Approve',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: screenWidth * 0.035,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.005),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: screenWidth * 0.25,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: screenWidth * 0.035,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: screenWidth * 0.035,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
    