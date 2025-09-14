import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';

class EmergencyContactDashboard extends StatefulWidget {
  const EmergencyContactDashboard({super.key});

  @override
  State<EmergencyContactDashboard> createState() =>
      _EmergencyContactDashboardState();
}

class _EmergencyContactDashboardState extends State<EmergencyContactDashboard> {
  final supabase = Supabase.instance.client;
  int _selectedIndex = 0;
  bool _isLoading = true;

  List<Map<String, dynamic>> _sosAlerts = [];
  Map<String, dynamic> _emergencyContactData = {};
  Map<String, dynamic> _profile = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load emergency contact data directly
      _emergencyContactData = await _getEmergencyContactData();

      // Load user profile
      await _loadUserProfile();

      // Load SOS alerts (emergency logs where this user is the emergency contact)
      await _loadSosAlerts();
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _getEmergencyContactData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return {
        'emergency_contacts': [],
        'group_memberships': [],
      };
    }

    try {
      // Get emergency contacts where this user is the emergency contact
      // Check if emergency_contact_user_id column exists, otherwise use a different approach
      List<dynamic> emergencyContacts = [];

      try {
        // Try the original approach first
        emergencyContacts = await supabase.from('emergency_contacts').select('''
              id,
              user_id,
              emergency_contact_name,
              emergency_contact_phone,
              emergency_contact_relationship
            ''').eq('emergency_contact_user_id', userId);
      } catch (e) {
        // If emergency_contact_user_id doesn't exist, try alternative approach
        debugPrint('emergency_contact_user_id column might not exist: $e');

        // Alternative: Check if this user's phone/email matches emergency contact info
        final currentUser = await supabase
            .from('user')
            .select('phone, email')
            .eq('id', userId)
            .single();

        if (currentUser['phone'] != null) {
          emergencyContacts =
              await supabase.from('emergency_contacts').select('''
                id,
                user_id,
                emergency_contact_name,
                emergency_contact_phone,
                emergency_contact_relationship
              ''').eq('emergency_contact_phone', currentUser['phone']);
        }
      }

      // Get group memberships where this user is a member
      List<dynamic> groupMemberships = [];
      try {
        groupMemberships = await supabase.from('group_memberships').select('''
              id,
              user_id,
              relationship
            ''').eq('user_id', userId);

        // Get group details separately to avoid complex joins
        for (var i = 0; i < groupMemberships.length; i++) {
          if (groupMemberships[i]['group_id'] != null) {
            try {
              final groupData = await supabase
                  .from('groups')
                  .select('id, name, created_by')
                  .eq('id', groupMemberships[i]['group_id'])
                  .single();

              groupMemberships[i]['group'] = groupData;

              // Get creator info
              if (groupData['created_by'] != null) {
                final creatorData = await supabase
                    .from('user')
                    .select('id, first_name, last_name')
                    .eq('id', groupData['created_by'])
                    .single();

                groupMemberships[i]['group']['creator'] = creatorData;
              }
            } catch (e) {
              debugPrint('Error loading group details: $e');
              groupMemberships[i]['group'] = null;
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading group memberships: $e');
      }

      return {
        'emergency_contacts': emergencyContacts,
        'group_memberships': groupMemberships,
      };
    } catch (e) {
      debugPrint('Error getting emergency contact data: $e');
      return {
        'emergency_contacts': [],
        'group_memberships': [],
      };
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final userData = await supabase
          .from('user')
          .select('first_name, last_name, email, phone')
          .eq('id', userId)
          .single();

      setState(() {
        _profile = {
          'name':
              '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}',
          'role': 'Emergency Contact',
          'phone': userData['phone'] ?? '',
          'email': userData['email'] ?? '',
          'notifPref': 'Push + SMS', // Default notification preference
        };
      });
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  Future<void> _loadSosAlerts() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final relatedUserIds = _getRelatedUserIds();
      if (relatedUserIds.isEmpty) {
        setState(() {
          _sosAlerts = [];
        });
        return;
      }

      // Get emergency logs where this user might be involved as an emergency contact
      // Simplify the query to avoid complex joins that might fail
      final alerts = await supabase
          .from('logs')
          .select('''
            id,
            user_id,
            created_at,
            description,
            emergency_level,
            location,
            responded_at
          ''')
          .inFilter('user_id', relatedUserIds)
          .order('created_at', ascending: false)
          .limit(10);

      // Get user details separately for each alert
      List<Map<String, dynamic>> processedAlerts = [];
      for (var alert in alerts) {
        try {
          // Get user info for this alert
          String userName = 'Unknown User';
          if (alert['user_id'] != null) {
            final userInfo = await supabase
                .from('user')
                .select('first_name, last_name')
                .eq('id', alert['user_id'])
                .single();

            userName =
                '${userInfo['first_name'] ?? ''} ${userInfo['last_name'] ?? ''}'
                    .trim();
            if (userName.isEmpty) userName = 'Unknown User';
          }

          processedAlerts.add({
            'id': alert['id'],
            'name': userName,
            'time': DateTime.parse(alert['created_at']),
            'location': alert['location'] ?? 'Location not available',
            'status': alert['responded_at'] != null ? 'resolved' : 'active',
            'emergency_level': alert['emergency_level'] ?? 'regular',
            'description': alert['description'] ?? '',
            'userId': alert['user_id'],
          });
        } catch (e) {
          debugPrint('Error processing alert ${alert['id']}: $e');
          // Still add the alert with basic info
          processedAlerts.add({
            'id': alert['id'],
            'name': 'Unknown User',
            'time': DateTime.parse(alert['created_at']),
            'location': alert['location'] ?? 'Location not available',
            'status': alert['responded_at'] != null ? 'resolved' : 'active',
            'emergency_level': alert['emergency_level'] ?? 'regular',
            'description': alert['description'] ?? '',
            'userId': alert['user_id'],
          });
        }
      }

      setState(() {
        _sosAlerts = processedAlerts;
      });
    } catch (e) {
      debugPrint('Error loading SOS alerts: $e');
      setState(() {
        _sosAlerts = [];
      });
    }
  }

  List<String> _getRelatedUserIds() {
    List<String> userIds = [];

    // Get user IDs from groups where this user is a member
    final groupMemberships =
        _emergencyContactData['group_memberships'] as List? ?? [];
    for (var membership in groupMemberships) {
      if (membership['group'] != null &&
          membership['group']['created_by'] != null) {
        userIds.add(membership['group']['created_by']);
      }
    }

    // Get user IDs from emergency contacts
    final emergencyContacts =
        _emergencyContactData['emergency_contacts'] as List? ?? [];
    for (var contact in emergencyContacts) {
      if (contact['user_id'] != null) {
        userIds.add(contact['user_id']);
      }
    }

    return userIds.toSet().toList(); // Remove duplicates
  }

  void _onTabTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFF73D5C),
          ),
        ),
      );
    }

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
        title: const Text('Emergency Contact Dashboard',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
        actions: [
          // Switch to regular user view if applicable
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.black),
            onPressed: () => _showRoleSwitchDialog(),
            tooltip: 'Switch View',
          ),
        ],
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
            label: 'Dashboard',
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

  void _showRoleSwitchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch View'),
        content:
            const Text('Do you want to switch to the regular user dashboard?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
            child: const Text('Switch to User View'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF73D5C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(double screenWidth, double screenHeight) {
    return RefreshIndicator(
      color: const Color(0xFFF73D5C),
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.all(screenWidth * 0.05),
        children: [
          // Role indicator
          Container(
            padding: EdgeInsets.all(screenWidth * 0.04),
            margin: EdgeInsets.only(bottom: screenHeight * 0.02),
            decoration: BoxDecoration(
              color: const Color(0xFFF73D5C).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: const Color(0xFFF73D5C).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.contact_emergency,
                  color: const Color(0xFFF73D5C),
                  size: screenWidth * 0.06,
                ),
                SizedBox(width: screenWidth * 0.03),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Emergency Contact',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'You are listed as an emergency contact for ${_getContactCount()} person(s)',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Text('Recent Emergency Alerts',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black)),
          SizedBox(height: screenHeight * 0.015),

          if (_sosAlerts.isEmpty)
            Container(
              padding: EdgeInsets.all(screenWidth * 0.05),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No emergency alerts yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You\'ll be notified here when someone you\'re listed as an emergency contact for sends an alert.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ..._sosAlerts.map(
                (alert) => _buildAlertCard(alert, screenWidth, screenHeight)),
        ],
      ),
    );
  }

  Widget _buildAlertCard(
      Map<String, dynamic> alert, double screenWidth, double screenHeight) {
    return Container(
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
          backgroundColor: alert['status'] == 'active'
              ? const Color(0xFFF73D5C).withOpacity(0.15)
              : Colors.green.withOpacity(0.15),
          child: Icon(
            alert['status'] == 'active' ? Icons.warning : Icons.check_circle,
            color: alert['status'] == 'active'
                ? const Color(0xFFF73D5C)
                : Colors.green,
          ),
        ),
        title: Text(alert['name'],
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(alert['location'],
                style: TextStyle(
                    fontSize: screenWidth * 0.035,
                    color: Colors.grey.shade700)),
            Text(_formatDate(alert['time']),
                style: TextStyle(
                    fontSize: screenWidth * 0.032,
                    color: Colors.grey.shade500)),
            if (alert['emergency_level'] != 'regular')
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: alert['emergency_level'] == 'critical'
                      ? Colors.red.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  alert['emergency_level'].toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: alert['emergency_level'] == 'critical'
                        ? Colors.red
                        : Colors.orange,
                  ),
                ),
              ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: alert['status'] == 'active'
                ? const Color(0xFFF73D5C).withOpacity(0.1)
                : Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            alert['status'].toUpperCase(),
            style: TextStyle(
              color: alert['status'] == 'active'
                  ? const Color(0xFFF73D5C)
                  : Colors.green,
              fontWeight: FontWeight.w600,
              fontSize: screenWidth * 0.032,
            ),
          ),
        ),
        onTap: () => _showAlertDetails(alert, screenWidth, screenHeight),
      ),
    );
  }

  Widget _buildHistory(double screenWidth, double screenHeight) {
    return RefreshIndicator(
      color: const Color(0xFFF73D5C),
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.all(screenWidth * 0.05),
        children: [
          const Text('Emergency Alert History',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black)),
          SizedBox(height: screenHeight * 0.015),
          if (_sosAlerts.isEmpty)
            Container(
              padding: EdgeInsets.all(screenWidth * 0.05),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Center(
                child: Text(
                  'No emergency alerts in history',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            )
          else
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
                    title: Text(alert['name'],
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(alert['location'],
                            style: TextStyle(
                                fontSize: screenWidth * 0.035,
                                color: Colors.grey.shade700)),
                        Text(_formatDate(alert['time']),
                            style: TextStyle(
                                fontSize: screenWidth * 0.032,
                                color: Colors.grey.shade500)),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: alert['status'] == 'active'
                            ? const Color(0xFFF73D5C).withOpacity(0.1)
                            : Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        alert['status'].toUpperCase(),
                        style: TextStyle(
                          color: alert['status'] == 'active'
                              ? const Color(0xFFF73D5C)
                              : Colors.green,
                          fontWeight: FontWeight.w600,
                          fontSize: screenWidth * 0.032,
                        ),
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildProfileSettings(double screenWidth, double screenHeight) {
    return ListView(
      padding: EdgeInsets.all(screenWidth * 0.05),
      children: [
        const Text('Emergency Contact Profile',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black)),
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
                    child: const Icon(Icons.contact_emergency,
                        color: Color(0xFFF73D5C)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_profile['name'] ?? 'Unknown',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Role: ${_profile['role'] ?? 'Emergency Contact'}',
                            style: TextStyle(
                                color: Colors.grey.shade700, fontSize: 14)),
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
                  Text(_profile['phone'] ?? 'No phone number',
                      style: const TextStyle(fontSize: 15)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.email, color: Colors.grey, size: 20),
                  const SizedBox(width: 8),
                  Text(_profile['email'] ?? 'No email',
                      style: const TextStyle(fontSize: 15)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.notifications, color: Colors.grey, size: 20),
                  const SizedBox(width: 8),
                  const Text('Notifications: ',
                      style: TextStyle(fontSize: 15, color: Colors.black)),
                  const SizedBox(width: 6),
                  Text(_profile['notifPref'] ?? 'Push + SMS',
                      style:
                          TextStyle(fontSize: 15, color: Colors.grey.shade700)),
                ],
              ),
            ],
          ),
        ),

        SizedBox(height: screenHeight * 0.02),

        // Groups where user is a member
        if (_emergencyContactData['group_memberships']?.isNotEmpty == true)
          _buildGroupMemberships(screenWidth, screenHeight),
      ],
    );
  }

  Widget _buildGroupMemberships(double screenWidth, double screenHeight) {
    final groupMemberships = _emergencyContactData['group_memberships'] as List;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Emergency Groups',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        SizedBox(height: screenHeight * 0.01),
        ...groupMemberships.map((membership) => Container(
              margin: EdgeInsets.only(bottom: screenHeight * 0.01),
              padding: EdgeInsets.all(screenWidth * 0.04),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    membership['group']?['name'] ?? 'Unknown Group',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  if (membership['group']?['creator'] != null)
                    Text(
                      'Added by: ${membership['group']['creator']['first_name'] ?? ''} ${membership['group']['creator']['last_name'] ?? ''}'
                          .trim(),
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    'Relationship: ${membership['relationship'] ?? 'Not specified'}',
                    style: TextStyle(
                        color: const Color(0xFFF73D5C),
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  int _getContactCount() {
    final groupMemberships =
        _emergencyContactData['group_memberships'] as List? ?? [];
    final emergencyContacts =
        _emergencyContactData['emergency_contacts'] as List? ?? [];

    // Count unique users who have this person as emergency contact
    Set<String> uniqueUsers = {};

    for (var membership in groupMemberships) {
      if (membership['group']?['created_by'] != null) {
        uniqueUsers.add(membership['group']['created_by']);
      }
    }

    for (var contact in emergencyContacts) {
      if (contact['user_id'] != null) {
        uniqueUsers.add(contact['user_id']);
      }
    }

    return uniqueUsers.length;
  }

  void _showAlertDetails(
      Map<String, dynamic> alert, double screenWidth, double screenHeight) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                      child: const Icon(Icons.person,
                          color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(alert['name'],
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: screenWidth * 0.05)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.access_time, color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Text(_formatDate(alert['time']),
                        style: TextStyle(
                            fontSize: 15, color: Colors.grey.shade700)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(alert['location'],
                            style: const TextStyle(fontSize: 15))),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Text('Status: ',
                        style: TextStyle(fontSize: 15, color: Colors.black)),
                    Text(alert['status'],
                        style: TextStyle(
                            fontSize: 15,
                            color: alert['status'] == 'active'
                                ? const Color(0xFFF73D5C)
                                : Colors.green)),
                  ],
                ),
                if (alert['emergency_level'] != 'regular') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.priority_high,
                          color: Colors.grey, size: 20),
                      const SizedBox(width: 8),
                      Text('Level: ',
                          style: TextStyle(fontSize: 15, color: Colors.black)),
                      Text(
                        alert['emergency_level'].toUpperCase(),
                        style: TextStyle(
                          fontSize: 15,
                          color: alert['emergency_level'] == 'critical'
                              ? Colors.red
                              : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
                if (alert['description']?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.description,
                          color: Colors.grey, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Description:',
                                style: TextStyle(
                                    fontSize: 15, color: Colors.black)),
                            const SizedBox(height: 4),
                            Text(alert['description'],
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey.shade700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF73D5C),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      alert['status'] == 'active'
                          ? 'Mark as Acknowledged'
                          : 'Close',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16),
                    ),
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
