import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();

  // Personal details
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _birthdateController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // Emergency contacts
  final TextEditingController _emergencyNameController = TextEditingController();
  final TextEditingController _emergencyPhoneController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();
  final TextEditingController _emergencyName2Controller = TextEditingController();
  final TextEditingController _emergencyPhone2Controller = TextEditingController();
  final TextEditingController _relationship2Controller = TextEditingController();

  // Role-specific data
  String? _role;
  Map<String, dynamic>? _policeData;
  Map<String, dynamic>? _tanodData;

  bool _isLoading = false;
  bool _showSecondContact = false;
  bool _hasSecondContact = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      // Fetch user info
      final userData =
          await supabase.from('user').select().eq('id', userId).single();

      // Save role
      _role = userData['role'];

      // Fill personal info
      _firstNameController.text = userData['first_name'] ?? '';
      _middleNameController.text = userData['middle_name'] ?? '';
      _lastNameController.text = userData['last_name'] ?? '';
      _birthdateController.text = userData['birthdate'] ?? '';
      _phoneController.text = userData['phone'] ?? '';
      _emailController.text = userData['email'] ?? '';

      // Fetch emergency contacts
      final emergencyData = await supabase
          .from('emergency_contacts')
          .select()
          .eq('user_id', userId)
          .order('created_at');

      if (emergencyData.isNotEmpty) {
        _emergencyNameController.text =
            emergencyData[0]['emergency_contact_name'] ?? '';
        _emergencyPhoneController.text =
            emergencyData[0]['emergency_contact_phone'] ?? '';
        _relationshipController.text =
            emergencyData[0]['emergency_contact_relationship'] ?? '';
      }

      if (emergencyData.length > 1) {
        _emergencyName2Controller.text =
            emergencyData[1]['emergency_contact_name'] ?? '';
        _emergencyPhone2Controller.text =
            emergencyData[1]['emergency_contact_phone'] ?? '';
        _relationship2Controller.text =
            emergencyData[1]['emergency_contact_relationship'] ?? '';
        _hasSecondContact = true;
        _showSecondContact = true;
      }

      // If Police → load police table
      if (_role == 'police') {
        final policeData = await supabase
            .from('police')
            .select()
            .eq('user_id', userId)
            .maybeSingle();
        _policeData = policeData;
      }

      // If Tanod → load tanod table
      if (_role == 'tanod') {
        final tanodData = await supabase
            .from('tanod')
            .select()
            .eq('user_id', userId)
            .maybeSingle();
        _tanodData = tanodData;
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String fullName =
        "${_firstNameController.text} ${_middleNameController.text} ${_lastNameController.text}"
            .trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Full Name: $fullName"),
                  Text("Birthdate: ${_birthdateController.text}"),
                  Text("Phone: ${_phoneController.text}"),
                  Text("Email: ${_emailController.text}"),
                  Text("Role: ${_role ?? ''}"),
                  const Divider(height: 30),

                  // Role-specific info
                  if (_role == 'police' && _policeData != null) ...[
                    const Text("Police Information",
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text("Station: ${_policeData?['station_name'] ?? ''}"),
                    Text("Station ID: ${_policeData?['station_id'] ?? ''}"),
                    Text("Status: ${_policeData?['status'] ?? ''}"),
                    const Divider(height: 30),
                  ],
                  if (_role == 'tanod' && _tanodData != null) ...[
                    const Text("Tanod Information",
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text("ID Number: ${_tanodData?['id_number'] ?? ''}"),
                    Text("Status: ${_tanodData?['status'] ?? ''}"),
                    const Divider(height: 30),
                  ],

                  // Emergency contacts
                  const Text("Emergency Contact 1",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("Name: ${_emergencyNameController.text}"),
                  Text("Phone: ${_emergencyPhoneController.text}"),
                  Text("Relationship: ${_relationshipController.text}"),
                  if (_showSecondContact) ...[
                    const Divider(),
                    const Text("Emergency Contact 2",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text("Name: ${_emergencyName2Controller.text}"),
                    Text("Phone: ${_emergencyPhone2Controller.text}"),
                    Text("Relationship: ${_relationship2Controller.text}"),
                  ],
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _birthdateController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _relationshipController.dispose();
    _emergencyName2Controller.dispose();
    _emergencyPhone2Controller.dispose();
    _relationship2Controller.dispose();
    super.dispose();
  }
}
