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
      if (userId == null) return;

      // Load user's groups
      final groups = await supabase
          .from('group')
          .select()
          .eq('created_by', userId)
          .order('created_at');

      setState(() {
        _groups = List<Map<String, dynamic>>.from(groups);
      });

      // Load members for each group
      for (var group in _groups) {
        final members = await supabase
            .from('group_members')
            .select('*, user:user(*)')
            .eq('group_id', group['id']);

        setState(() {
          _groupMembers[group['id']] = List<Map<String, dynamic>>.from(members);
        });
      }
    } catch (e) {
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
      // Check if user is already in the group
      final existing = _groupMembers[groupId]?.any(
        (member) => member['user_id'] == user['id'],
      );

      if (existing == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User is already in this group')),
          );
        }
        return;
      }

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

      // Create corresponding emergency contact
      await _createEmergencyContact(
        groupId: groupId,
        groupMemberId: result['id'],
        userData: user,
        relationship: relationship.trim(),
      );

      setState(() {
        _groupMembers[groupId]?.add(result);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding member: $e')),
        );
      }
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

  // MODIFIED: Delete group and all related emergency contacts
  Future<void> _deleteGroup(String groupId) async {
    try {
      // Delete all emergency contacts for this group
      await supabase
          .from('emergency_contacts')
          .delete()
          .eq('group_id', groupId);

      // Delete group (this will cascade delete group members due to foreign key)
      await supabase.from('group').delete().eq('id', groupId);

      setState(() {
        _groups.removeWhere((group) => group['id'] == groupId);
        _groupMembers.remove(groupId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Group and all emergency contacts deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting group: $e')),
        );
      }
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
                          decoration: const InputDecoration(
                            labelText: 'New Group Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _createGroup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF73D5C),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Create'),
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
                        child: ExpansionTile(
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
                                onPressed: () => _deleteGroup(group['id']),
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
                                label: const Text('Add Emergency Contact'),
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
                                    '${user['first_name']} ${user['last_name']}'),
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
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  // MODIFIED: Add member dialog with relationship input
  Future<void> _showAddMemberDialog(String groupId) async {
    _emailSearchController.clear();
    _relationshipController.clear();
    _searchResults.clear();
    _isSearching = false;
    Map<String, dynamic>? selectedUser;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) => AlertDialog(
          title: const Text('Add Emergency Contact'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Email search field
                TextField(
                  controller: _emailSearchController,
                  decoration: const InputDecoration(
                    labelText: 'Search by email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  onChanged: (value) {
                    dialogSetState(() {
                      selectedUser = null;
                    });
                    _onSearchChanged(value, dialogSetState);
                  },
                ),

                const SizedBox(height: 16),

                // Relationship field
                TextField(
                  controller: _relationshipController,
                  decoration: const InputDecoration(
                    labelText: 'Relationship (e.g., Mother, Brother, Friend)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.family_restroom),
                    hintText: 'Enter relationship to this person',
                  ),
                ),

                const SizedBox(height: 16),

                // Add button
                if (selectedUser != null &&
                    _relationshipController.text.isNotEmpty)
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
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Add Emergency Contact'),
                    ),
                  ),

                const SizedBox(height: 16),

                // Search results
                if (_isSearching)
                  const Center(child: CircularProgressIndicator())
                else if (_searchResults.isNotEmpty)
                  Flexible(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      margin: const EdgeInsets.only(top: 8),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
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
                              ),
                            ),
                            title: Text(
                              '${user['first_name']} ${user['last_name']}',
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              user['email'],
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFFF73D5C)
                                    : Colors.grey,
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
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
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
