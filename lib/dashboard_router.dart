import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'emergency_contact_dashboard.dart';

class DashboardRouter {
  static final supabase = Supabase.instance.client;

  /// Determines which dashboard to show based on user's role and emergency contact status
  static Future<Widget> getAppropriateScreen() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      final userEmail = supabase.auth.currentUser?.email;

      debugPrint('=== DASHBOARD ROUTER DEBUG ===');
      debugPrint('User ID: $userId');
      debugPrint('User Email: $userEmail');

      if (userId == null || userEmail == null) {
        debugPrint('User not authenticated, showing HomeScreen');
        return const HomeScreen();
      }

      // Get current user's contact info
      final userData = await supabase
          .from('user')
          .select('phone, email, first_name, last_name')
          .eq('id', userId)
          .single();

      final currentUserEmail = userData['email'];
      final userName = '${userData['first_name']} ${userData['last_name']}';

      debugPrint('User Email from DB: $currentUserEmail');
      debugPrint('User Name: $userName');

      // Check if current user is listed as someone else's emergency contact
      // Method 1: Check if current user's email matches any added_by field
      // This means someone added an emergency contact and the current user was the one who added it
      List<dynamic> emergencyContactMatches = [];

      if (currentUserEmail != null && currentUserEmail.isNotEmpty) {
        debugPrint(
            'Checking if user was added_by someone as emergency contact...');

        // Look for emergency contacts where added_by references current user's email
        final addedByMatches =
            await supabase.from('emergency_contacts').select('''
              id, 
              user_id, 
              emergency_contact_name, 
              emergency_contact_phone,
              added_by,
              added_by_user:user!emergency_contacts_added_by_fkey(email, first_name, last_name)
            ''').eq('added_by', userId);

        debugPrint(
            'Found ${addedByMatches.length} emergency contacts added by current user');
        // Note: These are contacts the current user added for others, not where they are the emergency contact

        // Instead, we need to find where someone else added the current user as their emergency contact
        // This would be where the emergency_contact_phone matches current user's phone
        // OR emergency_contact_name matches current user's name

        final userPhone = userData['phone'];

        // Check by phone number match
        if (userPhone != null && userPhone.isNotEmpty) {
          final phoneMatches = await supabase
              .from('emergency_contacts')
              .select(
                  'id, user_id, emergency_contact_name, emergency_contact_phone, added_by')
              .eq('emergency_contact_phone', userPhone)
              .neq('user_id',
                  userId); // Don't match their own emergency contacts

          debugPrint('Phone matches found: ${phoneMatches.length}');
          for (var match in phoneMatches) {
            debugPrint(
                '  - Match: ${match['emergency_contact_name']} (${match['emergency_contact_phone']}) for user_id: ${match['user_id']}');
          }

          emergencyContactMatches.addAll(phoneMatches);
        }

        // Check by name if no phone matches
        if (emergencyContactMatches.isEmpty) {
          final nameMatches = await supabase
              .from('emergency_contacts')
              .select(
                  'id, user_id, emergency_contact_name, emergency_contact_phone, added_by')
              .ilike('emergency_contact_name', '%$userName%')
              .neq('user_id', userId);

          debugPrint('Name matches found: ${nameMatches.length}');
          for (var match in nameMatches) {
            debugPrint(
                '  - Match: ${match['emergency_contact_name']} for user_id: ${match['user_id']}');
          }

          emergencyContactMatches.addAll(nameMatches);
        }
      } else {
        debugPrint('User email is null or empty, skipping email check');
      }

      // Check if user is a member of groups (added by others as emergency contact)
      debugPrint('Checking group memberships for user: $userId');
      final groupMemberExists = await supabase
          .from('group_members')
          .select('id, group_id, relationship')
          .eq('user_id', userId);

      debugPrint('Group memberships found: ${groupMemberExists.length}');
      for (var membership in groupMemberExists) {
        debugPrint(
            '  - Group membership: ${membership['id']} in group ${membership['group_id']}, relationship: ${membership['relationship']}');
      }

      // If user is listed as emergency contact for others OR is a group member,
      // show emergency contact dashboard
      if (emergencyContactMatches.isNotEmpty || groupMemberExists.isNotEmpty) {
        debugPrint('*** ROUTING TO EMERGENCY CONTACT DASHBOARD ***');
        debugPrint(
            'Emergency contact matches: ${emergencyContactMatches.length}');
        debugPrint('Group memberships: ${groupMemberExists.length}');
        return const EmergencyContactDashboard();
      }

      // Default: show regular home screen
      debugPrint('*** ROUTING TO HOME SCREEN (default) ***');
      return const HomeScreen();
    } catch (e) {
      debugPrint('Error determining dashboard: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      // On error, fallback to home screen
      return const HomeScreen();
    }
  }

  /// Check if user should see emergency contact dashboard
  static Future<bool> isEmergencyContact() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return false;

      // Get current user's contact info
      final userData = await supabase
          .from('user')
          .select('phone, email, first_name, last_name')
          .eq('id', userId)
          .single();

      final userPhone = userData['phone'];
      final userName = '${userData['first_name']} ${userData['last_name']}';

      // Check if current user is listed as someone else's emergency contact by phone
      if (userPhone != null && userPhone.isNotEmpty) {
        final phoneMatches = await supabase
            .from('emergency_contacts')
            .select('id')
            .eq('emergency_contact_phone', userPhone)
            .neq('user_id', userId)
            .limit(1);

        if (phoneMatches.isNotEmpty) return true;
      }

      // Check by name
      final nameMatches = await supabase
          .from('emergency_contacts')
          .select('id')
          .ilike('emergency_contact_name', '%$userName%')
          .neq('user_id', userId)
          .limit(1);

      if (nameMatches.isNotEmpty) return true;

      // Check if user is a member of any group (was added by someone else)
      final groupMemberExists = await supabase
          .from('group_members')
          .select('id')
          .eq('user_id', userId)
          .limit(1);

      return groupMemberExists.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking emergency contact status: $e');
      return false;
    }
  }

  /// Get emergency contact related data for the dashboard
  static Future<Map<String, dynamic>> getEmergencyContactData() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return {};

      // Get current user's contact info to find where they're listed as emergency contact
      final userData = await supabase
          .from('user')
          .select('phone, email, first_name, last_name')
          .eq('id', userId)
          .single();

      final userPhone = userData['phone'];
      final userName = '${userData['first_name']} ${userData['last_name']}';

      // Get groups where this user is a member
      final groupMemberships = await supabase.from('group_members').select('''
            id,
            relationship,
            created_at,
            group_id,
            group:group(
              id,
              name,
              created_by,
              created_at,
              creator:user!group_created_by_fkey(
                first_name,
                last_name,
                email,
                phone
              )
            )
          ''').eq('user_id', userId);

      // Get emergency contacts where this user is listed as the emergency contact
      List<dynamic> emergencyContacts = [];

      if (userPhone != null && userPhone.isNotEmpty) {
        final phoneContacts =
            await supabase.from('emergency_contacts').select('''
            id,
            emergency_contact_name,
            emergency_contact_relationship,
            emergency_contact_phone,
            user_id,
            created_at,
            added_by,
            user:user!emergency_contacts_user_id_fkey(
              first_name,
              last_name,
              email,
              phone
            ),
            added_by_user:user!emergency_contacts_added_by_fkey(
              first_name,
              last_name,
              email
            )
          ''').eq('emergency_contact_phone', userPhone).neq('user_id', userId);

        emergencyContacts.addAll(phoneContacts);
      }

      // Also check by name
      final nameContacts = await supabase
          .from('emergency_contacts')
          .select('''
          id,
          emergency_contact_name,
          emergency_contact_relationship,
          emergency_contact_phone,
          user_id,
          created_at,
          added_by,
          user:user!emergency_contacts_user_id_fkey(
            first_name,
            last_name,
            email,
            phone
          ),
          added_by_user:user!emergency_contacts_added_by_fkey(
            first_name,
            last_name,
            email
          )
        ''')
          .ilike('emergency_contact_name', '%$userName%')
          .neq('user_id', userId);

      emergencyContacts.addAll(nameContacts);

      return {
        'group_memberships': groupMemberships,
        'emergency_contacts': emergencyContacts,
        'is_emergency_contact':
            groupMemberships.isNotEmpty || emergencyContacts.isNotEmpty,
      };
    } catch (e) {
      debugPrint('Error getting emergency contact data: $e');
      return {
        'group_memberships': [],
        'emergency_contacts': [],
        'is_emergency_contact': false,
      };
    }
  }
}
