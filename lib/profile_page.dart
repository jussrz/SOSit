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
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String? _selectedRelationship;

  final List<String> _relationships = ['Mother', 'Father', 'Aunt', 'Uncle', 'Sibling'];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      setState(() {
        _nameController.text = data['emergency_contact_name'] ?? '';
        _phoneController.text = data['emergency_phone'] ?? '';
        _selectedRelationship = data['relationship'];
      });
    } catch (e) {
      // Handle missing profile or error silently
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _saveEmergencyContact() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final updates = {
      'id': userId,
      'emergency_contact_name': _nameController.text.trim(),
      'emergency_phone': _phoneController.text.trim(),
      'relationship': _selectedRelationship,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await supabase.from('profiles').upsert(updates);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Emergency contact saved!')),
        );
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving contact: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? 'No email';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header
            Center(
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 50,
                    backgroundImage: AssetImage('assets/default_user.png'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    email,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Emergency Contact Form
            const Text(
              'Emergency Contact',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Emergency Contact Name'),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Please enter a name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone Number'),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Please enter a phone number' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedRelationship,
                    decoration: const InputDecoration(
                      labelText: 'Relationship',
                      border: OutlineInputBorder(),
                    ),
                    items: _relationships.map((String relationship) {
                      return DropdownMenuItem<String>(
                        value: relationship,
                        child: Text(relationship),
                      );
                    }).toList(),
                    validator: (value) =>
                        value == null ? 'Please select a relationship' : null,
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedRelationship = newValue;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveEmergencyContact,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Save Emergency Contact',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Sign Out
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await supabase.auth.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Sign Out',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
