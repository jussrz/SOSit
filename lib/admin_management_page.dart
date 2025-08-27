import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_signup_page.dart';

class AdminManagementPage extends StatefulWidget {
  const AdminManagementPage({super.key});

  @override
  State<AdminManagementPage> createState() => _AdminManagementPageState();
}

class _AdminManagementPageState extends State<AdminManagementPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> admins = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  Future<void> _loadAdmins() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('admin')
          .select('id, admin_firstname, admin_lastname, admin_email, created_at')
          .order('created_at', ascending: false);
      
      setState(() {
        admins = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading admins: $e')),
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text('Admin Management', style: TextStyle(
          color: Colors.black, 
          fontWeight: FontWeight.w500
        )),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: const Color(0xFFF73D5C)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminSignupPage()),
              ).then((_) => _loadAdmins());
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAdmins,
              child: ListView.builder(
                padding: EdgeInsets.all(screenWidth * 0.04),
                itemCount: admins.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // Header with "Add New Admin" button
                    return Container(
                      margin: EdgeInsets.only(bottom: screenHeight * 0.02),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF73D5C),
                          padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AdminSignupPage()),
                          ).then((_) => _loadAdmins());
                        },
                        icon: Icon(Icons.add, color: Colors.white),
                        label: Text(
                          'Create New Admin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: screenWidth * 0.04,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }

                  final admin = admins[index - 1];
                  final isCurrentUser = admin['id'] == supabase.auth.currentUser?.id;

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
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFF73D5C),
                        child: Icon(Icons.admin_panel_settings, color: Colors.white),
                      ),
                      title: Text(
                        '${admin['admin_firstname']} ${admin['admin_lastname']}',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: screenWidth * 0.04,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            admin['admin_email'],
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: screenWidth * 0.035,
                            ),
                          ),
                          if (isCurrentUser)
                            Text(
                              '(You)',
                              style: TextStyle(
                                color: const Color(0xFFF73D5C),
                                fontSize: screenWidth * 0.03,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                      trailing: Text(
                        _formatDate(admin['created_at']),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: screenWidth * 0.03,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFF73D5C),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminSignupPage()),
          ).then((_) => _loadAdmins());
        },
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }
}
