import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

// Only import image_picker if available, otherwise instruct user to add it to pubspec.yaml
// import 'package:image_picker/image_picker.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final supabase = Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _userPhoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // Controllers for individual name fields
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _birthdateController = TextEditingController();

  String _profilePhotoUrl = '';
  File? _newProfilePhoto;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('No user ID found');
      return;
    }

    debugPrint('Loading profile for user: $userId');
    setState(() => _isLoading = true);

    try {
      // Load user data from 'user' table
      final userData =
          await supabase.from('user').select().eq('id', userId).single();

      debugPrint('User data from database: $userData');

      setState(() {
        // User basic info
        _firstNameController.text = userData['first_name'] ?? '';
        _middleNameController.text = userData['middle_name'] ?? '';
        _lastNameController.text = userData['last_name'] ?? '';

        // Combine names for full name display
        String fullName = [
          userData['first_name'] ?? '',
          userData['middle_name'] ?? '',
          userData['last_name'] ?? ''
        ].where((name) => name.isNotEmpty).join(' ');
        _fullNameController.text = fullName;

        _birthdateController.text = userData['birthdate'] ?? '';
        _userPhoneController.text = userData['phone'] ?? '';
        _emailController.text =
            userData['email'] ?? supabase.auth.currentUser?.email ?? '';
        _profilePhotoUrl = userData['profile_photo_url'] ?? '';

        _isLoading = false;
      });

      debugPrint('Profile loaded successfully');
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load profile: $e')),
        );
      }
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
    //   });
    // }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Please add image_picker to your pubspec.yaml to pick images.')),
    );
  }

  Future<String?> _uploadProfilePhoto(File file) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final fileExt = file.path.split('.').last;
    final filePath =
        'profile_photos/$userId.${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final bytes = await file.readAsBytes();
    final res = await supabase.storage.from('profile-photos').uploadBinary(
        filePath, bytes,
        fileOptions: const FileOptions(upsert: true));
    if (res.isEmpty) return null;
    final url = supabase.storage.from('profile-photos').getPublicUrl(filePath);
    return url;
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Upload new profile photo if selected
      String? newPhotoUrl;
      if (_newProfilePhoto != null) {
        newPhotoUrl = await _uploadProfilePhoto(_newProfilePhoto!);
        if (newPhotoUrl != null) {
          _profilePhotoUrl = newPhotoUrl;
        }
      }

      // Update user table
      Map<String, dynamic> updateData = {
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'birthdate': _birthdateController.text.trim(),
        'phone': _userPhoneController.text.trim(),
        'email': _emailController.text.trim(),
      };

      // Only include profile photo URL if we have a new one
      if (newPhotoUrl != null) {
        updateData['profile_photo_url'] = newPhotoUrl;
      }

      await supabase.from('user').update(updateData).eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Reload to verify changes
        await _loadUserProfile();
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text('User Profile',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w500)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Photo Section
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        shape: BoxShape.circle,
                        image: _newProfilePhoto != null
                            ? DecorationImage(
                                image: FileImage(_newProfilePhoto!),
                                fit: BoxFit.cover,
                              )
                            : (_profilePhotoUrl.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(_profilePhotoUrl),
                                    fit: BoxFit.cover,
                                  )
                                : null),
                      ),
                      child:
                          (_newProfilePhoto == null && _profilePhotoUrl.isEmpty)
                              ? Icon(Icons.person,
                                  size: 40, color: Colors.grey[600])
                              : null,
                    ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: _pickProfilePhoto,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Personal Details Section
              const Text('Personal Details',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.black)),
              const SizedBox(height: 16),

              _buildTextField('First Name', _firstNameController),
              const SizedBox(height: 12),
              _buildTextField('Middle Name', _middleNameController),
              const SizedBox(height: 12),
              _buildTextField('Last Name', _lastNameController),
              const SizedBox(height: 12),
              _buildTextField('Date of Birth', _birthdateController,
                  readOnly: true, onTap: () async {
                DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: _birthdateController.text.isNotEmpty
                      ? DateTime.tryParse(_birthdateController.text) ??
                          DateTime(2000, 1, 1)
                      : DateTime(2000, 1, 1),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _birthdateController.text =
                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                }
              }),
              const SizedBox(height: 12),
              _buildTextField('Phone Number', _userPhoneController,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _buildTextField('Email Address', _emailController,
                  readOnly: true),

              const SizedBox(height: 32),

              // Save Button
              Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF73D5C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Save',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool readOnly = false,
    VoidCallback? onTap,
    TextInputType? keyboardType,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        keyboardType: keyboardType,
        cursorColor: const Color(0xFFF73D5C),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
        style: TextStyle(
          fontSize: 16,
          color: (readOnly && label == 'Email Address')
              ? Colors.grey.shade500
              : Colors.black,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _userPhoneController.dispose();
    _emailController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _birthdateController.dispose();
    super.dispose();
  }
}