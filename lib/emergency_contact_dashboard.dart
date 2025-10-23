import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'services/parent_notification_service.dart';

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
  bool _isRefreshing = false;

  List<Map<String, dynamic>> _sosAlerts = [];
  Map<String, dynamic> _emergencyContactData = {};

  // Track unread alerts
  int get _unreadAlertsCount => _sosAlerts
      .where((alert) =>
          alert['viewed_at'] == null && alert['status'] != 'resolved')
      .length;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initializeNotifications();
  }

  /// Initialize parent notification service
  Future<void> _initializeNotifications() async {
    try {
      debugPrint('🔔 Initializing parent notifications in dashboard...');
      await ParentNotificationService().initialize(
        onNewNotification: () {
          // Refresh the alerts list when a new notification arrives
          debugPrint('🔄 New notification received, refreshing dashboard...');
          if (mounted) {
            _loadSosAlerts();
            // Show a snackbar to indicate new alert
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.notification_important, color: Colors.white),
                    SizedBox(width: 8),
                    Text('New emergency alert received!'),
                  ],
                ),
                backgroundColor: Color(0xFFF73D5C),
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      );
      debugPrint('✅ Parent notifications initialized in dashboard');
    } catch (e) {
      debugPrint('❌ Error initializing parent notifications: $e');
    }
  }

  @override
  void dispose() {
    // Clean up notification service
    ParentNotificationService().dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _isRefreshing = true;
    });

    try {
      debugPrint('🔄 Loading emergency contact dashboard data...');

      // Load emergency contact data directly
      _emergencyContactData = await _getEmergencyContactData();

      // Load SOS alerts (emergency logs where this user is the emergency contact)
      await _loadSosAlerts();

      debugPrint('✅ Dashboard data loaded successfully');
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Error loading data: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
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
      debugPrint('Current user ID: $userId');
      List<dynamic> emergencyContacts = [];

      // The key insight from debug output: emergency contacts are linked via group_member_id
      // BUT we need to find the specific group_member record that the emergency contact references
      try {
        // First, get ALL group_member records to understand the relationships
        debugPrint('Analyzing group_member relationships...');

        // Find emergency contacts that have a group_member_id
        final allEmergencyContacts = await supabase
            .from('emergency_contacts')
            .select('*')
            .not('group_member_id', 'is',
                null); // Only get contacts with group_member_id

        debugPrint(
            'Found ${allEmergencyContacts.length} emergency contacts with group_member_id');

        for (var contact in allEmergencyContacts) {
          if (contact['group_member_id'] != null) {
            try {
              // Get the group_member record that this emergency contact references
              final referencedGroupMember = await supabase
                  .from('group_members')
                  .select('*')
                  .eq('id', contact['group_member_id'])
                  .single();

              debugPrint(
                  'Emergency contact ${contact['id']} references group_member: ${referencedGroupMember['id']} with user_id: ${referencedGroupMember['user_id']}');

              // Check if this group_member belongs to the current user
              if (referencedGroupMember['user_id'] == userId) {
                // This emergency contact references the current user!
                emergencyContacts.add(contact);
                debugPrint(
                    'FOUND MATCH: Emergency contact from user ${contact['user_id']} references current user via group_member_id ${contact['group_member_id']}');
              }
            } catch (e) {
              debugPrint(
                  'Error getting group_member ${contact['group_member_id']}: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('Error finding group_members: $e');
      }

      debugPrint(
          'Total emergency contacts where current user is listed: ${emergencyContacts.length}');

      // Get group memberships where this user is a member
      List<dynamic> groupMemberships = [];
      try {
        final groupMembers = await supabase
            .from('group_members')
            .select('*')
            .eq('user_id', userId);

        debugPrint(
            'Found ${groupMembers.length} group memberships in group_members table');

        // Load group details for each membership
        for (var member in groupMembers) {
          try {
            // Use 'group' table - use maybeSingle() to handle missing groups gracefully
            final groupData = await supabase
                .from('group')
                .select('id, name, created_by')
                .eq('id', member['group_id'])
                .maybeSingle();

            // Skip if group doesn't exist (orphaned group_member record)
            if (groupData == null) {
              debugPrint(
                  '⚠️ Skipping orphaned group_member record - group ${member['group_id']} does not exist');
              continue;
            }

            // Create membership object
            final membership = {
              'id': member['id'],
              'group_id': member['group_id'],
              'user_id': member['user_id'],
              'relationship': member['relationship'],
              'group': groupData,
            };

            // Load creator details
            if (groupData['created_by'] != null) {
              try {
                final creatorData = await supabase
                    .from('user')
                    .select('id, first_name, last_name, phone, email')
                    .eq('id', groupData['created_by'])
                    .maybeSingle();

                if (creatorData != null) {
                  membership['group']['creator'] = creatorData;
                } else {
                  debugPrint(
                      '⚠️ Group creator user ${groupData['created_by']} not found');
                }
              } catch (e) {
                debugPrint(
                    '❌ Error loading creator for group ${groupData['id']}: $e');
              }
            }

            groupMemberships.add(membership);
            debugPrint('✅ Added group membership: ${groupData['name']}');
          } catch (e) {
            debugPrint(
                '❌ Error loading group details for group ${member['group_id']}: $e');
          }
        }
      } catch (e) {
        debugPrint('Error loading group memberships: $e');
      }

      final result = {
        'emergency_contacts': emergencyContacts,
        'group_memberships': groupMemberships,
      };

      debugPrint(
          'Final result: Emergency contacts: ${emergencyContacts.length}, Group memberships: ${groupMemberships.length}');

      return result;
    } catch (e) {
      debugPrint('Error getting emergency contact data: $e');
      return {
        'emergency_contacts': [],
        'group_memberships': [],
      };
    }
  }

  Future<void> _loadSosAlerts() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      debugPrint('🔍 Loading parent notifications for user: $userId');

      // Load from parent_notifications table instead of logs
      final notifications = await supabase
          .from('parent_notifications')
          .select('*')
          .eq('parent_user_id', userId)
          .order('created_at', ascending: false);

      debugPrint('📥 Found ${notifications.length} parent notifications');

      if (notifications.isEmpty) {
        debugPrint('No notifications found for this parent');
        setState(() {
          _sosAlerts = [];
        });
        return;
      }

      // Process parent notifications
      List<Map<String, dynamic>> processedAlerts = [];
      for (var notification in notifications) {
        try {
          final notificationData =
              notification['notification_data'] as Map<String, dynamic>?;

          // Get child user info
          String childName = notificationData?['child_name'] ?? 'Unknown User';
          if (notification['child_user_id'] != null) {
            try {
              final userInfo = await supabase
                  .from('user')
                  .select('first_name, last_name')
                  .eq('id', notification['child_user_id'])
                  .maybeSingle();

              if (userInfo != null) {
                childName =
                    '${userInfo['first_name'] ?? ''} ${userInfo['last_name'] ?? ''}'
                        .trim();
                if (childName.isEmpty) {
                  childName = notificationData?['child_name'] ?? 'Unknown User';
                }
              }
            } catch (e) {
              debugPrint('Error fetching child user info: $e');
            }
          }

          // Determine status based on alert_type and viewed_at
          String status = 'active';
          final alertType = notification['alert_type'] as String?;
          if (alertType == 'CANCEL') {
            status = 'resolved';
          } else if (notification['viewed_at'] != null) {
            status = 'viewed';
          }

          // Extract location from notification_data
          String location = 'Location not available';
          if (notificationData != null) {
            if (notificationData['address'] != null) {
              location = notificationData['address'];
            } else if (notificationData['latitude'] != null &&
                notificationData['longitude'] != null) {
              location =
                  'Lat: ${notificationData['latitude']}, Lng: ${notificationData['longitude']}';
            }
          }

          // Determine emergency level based on alert type
          String emergencyLevel = 'regular';
          if (alertType == 'CRITICAL') {
            emergencyLevel = 'critical';
          } else if (alertType == 'CANCEL') {
            emergencyLevel = 'cancelled';
          } else if (alertType == 'REGULAR') {
            emergencyLevel = 'regular';
          }

          processedAlerts.add({
            'id': notification['id'],
            'name': childName,
            'time': DateTime.parse(notification['created_at']),
            'location': location,
            'status': status,
            'emergency_level': emergencyLevel,
            'alert_type': alertType, // Add raw alert type for reference
            'description': notification['notification_body'] ?? '',
            'title': notification['notification_title'] ?? '',
            'userId': notification['child_user_id'],
            'viewed_at': notification['viewed_at'],
            'battery_level': notificationData?['battery_level'],
            'raw_data': notification, // Keep raw data for debugging
          });

          debugPrint('✅ Processed notification: $childName at $location');
        } catch (e) {
          debugPrint(
              '❌ Error processing notification ${notification['id']}: $e');
          // Still add the notification with basic info
          final alertType = notification['alert_type'] as String?;
          String emergencyLevel = 'regular';
          if (alertType == 'CRITICAL') {
            emergencyLevel = 'critical';
          } else if (alertType == 'CANCEL') {
            emergencyLevel = 'cancelled';
          }

          processedAlerts.add({
            'id': notification['id'],
            'name': 'Unknown User',
            'time': DateTime.parse(notification['created_at']),
            'location': 'Location not available',
            'status': alertType == 'CANCEL' ? 'resolved' : 'active',
            'emergency_level': emergencyLevel,
            'alert_type': alertType,
            'description': notification['notification_body'] ?? '',
            'title': notification['notification_title'] ?? '',
            'userId': notification['child_user_id'],
            'viewed_at': notification['viewed_at'],
            'raw_data': notification,
          });
        }
      }

      debugPrint(
          'Processed ${processedAlerts.length} total alerts for history');
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

  /// Mark an alert as viewed
  Future<void> _markAlertAsViewed(Map<String, dynamic> alert) async {
    try {
      final alertId = alert['id'];
      debugPrint('👁️ Marking alert $alertId as viewed...');

      await supabase.from('parent_notifications').update(
          {'viewed_at': DateTime.now().toIso8601String()}).eq('id', alertId);

      // Update local state
      setState(() {
        final index = _sosAlerts.indexWhere((a) => a['id'] == alertId);
        if (index != -1) {
          _sosAlerts[index]['viewed_at'] = DateTime.now().toIso8601String();
          _sosAlerts[index]['status'] = 'viewed';
        }
      });

      debugPrint('✅ Alert marked as viewed');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alert marked as viewed'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error marking alert as viewed: $e');
    }
  }

  List<String> _getRelatedUserIds() {
    List<String> userIds = [];

    // Get user IDs from groups where this user is a member (the group creators)
    final groupMemberships =
        _emergencyContactData['group_memberships'] as List? ?? [];
    for (var membership in groupMemberships) {
      if (membership['group'] != null &&
          membership['group']['created_by'] != null) {
        userIds.add(membership['group']['created_by']);
        debugPrint(
            'Added group creator user ID: ${membership['group']['created_by']}');
      }
    }

    // Get user IDs from emergency contacts (the users who have this person as emergency contact)
    final emergencyContacts =
        _emergencyContactData['emergency_contacts'] as List? ?? [];
    for (var contact in emergencyContacts) {
      if (contact['user_id'] != null) {
        userIds.add(contact['user_id']);
        debugPrint('Added emergency contact user ID: ${contact['user_id']}');
      }
    }

    final uniqueUserIds = userIds.toSet().toList();
    debugPrint('Final unique user IDs: $uniqueUserIds');
    return uniqueUserIds;
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
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Emergency Contact Dashboard',
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    fontSize: 18)),
            if (_unreadAlertsCount > 0) ...[
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(0xFFF73D5C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_unreadAlertsCount',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Refresh button
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: _isRefreshing ? Color(0xFFF73D5C) : Colors.black,
            ),
            onPressed: _isRefreshing ? null : _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              _buildDashboard(screenWidth, screenHeight),
              _buildHistory(screenWidth, screenHeight),
            ],
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFF73D5C),
        unselectedItemColor: Colors.grey.shade600,
        backgroundColor: Colors.white,
        onTap: (index) {
          if (index == 2) {
            // Switch view action
            _showRoleSwitchDialog();
          } else {
            _onTabTapped(index);
          }
        },
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
            icon: Icon(Icons.swap_horiz),
            label: 'Switch View',
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0 && _sosAlerts.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showAlertStatistics(),
              backgroundColor: Color(0xFFF73D5C),
              icon: Icon(Icons.analytics),
              label: Text('Statistics'),
            )
          : null,
    );
  }

  void _showAlertStatistics() {
    final criticalCount =
        _sosAlerts.where((a) => a['emergency_level'] == 'critical').length;
    final regularCount =
        _sosAlerts.where((a) => a['emergency_level'] == 'regular').length;
    final cancelledCount =
        _sosAlerts.where((a) => a['emergency_level'] == 'cancelled').length;
    final activeCount = _sosAlerts.where((a) => a['status'] == 'active').length;
    final resolvedCount =
        _sosAlerts.where((a) => a['status'] == 'resolved').length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.analytics, color: Color(0xFFF73D5C)),
            SizedBox(width: 8),
            Text('Alert Statistics'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Alerts: ${_sosAlerts.length}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Divider(height: 24),
            _buildStatRow('🔴 Critical', criticalCount, Colors.red),
            _buildStatRow('🟠 Regular', regularCount, Colors.orange),
            _buildStatRow('🟢 Cancelled', cancelledCount, Colors.green),
            Divider(height: 24),
            _buildStatRow('⚠️ Active', activeCount, Color(0xFFF73D5C)),
            _buildStatRow('✅ Resolved', resolvedCount, Colors.green),
            _buildStatRow('👁️ Unread', _unreadAlertsCount, Colors.blue),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int count, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
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
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF73D5C),
            ),
            child: const Text('Switch to User View'),
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
          // Loading indicator banner
          if (_isRefreshing)
            Container(
              padding: EdgeInsets.all(12),
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Color(0xFFF73D5C).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Color(0xFFF73D5C).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFF73D5C)),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Refreshing alerts...',
                    style: TextStyle(
                      color: Color(0xFFF73D5C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // Unread alerts summary
          if (_unreadAlertsCount > 0)
            Container(
              padding: EdgeInsets.all(12),
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFF73D5C).withValues(alpha: 0.15),
                    Color(0xFFF73D5C).withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Color(0xFFF73D5C).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.notification_important,
                      color: Color(0xFFF73D5C), size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You have $_unreadAlertsCount unread alert${_unreadAlertsCount > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFFF73D5C),
                          ),
                        ),
                        Text(
                          'Swipe right on alerts to mark as viewed',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Role indicator - only show when not listed as emergency contact yet
          if (_getContactCount() == 0)
            Container(
              padding: EdgeInsets.all(screenWidth * 0.04),
              margin: EdgeInsets.only(bottom: screenHeight * 0.02),
              decoration: BoxDecoration(
                color: const Color(0xFFF73D5C).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFF73D5C).withValues(alpha: 0.3)),
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
                          'You are not listed as an emergency contact yet',
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

          const Text('People Who Listed You as Emergency Contact',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black)),
          SizedBox(height: screenHeight * 0.015),

          // Show emergency contacts who have listed this user
          if (_emergencyContactData['emergency_contacts']?.isEmpty ?? true)
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
                      Icons.person_add_disabled,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No one has listed you as emergency contact yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._buildEmergencyContactCards(screenWidth, screenHeight),

          SizedBox(height: screenHeight * 0.03),

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
    final isUnread =
        alert['viewed_at'] == null && alert['status'] != 'resolved';

    return Dismissible(
      key: Key('alert_${alert['id']}'),
      background: Container(
        margin: EdgeInsets.only(bottom: screenHeight * 0.015),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.only(left: 20),
        child: Icon(Icons.check_circle, color: Colors.white, size: 30),
      ),
      secondaryBackground: Container(
        margin: EdgeInsets.only(bottom: screenHeight * 0.015),
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        child: Icon(Icons.info, color: Colors.white, size: 30),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Mark as viewed
          await _markAlertAsViewed(alert);
          return false; // Don't dismiss the card
        } else {
          // Show details
          _showAlertDetails(alert, screenWidth, screenHeight);
          return false; // Don't dismiss the card
        }
      },
      child: Container(
        margin: EdgeInsets.only(bottom: screenHeight * 0.015),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: isUnread
                ? Color(0xFFF73D5C).withValues(alpha: 0.3)
                : Colors.grey.shade200,
            width: isUnread ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            ListTile(
              leading: Stack(
                children: [
                  FutureBuilder<String?>(
                    future: _getUserProfilePhoto(alert['userId']),
                    builder: (context, snapshot) {
                      return CircleAvatar(
                        backgroundColor: alert['status'] == 'active'
                            ? const Color(0xFFF73D5C).withValues(alpha: 0.15)
                            : Colors.green.withValues(alpha: 0.15),
                        backgroundImage:
                            snapshot.hasData && snapshot.data!.isNotEmpty
                                ? NetworkImage(snapshot.data!)
                                : null,
                        child: snapshot.hasData && snapshot.data!.isNotEmpty
                            ? null
                            : Icon(
                                alert['status'] == 'active'
                                    ? Icons.warning
                                    : Icons.check_circle,
                                color: alert['status'] == 'active'
                                    ? const Color(0xFFF73D5C)
                                    : Colors.green,
                              ),
                      );
                    },
                  ),
                  if (isUnread)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Color(0xFFF73D5C),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(alert['name'],
                  style: TextStyle(
                    fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                  )),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: alert['emergency_level'] == 'critical'
                            ? Colors.red.withValues(alpha: 0.1)
                            : alert['emergency_level'] == 'cancelled'
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        alert['emergency_level'].toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: alert['emergency_level'] == 'critical'
                              ? Colors.red
                              : alert['emergency_level'] == 'cancelled'
                                  ? Colors.green
                                  : Colors.orange,
                        ),
                      ),
                    ),
                ],
              ),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: alert['status'] == 'active'
                      ? const Color(0xFFF73D5C).withValues(alpha: 0.1)
                      : Colors.green.withValues(alpha: 0.1),
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
            // Quick action buttons
            if (isUnread)
              Container(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.check, size: 16),
                        label: Text('Mark as Viewed',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                          side: BorderSide(color: Colors.green),
                          padding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: () => _markAlertAsViewed(alert),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.info_outline, size: 16),
                        label: Text('Details', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFF73D5C),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: () =>
                            _showAlertDetails(alert, screenWidth, screenHeight),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
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

          // Show total count
          if (_sosAlerts.isNotEmpty)
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.04,
                  vertical: screenHeight * 0.01),
              margin: EdgeInsets.only(bottom: screenHeight * 0.02),
              decoration: BoxDecoration(
                color: const Color(0xFFF73D5C).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFF73D5C).withValues(alpha: 0.3)),
              ),
              child: Text(
                'Total alerts: ${_sosAlerts.length}',
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xFFF73D5C),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

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
                      Icons.history,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No emergency alerts in history',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Emergency alerts from people you\'re listed as an emergency contact for will appear here.',
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
            ..._sosAlerts.map((alert) => Container(
                  margin: EdgeInsets.only(bottom: screenHeight * 0.015),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(screenWidth * 0.04),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with name and emergency level
                        Row(
                          children: [
                            FutureBuilder<String?>(
                              future: _getUserProfilePhoto(alert['userId']),
                              builder: (context, snapshot) {
                                return CircleAvatar(
                                  backgroundColor: alert['status'] == 'active'
                                      ? const Color(0xFFF73D5C)
                                          .withValues(alpha: 0.15)
                                      : alert['status'] == 'resolved'
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : Colors.grey.withValues(alpha: 0.15),
                                  backgroundImage: snapshot.hasData &&
                                          snapshot.data!.isNotEmpty
                                      ? NetworkImage(snapshot.data!)
                                      : null,
                                  child: snapshot.hasData &&
                                          snapshot.data!.isNotEmpty
                                      ? null
                                      : Icon(
                                          alert['status'] == 'active'
                                              ? Icons.warning
                                              : alert['status'] == 'resolved'
                                                  ? Icons.check_circle
                                                  : Icons.history,
                                          color: alert['status'] == 'active'
                                              ? const Color(0xFFF73D5C)
                                              : alert['status'] == 'resolved'
                                                  ? Colors.green
                                                  : Colors.grey.shade700,
                                          size: 20,
                                        ),
                                );
                              },
                            ),
                            SizedBox(width: screenWidth * 0.03),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    alert['name'],
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: screenWidth * 0.045,
                                      color: Colors.black,
                                    ),
                                  ),
                                  if (alert['emergency_level'] != 'regular')
                                    Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: alert['emergency_level'] ==
                                                'critical'
                                            ? Colors.red.withValues(alpha: 0.1)
                                            : alert['emergency_level'] ==
                                                    'checkin'
                                                ? Colors.blue
                                                    .withValues(alpha: 0.1)
                                                : Colors.orange
                                                    .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        alert['emergency_level'].toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: alert['emergency_level'] ==
                                                  'critical'
                                              ? Colors.red
                                              : alert['emergency_level'] ==
                                                      'checkin'
                                                  ? Colors.blue
                                                  : Colors.orange,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: alert['status'] == 'active'
                                    ? const Color(0xFFF73D5C)
                                        .withValues(alpha: 0.1)
                                    : alert['status'] == 'resolved'
                                        ? Colors.green.withValues(alpha: 0.1)
                                        : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                alert['status'].toUpperCase(),
                                style: TextStyle(
                                  color: alert['status'] == 'active'
                                      ? const Color(0xFFF73D5C)
                                      : alert['status'] == 'resolved'
                                          ? Colors.green
                                          : Colors.grey.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: screenWidth * 0.025,
                                ),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: screenHeight * 0.015),

                        // Time & Date - More prominent
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              color: const Color(0xFFF73D5C),
                              size: screenWidth * 0.045,
                            ),
                            SizedBox(width: screenWidth * 0.02),
                            Text(
                              _formatDetailedDate(alert['time']),
                              style: TextStyle(
                                fontSize: screenWidth * 0.038,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: screenHeight * 0.01),

                        // Location - More prominent
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.location_on,
                              color: const Color(0xFFF73D5C),
                              size: screenWidth * 0.045,
                            ),
                            SizedBox(width: screenWidth * 0.02),
                            Expanded(
                              child: Text(
                                alert['location'],
                                style: TextStyle(
                                  fontSize: screenWidth * 0.036,
                                  color: Colors.black87,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        // Description if available
                        if (alert['description']?.isNotEmpty == true) ...[
                          SizedBox(height: screenHeight * 0.01),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.description,
                                color: Colors.grey.shade600,
                                size: screenWidth * 0.04,
                              ),
                              SizedBox(width: screenWidth * 0.02),
                              Expanded(
                                child: Text(
                                  alert['description'],
                                  style: TextStyle(
                                    fontSize: screenWidth * 0.033,
                                    color: Colors.grey.shade700,
                                    fontStyle: FontStyle.italic,
                                    height: 1.3,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Responded info if available
                        if (alert['responded_at'] != null) ...[
                          SizedBox(height: screenHeight * 0.01),
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: screenWidth * 0.04,
                              ),
                              SizedBox(width: screenWidth * 0.02),
                              Text(
                                'Responded: ${_formatDetailedDate(DateTime.parse(alert['responded_at']))}',
                                style: TextStyle(
                                  fontSize: screenWidth * 0.03,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],

                        SizedBox(height: screenHeight * 0.015),

                        // Tap for details
                        GestureDetector(
                          onTap: () => _showAlertDetails(
                              alert, screenWidth, screenHeight),
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                                vertical: screenHeight * 0.008),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'View Details',
                                  style: TextStyle(
                                    color: const Color(0xFFF73D5C),
                                    fontSize: screenWidth * 0.032,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(width: screenWidth * 0.02),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  color: const Color(0xFFF73D5C),
                                  size: screenWidth * 0.03,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      ),
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
                    FutureBuilder<String?>(
                      future: _getUserProfilePhoto(alert['userId']),
                      builder: (context, snapshot) {
                        return CircleAvatar(
                          backgroundColor: const Color(0xFFF73D5C),
                          radius: screenWidth * 0.07,
                          backgroundImage:
                              snapshot.hasData && snapshot.data!.isNotEmpty
                                  ? NetworkImage(snapshot.data!)
                                  : null,
                          child: snapshot.hasData && snapshot.data!.isNotEmpty
                              ? null
                              : const Icon(Icons.person,
                                  color: Colors.white, size: 32),
                        );
                      },
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

  List<Widget> _buildEmergencyContactCards(
      double screenWidth, double screenHeight) {
    final emergencyContacts =
        _emergencyContactData['emergency_contacts'] as List? ?? [];

    return emergencyContacts.map((contact) {
      return Container(
        margin: EdgeInsets.only(bottom: screenHeight * 0.015),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: ListTile(
          leading: FutureBuilder<String?>(
            future: _getUserProfilePhoto(contact['user_id']),
            builder: (context, snapshot) {
              return CircleAvatar(
                backgroundColor:
                    const Color(0xFFF73D5C).withValues(alpha: 0.15),
                backgroundImage: snapshot.hasData && snapshot.data!.isNotEmpty
                    ? NetworkImage(snapshot.data!)
                    : null,
                child: snapshot.hasData && snapshot.data!.isNotEmpty
                    ? null
                    : const Icon(Icons.person, color: Color(0xFFF73D5C)),
              );
            },
          ),
          title: FutureBuilder<String>(
            future: _getUserName(contact['user_id']),
            builder: (context, snapshot) {
              return Text(
                snapshot.data ?? 'Loading...',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              );
            },
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                'Listed you as: ${contact['emergency_contact_relationship'] ?? 'Emergency Contact'}',
                style: TextStyle(
                  color: const Color(0xFFF73D5C),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              if (contact['emergency_contact_phone'] != null)
                Text(
                  'Your contact info: ${contact['emergency_contact_phone']}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                'Added: ${_formatDate(DateTime.parse(contact['created_at']))}',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          trailing: Icon(
            Icons.verified_user,
            color: Colors.green,
            size: 24,
          ),
          onTap: () =>
              _showEmergencyContactDetails(contact, screenWidth, screenHeight),
        ),
      );
    }).toList();
  }

  Future<String> _getUserName(String? userId) async {
    if (userId == null) return 'Unknown User';

    try {
      final userData = await supabase
          .from('user')
          .select('first_name, last_name')
          .eq('id', userId)
          .single();

      final firstName = userData['first_name'] ?? '';
      final lastName = userData['last_name'] ?? '';
      final fullName = '$firstName $lastName'.trim();

      return fullName.isEmpty ? 'Unknown User' : fullName;
    } catch (e) {
      debugPrint('Error loading user name for $userId: $e');
      return 'Unknown User';
    }
  }

  void _showEmergencyContactDetails(
      Map<String, dynamic> contact, double screenWidth, double screenHeight) {
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
                    FutureBuilder<String?>(
                      future: _getUserProfilePhoto(contact['user_id']),
                      builder: (context, snapshot) {
                        return CircleAvatar(
                          backgroundColor: const Color(0xFFF73D5C),
                          radius: screenWidth * 0.07,
                          backgroundImage:
                              snapshot.hasData && snapshot.data!.isNotEmpty
                                  ? NetworkImage(snapshot.data!)
                                  : null,
                          child: snapshot.hasData && snapshot.data!.isNotEmpty
                              ? null
                              : const Icon(Icons.person,
                                  color: Colors.white, size: 32),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FutureBuilder<String>(
                        future: _getUserName(contact['user_id']),
                        builder: (context, snapshot) {
                          return Text(
                            snapshot.data ?? 'Loading...',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: screenWidth * 0.05,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.contact_emergency,
                        color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Text('Relationship: ',
                        style: TextStyle(fontSize: 15, color: Colors.black)),
                    Text(
                      contact['emergency_contact_relationship'] ??
                          'Not specified',
                      style: TextStyle(
                          fontSize: 15,
                          color: const Color(0xFFF73D5C),
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (contact['emergency_contact_phone'] != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.phone, color: Colors.grey, size: 20),
                      const SizedBox(width: 8),
                      Text('Your contact info: ',
                          style: TextStyle(fontSize: 15, color: Colors.black)),
                      Text(
                        contact['emergency_contact_phone'],
                        style: TextStyle(
                            fontSize: 15, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    const Icon(Icons.access_time, color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Text('Added on: ',
                        style: TextStyle(fontSize: 15, color: Colors.black)),
                    Text(
                      _formatDate(DateTime.parse(contact['created_at'])),
                      style:
                          TextStyle(fontSize: 15, color: Colors.grey.shade700),
                    ),
                  ],
                ),
                if (contact['added_by'] != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.person_add,
                          color: Colors.grey, size: 20),
                      const SizedBox(width: 8),
                      Text('Added by: ',
                          style: TextStyle(fontSize: 15, color: Colors.black)),
                      Text(
                        contact['added_by'],
                        style: TextStyle(
                            fontSize: 15, color: Colors.grey.shade700),
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
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
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

  Future<String?> _getUserProfilePhoto(String? userId) async {
    if (userId == null) return null;

    try {
      final userData = await supabase
          .from('user')
          .select('profile_photo_url')
          .eq('id', userId)
          .single();

      return userData['profile_photo_url'];
    } catch (e) {
      debugPrint('Error fetching profile photo for user $userId: $e');
      return null;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDetailedDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    // Format: "Dec 15, 2023 at 2:30 PM (2 hours ago)"
    String monthName = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ][date.month];

    String period = date.hour >= 12 ? 'PM' : 'AM';
    int hour =
        date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    String minute = date.minute.toString().padLeft(2, '0');

    String timeAgo = '';
    if (difference.inMinutes < 60) {
      timeAgo = '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      timeAgo = '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      timeAgo = '${difference.inDays} days ago';
    } else {
      timeAgo = '${(difference.inDays / 7).floor()} weeks ago';
    }

    return '$monthName ${date.day}, ${date.year} at $hour:$minute $period ($timeAgo)';
  }
}
