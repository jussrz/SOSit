import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

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
      debugPrint('Loaded profile: $data');

      setState(() {
        _fullNameController.text = data['full_name'] ?? '';
        _dobController.text = data['birthdate'] ?? '';
        _userPhoneController.text = data['phone'] ?? ''; // Changed from user_phone to phone
        _emailController.text = data['email'] ?? supabase.auth.currentUser?.email ?? '';
        _profilePhotoUrl = data['photo_path'] ?? '';
        _emergencyNameController.text = data['emergency_contact_name'] ?? '';
        _emergencyPhoneController.text = data['emergency_phone'] ?? '';
        _relationshipController.text = data['relationship'] ?? '';
      });
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _pickProfilePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() {
        _newProfilePhoto = File(picked.path);
        _isEditingPhoto = true;
      });
    }
  }

  Future<String?> _uploadProfilePhoto(File file) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Simplify file path
      final fileExt = file.path.split('.').last;
      final fileName = '$userId.$fileExt';
      
      debugPrint('Starting photo upload...');
      final bytes = await file.readAsBytes();
      
      // Upload to storage
      final result = await supabase.storage
          .from('profile-photo')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      
      debugPrint('Upload result: $result');

      // Get public URL
      final publicUrl = supabase.storage
          .from('profile-photo')
          .getPublicUrl(fileName);
      
      debugPrint('Generated public URL: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      return null;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      debugPrint('Starting profile save...');
      
      // Handle photo first if there's a new one
      String? photoUrl = _profilePhotoUrl;
      if (_newProfilePhoto != null) {
        photoUrl = await _uploadProfilePhoto(_newProfilePhoto!);
        debugPrint('Uploaded photo URL: $photoUrl');
      }

      final updates = {
        'id': userId,
        'full_name': _fullNameController.text.trim(),
        'birthdate': _dobController.text,
        'phone': _userPhoneController.text.trim(),
        'email': _emailController.text.trim(),
        'photo_path': photoUrl,
        'emergency_contact_name': _emergencyNameController.text.trim(),
        'emergency_phone': _emergencyPhoneController.text.trim(),
        'relationship': _relationshipController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      debugPrint('Saving profile with data: $updates');

      // First check if profile exists
      final existing = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (existing == null) {
        // Insert new profile
        debugPrint('Creating new profile...');
        await supabase.from('profiles').insert(updates);
      } else {
        // Update existing profile
        debugPrint('Updating existing profile...');
        await supabase
            .from('profiles')
            .update(updates)
            .eq('id', userId);
      }

      debugPrint('Profile saved successfully');
      
      // Reload profile to verify changes
      await _loadUserProfile();

      if (context.mounted) {
        setState(() {
          if (photoUrl != null) _profilePhotoUrl = photoUrl;
          _newProfilePhoto = null;
          _isEditingPhoto = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully!')),
        );
      }

    } catch (e, stack) {
      debugPrint('Error saving profile: $e');
      debugPrint('Stack trace: $stack');
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
                              : null) as ImageProvider<Object>?, // <-- Cast to ImageProvider<Object>?
                      child: (_newProfilePhoto == null && _profilePhotoUrl.isEmpty)
                          ? const Icon(Icons.person, size: 56, color: Colors.grey)
                          : null,
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
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Please enter your name' : null,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _dobController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Date of Birth',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                  ),
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
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _userPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.isEmpty ? 'Please enter your phone number' : null,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                  ),
                  readOnly: true,
                ),
              ),
              const SizedBox(height: 18),
              Divider(height: 32, thickness: 1.2, color: Colors.grey[200]),
              const Text('Emergency Contact', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _emergencyNameController,
                  decoration: const InputDecoration(
                    labelText: 'Emergency Contact Name',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Please enter a name' : null,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonFormField<String>(
                  value: _relationshipController.text.isNotEmpty ? _relationshipController.text : null,
                  items: const [
                    DropdownMenuItem(value: 'Spouse', child: Text('Spouse')),
                    DropdownMenuItem(value: 'Father', child: Text('Father')),
                    DropdownMenuItem(value: 'Mother', child: Text('Mother')),
                    DropdownMenuItem(value: 'Sibling', child: Text('Sibling')),
                    DropdownMenuItem(value: 'Friend', child: Text('Friend')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _relationshipController.text = val ?? '';
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: "Relationship to User",
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Please select a relationship' : null,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _emergencyPhoneController,
                  decoration: const InputDecoration(
                    labelText: "Emergency Contact's Phone Number",
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.isEmpty ? 'Please enter a phone number' : null,
                ),
              ),
              const SizedBox(height: 24), // <-- Add this line for space before the first button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Add Emergency Contact',
                    style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold,),
                  ),
                ),
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
                    style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold,),
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