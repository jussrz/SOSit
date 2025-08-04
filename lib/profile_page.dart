

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

// Only import image_picker if available, otherwise instruct user to add it to pubspec.yaml
// import 'package:image_picker/image_picker.dart';



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
  final TextEditingController _emergencyNameController = TextEditingController();
  final TextEditingController _emergencyPhoneController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();

  String _profilePhotoUrl = '';
  File? _newProfilePhoto;
  bool _isEditingPhoto = false;

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
        _fullNameController.text = data['full_name'] ?? '';
        _dobController.text = data['dob'] ?? '';
        _userPhoneController.text = data['user_phone'] ?? '';
        _emailController.text = data['email'] ?? supabase.auth.currentUser?.email ?? '';
        _profilePhotoUrl = data['profile_photo_url'] ?? '';
        _emergencyNameController.text = data['emergency_contact_name'] ?? '';
        _emergencyPhoneController.text = data['emergency_phone'] ?? '';
        _relationshipController.text = data['relationship'] ?? '';
      });
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _pickProfilePhoto() async {
    // You must add image_picker to your pubspec.yaml for this to work:
    // dependencies:
    //   image_picker: ^1.0.0
    // Then run: flutter pub get
    // Uncomment the import at the top after installing.
    //
    // final picker = ImagePicker();
    // final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    // if (picked != null) {
    //   setState(() {
    //     _newProfilePhoto = File(picked.path);
    //     _isEditingPhoto = true;
    //   });
    // }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please add image_picker to your pubspec.yaml to pick images.')),
    );
  }

  Future<String?> _uploadProfilePhoto(File file) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final fileExt = file.path.split('.').last;
    final filePath = 'profile_photos/$userId.${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final bytes = await file.readAsBytes();
    final res = await supabase.storage.from('profile-photos').uploadBinary(filePath, bytes, fileOptions: const FileOptions(upsert: true));
    if (res.isEmpty) return null;
    final url = supabase.storage.from('profile-photos').getPublicUrl(filePath);
    return url;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    String? photoUrl = _profilePhotoUrl;
    if (_newProfilePhoto != null) {
      final uploaded = await _uploadProfilePhoto(_newProfilePhoto!);
      if (uploaded != null) {
        photoUrl = uploaded;
      }
    }
    final updates = {
      'id': userId,
      'full_name': _fullNameController.text.trim(),
      'dob': _dobController.text.trim(),
      'user_phone': _userPhoneController.text.trim(),
      'email': _emailController.text.trim(),
      'profile_photo_url': photoUrl,
      'emergency_contact_name': _emergencyNameController.text.trim(),
      'emergency_phone': _emergencyPhoneController.text.trim(),
      'relationship': _relationshipController.text.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    try {
      await supabase.from('profiles').upsert(updates);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved!')),
        );
        setState(() {
          _isEditingPhoto = false;
          if (photoUrl != null) _profilePhotoUrl = photoUrl;
          _newProfilePhoto = null;
        });
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (context.mounted) {
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
        title: const Text('User Information', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w500)),
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
                              : const AssetImage('assets/default_user.png') as ImageProvider),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 4,
                      child: GestureDetector(
                        onTap: _pickProfilePhoto,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.edit, color: Colors.blueAccent, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text('Personal Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (v) => v == null || v.isEmpty ? 'Please enter your name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dobController,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Date of Birth'),
                onTap: () async {
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _dobController.text.isNotEmpty ? DateTime.tryParse(_dobController.text) ?? DateTime(2000, 1, 1) : DateTime(2000, 1, 1),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    _dobController.text = "${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}";
                  }
                },
                validator: (v) => v == null || v.isEmpty ? 'Please select your date of birth' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _userPhoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.phone,
                validator: (v) => v == null || v.isEmpty ? 'Please enter your phone number' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email Address'),
                readOnly: true,
              ),
              const SizedBox(height: 18),
              Divider(height: 32, thickness: 1.2, color: Colors.grey[200]),
              const Text('Emergency Contact', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emergencyNameController,
                decoration: const InputDecoration(labelText: 'Emergency Contact Name'),
                validator: (v) => v == null || v.isEmpty ? 'Please enter a name' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _relationshipController.text.isNotEmpty ? _relationshipController.text : null,
                items: const [
                  DropdownMenuItem(value: 'Spouse', child: Text('Spouse')),
                  DropdownMenuItem(value: 'Parent', child: Text('Parent')),
                  DropdownMenuItem(value: 'Sibling', child: Text('Sibling')),
                  DropdownMenuItem(value: 'Friend', child: Text('Friend')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (val) {
                  setState(() {
                    _relationshipController.text = val ?? '';
                  });
                },
                decoration: const InputDecoration(labelText: "Relationship to User"),
                validator: (v) => v == null || v.isEmpty ? 'Please select a relationship' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emergencyPhoneController,
                decoration: const InputDecoration(labelText: "Emergency Contact's Phone Number"),
                keyboardType: TextInputType.phone,
                validator: (v) => v == null || v.isEmpty ? 'Please enter a phone number' : null,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveProfile,
                      icon: const Icon(Icons.person_add, color: Colors.white),
                      label: const Text('Add Emergency Contact'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
