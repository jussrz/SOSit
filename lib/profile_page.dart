import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'login_page.dart'; // Add this import

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _userPhoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _emergencyNameController =
      TextEditingController();
  final TextEditingController _emergencyPhoneController =
      TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();

  String _profilePhotoUrl = '';
  File? _newProfilePhoto;

  final List<Map<String, TextEditingController>> _emergencyContacts = [];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    final userId = user?.id;
    if (userId == null) return;

    try {
      // First, try to get the profile data
      final data =
          await supabase.from('profiles').select('*').eq('id', userId).single();

      setState(() {
        _fullNameController.text = data['full_name'] ?? '';
        _dobController.text = data['birthdate'] ?? '';
        _userPhoneController.text = data['phone'] ?? '';
        _emailController.text = user?.email ?? data['email'] ?? '';
        _profilePhotoUrl = data['photo_path'] ?? '';
        _emergencyNameController.text = data['emergency_contact_name'] ?? '';
        _emergencyPhoneController.text = data['emergency_phone'] ?? '';
        _relationshipController.text = data['relationship'] ?? '';

        // Clear existing emergency contacts
        _emergencyContacts.clear();

        // Add emergency contact 2 if it exists
        if (data['emergency_contact_name2'] != null ||
            data['emergency_phone2'] != null ||
            data['relationship2'] != null) {
          _emergencyContacts.add({
            'name': TextEditingController(
                text: data['emergency_contact_name2'] ?? ''),
            'phone':
                TextEditingController(text: data['emergency_phone2'] ?? ''),
            'relationship':
                TextEditingController(text: data['relationship2'] ?? ''),
          });
        }
      });
    } catch (e) {
      // If no profile exists, create initial profile with email
      if (user?.email != null) {
        try {
          await supabase.from('profiles').upsert({
            'id': userId,
            'email': user!.email,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
          // Reload the profile after creating it
          await _loadUserProfile();
        } catch (createError) {
          debugPrint('Error creating profile: $createError');
        }
      } else {
        debugPrint('Error loading profile: $e');
      }
    }
  }

  Future<void> _pickProfilePhoto() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() {
        _newProfilePhoto = File(picked.path);
      });
    }
  }

  Future<String?> _uploadProfilePhoto(File file) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;
      final fileExt = file.path.split('.').last;
      final fileName = '$userId.$fileExt';
      final bytes = await file.readAsBytes();
      await supabase.storage.from('profile-photo').uploadBinary(
            fileName,
            bytes,
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      return supabase.storage.from('profile-photo').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      return null;
    }
  }

  void _addNewEmergencyContact() {
    if (_emergencyContacts.isEmpty) {
      setState(() {
        _emergencyContacts.add({
          'name': TextEditingController(),
          'phone': TextEditingController(),
          'relationship': TextEditingController(),
        });
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Use _profilePhotoUrl directly
      if (_newProfilePhoto != null) {
        final uploadedUrl = await _uploadProfilePhoto(_newProfilePhoto!);
        if (uploadedUrl != null) {
          _profilePhotoUrl = uploadedUrl;
        }
      }

      // Save main profile data
      final profileData = {
        'id': userId,
        'full_name': _fullNameController.text.trim(),
        'birthdate': _dobController.text,
        'phone': _userPhoneController.text.trim(),
        'email':
            supabase.auth.currentUser?.email ?? _emailController.text.trim(),
        'photo_path': _profilePhotoUrl,
        'emergency_contact_name': _emergencyNameController.text.trim(),
        'emergency_phone': _emergencyPhoneController.text.trim(),
        'relationship': _relationshipController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      await supabase.from('profiles').upsert(profileData);

      // Save emergency contact 2 data if it exists
      if (_emergencyContacts.isNotEmpty) {
        final additional = _emergencyContacts[0];
        await supabase.from('profiles').update({
          'emergency_contact_name2': additional['name']!.text.trim(),
          'emergency_phone2': additional['phone']!.text.trim(),
          'relationship2': additional['relationship']!.text.trim(),
        }).eq('id', userId);
      }

      await _loadUserProfile();
      if (mounted) {
        setState(() {
          _newProfilePhoto = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully!')),
        );
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text('User Information',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w500)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: _newProfilePhoto != null
                          ? FileImage(_newProfilePhoto!)
                          : (_profilePhotoUrl.isNotEmpty
                              ? NetworkImage(_profilePhotoUrl)
                              : null) as ImageProvider<Object>?,
                      child:
                          (_newProfilePhoto == null && _profilePhotoUrl.isEmpty)
                              ? const Icon(Icons.person,
                                  size: 56, color: Colors.grey)
                              : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 4,
                      child: GestureDetector(
                        onTap: _pickProfilePhoto,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black12, blurRadius: 4)
                            ],
                          ),
                          child: const Icon(Icons.edit,
                              color: Colors.blueAccent, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text('Personal Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),

              _buildTextField(_fullNameController, 'Full Name'),
              _buildDateField(),
              _buildTextField(_userPhoneController, 'Phone Number',
                  keyboardType: TextInputType.phone),
              _buildTextField(_emailController, 'Email Address',
                  readOnly: true),

              Divider(height: 32, thickness: 1.2, color: Colors.grey[200]),
              const Text('Emergency Contacts',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),

              _buildEmergencyContactCard({
                'name': _emergencyNameController,
                'phone': _emergencyPhoneController,
                'relationship': _relationshipController,
              }),

              ..._emergencyContacts.map((contact) =>
                  _buildEmergencyContactCard(contact, removable: true)),

              if (_emergencyContacts.isEmpty)
                SizedBox(
                  width: MediaQuery.of(context).size.width *
                      0.5, // Make button 80% of screen width
                  child: OutlinedButton.icon(
                    onPressed: _addNewEmergencyContact,
                    icon: const Icon(Icons.add, color: Color(0xFFF73D5C)),
                    label: const Text('Add Emergency Contact',
                        style: TextStyle(
                            color: Color(0xFFF73D5C),
                            fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFFF73D5C)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32))),
                  ),
                ),

              const SizedBox(height: 16),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF73D5C),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Sign Out button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    try {
                      await supabase.auth.signOut();
                      if (context.mounted) {
                        // Replace entire navigation stack with login page
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                          (route) => false,
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error signing out: $e')),
                        );
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Color(0xFFF73D5C)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  child: const Text(
                    'Sign Out',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFFF73D5C),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label,
      {bool readOnly = false,
      TextInputType keyboardType = TextInputType.text}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(12)),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        decoration: InputDecoration(
            labelText: label,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(12)),
        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      ),
    );
  }

  Widget _buildDateField() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(12)),
      child: TextFormField(
        controller: _dobController,
        readOnly: true,
        decoration: const InputDecoration(
            labelText: 'Date of Birth',
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(12)),
        onTap: () async {
          DateTime? picked = await showDatePicker(
              context: context,
              initialDate:
                  DateTime.tryParse(_dobController.text) ?? DateTime(2000),
              firstDate: DateTime(1900),
              lastDate: DateTime.now());
          if (picked != null) {
            _dobController.text =
                "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
          }
        },
      ),
    );
  }

  Widget _buildEmergencyContactCard(Map<String, TextEditingController> contact,
      {bool removable = false}) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (removable)
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      setState(() => _emergencyContacts.remove(contact))),
            ),
          _buildEmergencyContactFields(contact),
        ],
      ),
    );
  }

  Widget _buildEmergencyContactFields(
      Map<String, TextEditingController> contact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField(contact['name']!, 'Emergency Contact Name'),
        const SizedBox(height: 12),
        _buildTextField(
          contact['phone']!,
          "Emergency Contact's Phone Number",
          keyboardType: TextInputType.phone,
        ),
      ],
    );
  }
}
