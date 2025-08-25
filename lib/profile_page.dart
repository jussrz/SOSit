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

  // User info controllers
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // Emergency contacts
  List<Map<String, dynamic>> _emergencyContacts = [];

  bool _isLoading = false;

  final List<String> relationshipOptions = [
    'Mother',
    'Father',
    'Sibling',
    'Aunt',
    'Uncle',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Load user info
      final userData = await supabase.from('user').select().eq('id', userId).single();
      if (userData != null) {
        final first = userData['first_name'] ?? '';
        final middle = userData['middle_name'] ?? '';
        final last = userData['last_name'] ?? '';
        _fullNameController.text =
            [first, middle, last].where((s) => s.isNotEmpty).join(' ');
        _dobController.text = userData['birthdate'] ?? '';
        _emailController.text = userData['email'] ?? supabase.auth.currentUser?.email ?? '';
        _phoneController.text = userData['phone'] ?? '';
      }

      // Load emergency contacts
      final contacts = await supabase.from('emergency_contacts').select().eq('user_id', userId);
      setState(() {
        _emergencyContacts = contacts.map<Map<String, dynamic>>((c) => {
              'id': c['id'],
              'name': c['emergency_contact_name'] ?? '',
              'phone': c['emergency_contact_phone'] ?? '',
              'relationship': c['emergency_contact_relationship'] ?? '',
            }).toList();
      });
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load profile: $e')),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      // Update phone in user table
      await supabase.from('user').update({'phone': _phoneController.text.trim()}).eq('id', userId);

      // Save emergency contacts
      for (var contact in _emergencyContacts) {
        if (contact['id'] != null) {
          await supabase.from('emergency_contacts').update({
            'emergency_contact_name': contact['name'],
            'emergency_contact_phone': contact['phone'],
            'emergency_contact_relationship': contact['relationship'],
          }).eq('id', contact['id']);
        } else {
          if (contact['name'].isNotEmpty &&
              contact['phone'].isNotEmpty &&
              contact['relationship'].isNotEmpty) {
            await supabase.from('emergency_contacts').insert({
              'user_id': userId,
              'emergency_contact_name': contact['name'],
              'emergency_contact_phone': contact['phone'],
              'emergency_contact_relationship': contact['relationship'],
            });
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
      );

      _loadUserProfile();
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addEmergencyContact() {
    setState(() {
      _emergencyContacts.add({'id': null, 'name': '', 'phone': '', 'relationship': ''});
    });
  }

  void _removeEmergencyContact(int index) {
    setState(() {
      _emergencyContacts.removeAt(index);
    });
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _dobController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // User info
              _buildTextField('Full Name', _fullNameController, readOnly: true),
              _buildTextField('Date of Birth', _dobController, readOnly: true),
              _buildTextField('Email', _emailController, readOnly: true),
              _buildTextField('Phone Number', _phoneController),
              const SizedBox(height: 20),
              const Text('Emergency Contacts', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ..._emergencyContacts.asMap().entries.map((entry) {
                int index = entry.key;
                var contact = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        _buildTextField('Name', TextEditingController(text: contact['name']),
                            onChanged: (val) => contact['name'] = val),
                        const SizedBox(height: 8),
                        _buildDropdownField('Relationship', contact['relationship'],
                            (val) => contact['relationship'] = val),
                        const SizedBox(height: 8),
                        _buildTextField('Phone', TextEditingController(text: contact['phone']),
                            onChanged: (val) => contact['phone'] = val),
                        TextButton(
                          onPressed: () => _removeEmergencyContact(index),
                          child: const Text('Remove', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              TextButton(onPressed: _addEmergencyContact, child: const Text('Add Emergency Contact')),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {bool readOnly = false, Function(String)? onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildDropdownField(String label, String value, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      value: value.isNotEmpty ? value : null,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: relationshipOptions.map((rel) => DropdownMenuItem(value: rel, child: Text(rel))).toList(),
      onChanged: onChanged,
    );
  }
}
