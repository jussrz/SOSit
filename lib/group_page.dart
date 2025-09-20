import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  final supabase = Supabase.instance.client;
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _emailSearchController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();
  bool _isLoading = false;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, List<Map<String, dynamic>>> _groupMembers = {};

  // Add a separate loading state for search
  bool _isSearching = false;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ No user ID found');
        return;
      }

      debugPrint('📥 Loading groups for user: $userId');

      // Load user's groups
      final groups = await supabase
          .from('group')
          .select()
          .eq('created_by', userId)
          .order('created_at');

      debugPrint('📊 Found ${groups.length} groups:');
      for (var group in groups) {
        debugPrint('   - Group: ${group['name']} (ID: ${group['id']})');
      }

      setState(() {
        _groups = List<Map<String, dynamic>>.from(groups);
      });

      // Load members for each group
      for (var group in _groups) {
        final members = await supabase
            .from('group_members')
            .select('*, user:user(*)')
            .eq('group_id', group['id']);

        debugPrint('👥 Group "${group['name']}" has ${members.length} members');

        setState(() {
          _groupMembers[group['id']] = List<Map<String, dynamic>>.from(members);
        });
      }
      
      debugPrint('✅ Groups loading completed');
    } catch (e) {
      debugPrint('❌ Error loading groups: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading groups: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Create new group
      final result = await supabase
          .from('group')
          .insert({
            'name': _groupNameController.text.trim(),
            'created_by': userId,
          })
          .select()
          .single();

      setState(() {
        _groups.add(result);
        _groupMembers[result['id']] = [];
      });

      _groupNameController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating group: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Modified search function with proper state management
  Future<void> _searchUser(String email, StateSetter dialogSetState) async {
    if (email.length < 3) {
      dialogSetState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    try {
      dialogSetState(() => _isSearching = true);

      // Try to match emails using ilike for case-insensitive partial match
      final searchTerm = email.toLowerCase().trim();
      final results = await supabase
          .from('user')
          .select('id, email, first_name, last_name, phone')
          .or('email.ilike.%${searchTerm}%')
          .limit(5);

      debugPrint('Search results for "$searchTerm": $results');

      if (!mounted) return;
      dialogSetState(() {
        _searchResults = List<Map<String, dynamic>>.from(results);
        _isSearching = false;
      });
    } catch (e) {
      debugPrint('Error in _searchUser: $e');
      if (mounted) {
        dialogSetState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching users: $e')),
        );
      }
    }
  }

  // Debounced search function
  void _onSearchChanged(String value, StateSetter dialogSetState) {
    _searchTimer?.cancel();

    if (value.length < 3) {
      dialogSetState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _searchTimer = Timer(const Duration(milliseconds: 500), () {
      _searchUser(value, dialogSetState);
    });
  }

  // NEW: Function to create emergency contact when adding group member
  Future<void> _createEmergencyContact({
    required String groupId,
    required String groupMemberId,
    required Map<String, dynamic> userData,
    required String relationship,
  }) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      final userEmail = supabase.auth.currentUser?.email;
      if (userId == null || userEmail == null) return;

      // Create emergency contact record
      await supabase.from('emergency_contacts').insert({
        'emergency_contact_name':
            '${userData['first_name']} ${userData['last_name']}',
        'emergency_contact_relationship': relationship,
        'emergency_contact_phone': userData['phone'] ?? '',
        'user_id':
            userId, // The group creator gets this as their emergency contact
        'group_id': groupId,
        'group_member_id': groupMemberId,
        'added_by': userEmail, // Store email instead of user ID
      });

      debugPrint('Emergency contact created for user: ${userData['email']}');
    } catch (e) {
      debugPrint('Error creating emergency contact: $e');
      // Don't throw error to avoid breaking the group member addition
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Warning: Emergency contact creation failed: $e')),
        );
      }
    }
  }

  // MODIFIED: Add member to group with relationship and emergency contact creation
  Future<void> _addMemberToGroup(
      String groupId, Map<String, dynamic> user, String relationship) async {
    if (relationship.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please specify the relationship')),
        );
      }
      return;
    }

    try {
      debugPrint('Attempting to add user ${user['id']} to group $groupId');
      
      // Check if user is already in the group by querying the database directly
      final existingMembers = await supabase
          .from('group_members')
          .select('id')
          .eq('group_id', groupId)
          .eq('user_id', user['id']);

      debugPrint('Found ${existingMembers.length} existing members for this user in this group');

      if (existingMembers.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User is already in this group')),
          );
        }
        return;
      }

      // Check if user already has 2 emergency contacts
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        final existingContacts = await supabase
            .from('emergency_contacts')
            .select('id')
            .eq('user_id', currentUserId);
        
        debugPrint('Current user has ${existingContacts.length} emergency contacts');
        
        if (existingContacts.length >= 2) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Maximum 2 emergency contacts allowed per person')),
            );
          }
          return;
        }
      }

      debugPrint('Adding user to group_members table...');
      
      // Add user to group
      final result = await supabase
          .from('group_members')
          .insert({
            'user_id': user['id'],
            'group_id': groupId,
            'relationship': relationship.trim(),
          })
          .select('*, user:user(*)')
          .single();

      debugPrint('Successfully added to group_members: ${result['id']}');

      // Create corresponding emergency contact
      debugPrint('Creating emergency contact...');
      await _createEmergencyContact(
        groupId: groupId,
        groupMemberId: result['id'],
        userData: user,
        relationship: relationship.trim(),
      );

      // Refresh the group members list from database to ensure consistency
      await _refreshGroupMembers(groupId);

      setState(() {
        _searchResults = [];
        _emailSearchController.clear();
        _relationshipController.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Member and emergency contact added successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error adding member: $e');
      String errorMessage = 'Error adding member';
      
      // Handle specific constraint violations
      if (e.toString().contains('group_members_group_id_key')) {
        errorMessage = 'Database constraint error: Only one member allowed per group. Please contact support to fix this database issue.';
      } else if (e.toString().contains('group_members_user_group_unique')) {
        errorMessage = 'This person is already in this group.';
      } else if (e.toString().contains('duplicate key')) {
        errorMessage = 'This person is already added to this group.';
      } else if (e.toString().contains('violates check constraint')) {
        errorMessage = 'Maximum 2 emergency contacts allowed per person.';
      } else {
        errorMessage = 'Error adding member: ${e.toString()}';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // NEW: Helper method to refresh group members from database
  Future<void> _refreshGroupMembers(String groupId) async {
    try {
      final members = await supabase
          .from('group_members')
          .select('*, user:user(*)')
          .eq('group_id', groupId);

      setState(() {
        _groupMembers[groupId] = List<Map<String, dynamic>>.from(members);
      });
    } catch (e) {
      debugPrint('Error refreshing group members: $e');
    }
  }

  // MODIFIED: Remove member and corresponding emergency contact
  Future<void> _removeMember(String groupId, String memberId) async {
    try {
      // Remove emergency contact first
      await supabase
          .from('emergency_contacts')
          .delete()
          .eq('group_member_id', memberId);

      // Then remove group member
      await supabase.from('group_members').delete().eq('id', memberId);

      setState(() {
        _groupMembers[groupId]
            ?.removeWhere((member) => member['id'] == memberId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Member and emergency contact removed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing member: $e')),
        );
      }
    }
  }

  // COMPLETELY REWRITTEN: Delete group with proper error handling and verification
  Future<void> _deleteGroup(String groupId) async {
    try {
      debugPrint('🗑️ Starting group deletion for groupId: $groupId');
      
      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(color: Color(0xFFF73D5C)),
                SizedBox(width: 20),
                Text('Deleting group...'),
              ],
            ),
          ),
        );
      }

      // STEP 1: Delete emergency contacts (if any)
      debugPrint('� Step 1: Deleting emergency contacts...');
      await supabase
          .from('emergency_contacts')
          .delete()
          .eq('group_id', groupId);
      debugPrint('✅ Emergency contacts deleted');

      // STEP 2: Delete group members (if any)
      debugPrint('🔄 Step 2: Deleting group members...');
      await supabase
          .from('group_members')
          .delete()
          .eq('group_id', groupId);
      debugPrint('✅ Group members deleted');

      // STEP 3: Delete the group - using multiple approaches to ensure deletion
      debugPrint('🔄 Step 3: Deleting group...');
      
      // Check user permissions first
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }
      debugPrint('🔐 Current user ID: $currentUserId');
      
      // Verify user owns this group
      final ownershipCheck = await supabase
          .from('group')
          .select('created_by')
          .eq('id', groupId)
          .single();
      
      debugPrint('👤 Group owner: ${ownershipCheck['created_by']}');
      
      if (ownershipCheck['created_by'] != currentUserId) {
        throw Exception('Permission denied: You can only delete groups you created');
      }
      
      // Try multiple deletion methods with detailed response logging
      bool groupDeleted = false;
      
      // Method 1: Standard delete with response checking
      try {
        debugPrint('🔄 Method 1: Standard delete...');
        final deleteResponse1 = await supabase
            .from('group')
            .delete()
            .eq('id', groupId)
            .select();
        debugPrint('✅ Method 1 response: $deleteResponse1');
        debugPrint('✅ Method 1 deleted ${deleteResponse1.length} records');
        
        if (deleteResponse1.isNotEmpty) {
          groupDeleted = true;
          debugPrint('Method 1: Successfully deleted group');
        }
      } catch (e) {
        debugPrint('❌ Method 1 failed: $e');
      }
      
      // Method 2: Delete with explicit ownership filter (only if Method 1 failed)
      if (!groupDeleted) {
        try {
          debugPrint('🔄 Method 2: Ownership-filtered delete...');
          final deleteResponse2 = await supabase
              .from('group')
              .delete()
              .eq('id', groupId)
              .eq('created_by', currentUserId)
              .select();
          debugPrint('✅ Method 2 response: $deleteResponse2');
          debugPrint('✅ Method 2 deleted ${deleteResponse2.length} records');
          
          if (deleteResponse2.isNotEmpty) {
            groupDeleted = true;
            debugPrint('Method 2: Successfully deleted group');
          }
        } catch (e) {
          debugPrint('❌ Method 2 failed: $e');
        }
      }
      
      // Method 3: Raw SQL approach (only if previous methods failed)
      if (!groupDeleted) {
        try {
          debugPrint('🔄 Method 3: Raw SQL delete...');
          final sqlResult = await supabase.rpc('delete_group_by_id', params: {
            'group_id': groupId,
            'user_id': currentUserId,
          });
          debugPrint('✅ Method 3 SQL response: $sqlResult');
          
          // Check if group still exists after SQL
          final postSqlCheck = await supabase
              .from('group')
              .select('id')
              .eq('id', groupId);
          
          if (postSqlCheck.isEmpty) {
            groupDeleted = true;
            debugPrint('✅ Method 3: Successfully deleted group via SQL');
          }
        } catch (e) {
          debugPrint('❌ Method 3 failed (expected if RPC function doesn\'t exist): $e');
        }
      }
      
      // Method 4: Direct database check and force delete
      if (!groupDeleted) {
        try {
          debugPrint('🔄 Method 4: Force delete with verification...');
          
          // Check if there are any foreign key constraints
          final constraintCheck = await supabase
              .from('group_members')
              .select('id')
              .eq('group_id', groupId);
          debugPrint('🔍 Remaining group_members: ${constraintCheck.length}');
          
          final emergencyCheck = await supabase
              .from('emergency_contacts')
              .select('id')
              .eq('group_id', groupId);
          debugPrint('🔍 Remaining emergency_contacts: ${emergencyCheck.length}');
          
          // Force delete any remaining dependencies
          if (constraintCheck.isNotEmpty) {
            await supabase
                .from('group_members')
                .delete()
                .eq('group_id', groupId);
            debugPrint('🧹 Force deleted remaining group members');
          }
          
          if (emergencyCheck.isNotEmpty) {
            await supabase
                .from('emergency_contacts')
                .delete()
                .eq('group_id', groupId);
            debugPrint('🧹 Force deleted remaining emergency contacts');
          }
          
          // Try delete again after cleanup
          final finalDeleteResponse = await supabase
              .from('group')
              .delete()
              .eq('id', groupId)
              .select();
          debugPrint('✅ Method 4 final delete response: $finalDeleteResponse');
          
          if (finalDeleteResponse.isNotEmpty) {
            groupDeleted = true;
            debugPrint('✅ Method 4: Successfully deleted group after cleanup');
          }
        } catch (e) {
          debugPrint('❌ Method 4 failed: $e');
        }
      }

      // Wait a moment for database consistency
      await Future.delayed(const Duration(milliseconds: 1000));

      // FINAL VERIFICATION: Check if group still exists
      final verificationQuery = await supabase
          .from('group')
          .select('id, name')
          .eq('id', groupId);
      
      debugPrint('🔍 Final verification: ${verificationQuery.length} groups found');
      if (verificationQuery.isNotEmpty) {
        debugPrint('⚠️ Group still exists: ${verificationQuery.first}');
      }

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (verificationQuery.isEmpty || groupDeleted) {
        // SUCCESS: Group is gone
        setState(() {
          _groups.removeWhere((group) => group['id'] == groupId);
          _groupMembers.remove(groupId);
        });

        debugPrint('✅ DELETION SUCCESSFUL - Group completely removed');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Group deleted successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // FAILURE: Group still exists despite all attempts
        debugPrint('💥 CRITICAL: All deletion methods failed');
        debugPrint('🔍 This indicates a database permission or RLS policy issue');
        debugPrint('💡 Possible causes:');
        debugPrint('   - Row Level Security (RLS) policies preventing deletion');
        debugPrint('   - Database user lacks DELETE permissions');
        debugPrint('   - Foreign key constraints (despite cleanup attempts)');
        debugPrint('   - Database triggers preventing deletion');
        
        throw Exception('Group deletion failed: Database may have security policies preventing deletion. Contact your database administrator.');
      }
      
    } catch (e) {
      debugPrint('💥 DELETION FAILED: $e');
      
      // Close loading dialog if still open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      // Force refresh to see current state
      await _loadGroups();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to delete group: ${e.toString()}'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Simplified confirmation dialog for group deletion
  Future<void> _confirmDeleteGroup(String groupId, String groupName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete Group',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
                children: [
                  const TextSpan(text: 'Are you sure you want to delete '),
                  TextSpan(
                    text: '"$groupName"',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF73D5C),
                    ),
                  ),
                  const TextSpan(text: '?'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will also remove all emergency contacts added through this group.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade600,
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
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF73D5C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteGroup(groupId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contact Groups'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Create Group Section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _groupNameController,
                          decoration: InputDecoration(
                            labelText: 'New Group Name',
                            labelStyle: TextStyle(color: Colors.black),
                    floatingLabelStyle: TextStyle(color: Color(0xFFF73D5C)),
                            border: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFF73D5C)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFF73D5C), width: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _createGroup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF73D5C),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24), // match Add Emergency Contact button
                            ),
                            elevation: 2,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                          ),
                          child: const Text(
                            'Create',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              letterSpacing: 0.5,
                              color: Colors.white, // ensure white text
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Info text
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Add family members and friends to your emergency contact groups. They will be automatically added to your emergency contacts.',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Groups List
                Expanded(
                  child: ListView.builder(
                    itemCount: _groups.length,
                    itemBuilder: (context, index) {
                      final group = _groups[index];
                      final members = _groupMembers[group['id']] ?? [];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            childrenPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                            maintainState: true,
                            collapsedBackgroundColor: Colors.white,
                            backgroundColor: Colors.white,
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    group['name'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () => _confirmDeleteGroup(group['id'], group['name']),
                                ),
                              ],
                            ),
                            subtitle:
                                Text('${members.length} emergency contacts'),
                            children: [
                              // Add Member Button
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.person_add),
                                  label: const Text('Add Emergency Contact',
                                    style: TextStyle(
                                      color: Colors.white, // ensure white text
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF73D5C),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 16),
                                  ),
                                  onPressed: () =>
                                      _showAddMemberDialog(group['id']),
                                ),
                              ),

                              // Members List
                              ...members.map((member) {
                                final user = member['user'];
                                return ListTile(
                                  leading: const Icon(Icons.contact_emergency,
                                      color: Color(0xFFF73D5C)),
                                  title: Text(
                                      '${user['first_name']} ${user['last_name']}',
                                    style: const TextStyle(
                                      color: Color(0xFFF73D5C), // accent color for name
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(user['email']),
                                      Text(
                                        'Relationship: ${member['relationship']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFFF73D5C),
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.remove_circle_outline,
                                        color: Colors.red),
                                    onPressed: () =>
                                        _removeMember(group['id'], member['id']),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  // MODIFIED: Add member dialog with relationship input and improved UX
  Future<void> _showAddMemberDialog(String groupId) async {
    _emailSearchController.clear();
    _relationshipController.clear();
    _searchResults.clear();
    _isSearching = false;
    Map<String, dynamic>? selectedUser;

    // Check current emergency contact count
    final currentUserId = supabase.auth.currentUser?.id;
    int currentContactCount = 0;
    if (currentUserId != null) {
      try {
        final existingContacts = await supabase
            .from('emergency_contacts')
            .select('id')
            .eq('user_id', currentUserId);
        currentContactCount = existingContacts.length;
      } catch (e) {
        debugPrint('Error checking contact count: $e');
      }
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Add Emergency Contact',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Emergency contact limit warning
                if (currentContactCount >= 2)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You already have 2 emergency contacts (maximum allowed)',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF73D5C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF73D5C).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: const Color(0xFFF73D5C), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Emergency contacts: $currentContactCount/2',
                            style: const TextStyle(
                              color: Color(0xFFF73D5C),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Search by email field
                TextField(
                  controller: _emailSearchController,
                  enabled: currentContactCount < 2,
                  decoration: InputDecoration(
                    labelText: 'Search by email',
                    labelStyle: TextStyle(color: Colors.black),
                    floatingLabelStyle: TextStyle(color: Color(0xFFF73D5C)),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFF73D5C)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFF73D5C), width: 2),
                    ),
                    prefixIcon: Icon(Icons.email, color: Color(0xFFF73D5C)),
                  ),
                  onChanged: (value) {
                    // Only reset selectedUser if the search field is being cleared
                    // or if the typed value doesn't match the selected user's email
                    if (value.length < 3) {
                      dialogSetState(() {
                        selectedUser = null;
                        _searchResults = [];
                        _isSearching = false;
                      });
                    } else if (selectedUser != null && 
                               !selectedUser!['email'].toLowerCase().contains(value.toLowerCase())) {
                      // Only reset if the current value doesn't match the selected user
                      dialogSetState(() {
                        selectedUser = null;
                      });
                    }
                    _onSearchChanged(value, dialogSetState);
                  },
                ),

                const SizedBox(height: 16),

                // Relationship field
                TextField(
                  controller: _relationshipController,
                  enabled: currentContactCount < 2,
                  decoration: InputDecoration(
                    labelText: 'Relationship (e.g., Mother, Brother, Friend)',
                    labelStyle: TextStyle(color: Colors.black),
                    floatingLabelStyle: TextStyle(color: Color(0xFFF73D5C)),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFF73D5C)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFF73D5C), width: 2),
                    ),
                    prefixIcon: Icon(Icons.family_restroom, color: Color(0xFFF73D5C)),
                    hintText: 'Enter relationship to this person',
                  ),
                  onChanged: (value) {
                    // Trigger rebuild to show/hide the add button
                    dialogSetState(() {});
                  },
                ),

                const SizedBox(height: 16),

                // Add button - only show if all conditions are met
                if (currentContactCount < 2 && 
                    selectedUser != null &&
                    _relationshipController.text.trim().isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _addMemberToGroup(
                          groupId,
                          selectedUser!,
                          _relationshipController.text,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF73D5C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Add Emergency Contact',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // Search results
                if (currentContactCount < 2) ...[
                  if (_isSearching)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFF73D5C),
                      ),
                    )
                  else if (_searchResults.isNotEmpty)
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFF73D5C).withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        margin: const EdgeInsets.only(top: 8),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, index) {
                            final user = _searchResults[index];
                            final isSelected = selectedUser != null &&
                                selectedUser!['id'] == user['id'];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isSelected
                                    ? const Color(0xFFF73D5C)
                                    : Colors.grey.shade200,
                                child: Icon(
                                  Icons.person,
                                  color: isSelected ? Colors.white : Colors.grey,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                '${user['first_name']} ${user['last_name']}',
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected ? const Color(0xFFF73D5C) : Colors.black,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Text(
                                user['email'],
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFFF73D5C)
                                      : Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              selected: isSelected,
                              selectedTileColor: const Color(0xFFFFF0F3),
                              onTap: () {
                                dialogSetState(() => selectedUser = user);
                              },
                            );
                          },
                        ),
                      ),
                    )
                  else if (_emailSearchController.text.length >= 3 &&
                      !_isSearching)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        'No users found',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _emailSearchController.dispose();
    _relationshipController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }
}
