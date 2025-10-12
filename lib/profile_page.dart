import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

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
    try {
      final picker = ImagePicker();
      
      // Show options to pick from gallery or camera
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Select Photo Source'),
            content: const Text('Choose where to get your profile photo from:'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(ImageSource.camera),
                child: const Text('Camera'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
                child: const Text('Gallery'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );

      if (source != null) {
        final picked = await picker.pickImage(
          source: source, 
          imageQuality: 80,
          maxWidth: 800,
          maxHeight: 800,
        );
        
        if (picked != null) {
          setState(() {
            _newProfilePhoto = File(picked.path);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadProfilePhoto(File file) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final fileExt = file.path.split('.').last;
    final filePath =
        '$userId/profile_photo.${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final bytes = await file.readAsBytes();
    final res = await supabase.storage.from('profile-photo').uploadBinary(
        filePath, bytes,
        fileOptions: const FileOptions(upsert: true));
    if (res.isEmpty) return null;
    final url = supabase.storage.from('profile-photo').getPublicUrl(filePath);
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
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Colors.black, size: screenWidth * 0.06),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          'User Profile',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: screenWidth * 0.045,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(screenWidth * 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: screenHeight * 0.01),

              // Main content card
              Container(
                padding: EdgeInsets.all(screenWidth * 0.06),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
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
                              width: screenWidth * 0.22,
                              height: screenWidth * 0.22,
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
                              child: (_newProfilePhoto == null && _profilePhotoUrl.isEmpty)
                                  ? Icon(Icons.person,
                                      size: screenWidth * 0.1, color: Colors.grey[600])
                                  : null,
                            ),
                            Positioned(
                              bottom: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: _pickProfilePhoto,
                                child: Container(
                                  width: screenWidth * 0.08,
                                  height: screenWidth * 0.08,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF73D5C),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: Icon(Icons.edit,
                                      color: Colors.white, size: screenWidth * 0.04),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.04),

                      // Personal Details Section
                      Text(
                        'Personal Details',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: screenWidth * 0.045,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.025),

                      _buildTextField('First Name', _firstNameController, screenWidth, screenHeight),
                      SizedBox(height: screenHeight * 0.02),
                      _buildTextField('Middle Name', _middleNameController, screenWidth, screenHeight),
                      SizedBox(height: screenHeight * 0.02),
                      _buildTextField('Last Name', _lastNameController, screenWidth, screenHeight),
                      SizedBox(height: screenHeight * 0.02),
                      _buildTextField('Date of Birth', _birthdateController, screenWidth, screenHeight,
                          readOnly: true, 
                          icon: Icons.calendar_today,
                          onTap: () async {
                        DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: _birthdateController.text.isNotEmpty
                              ? DateTime.tryParse(_birthdateController.text) ??
                                  DateTime(2000, 1, 1)
                              : DateTime(2000, 1, 1),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.light(
                                  primary: const Color(0xFFF73D5C),
                                  onPrimary: Colors.white,
                                  onSurface: Colors.black,
                                ),
                                textButtonTheme: TextButtonThemeData(
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFFF73D5C),
                                  ),
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          _birthdateController.text =
                              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                        }
                      }),
                      SizedBox(height: screenHeight * 0.02),
                      _buildTextField('Phone Number', _userPhoneController, screenWidth, screenHeight,
                          keyboardType: TextInputType.phone, icon: Icons.phone),
                      SizedBox(height: screenHeight * 0.02),
                      _buildTextField('Email Address', _emailController, screenWidth, screenHeight,
                          readOnly: true, icon: Icons.email),

                      SizedBox(height: screenHeight * 0.04),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: screenHeight * 0.06,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF73D5C),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 2,
                          ),
                          onPressed: _isLoading ? null : _saveProfile,
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(
                                  'Save Profile',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: screenWidth * 0.045,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
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
    TextEditingController controller,
    double screenWidth,
    double screenHeight, {
    bool readOnly = false,
    VoidCallback? onTap,
    TextInputType? keyboardType,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: screenWidth * 0.04,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: screenHeight * 0.01),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
            color: readOnly ? Colors.grey.shade100 : Colors.grey.shade50,
          ),
          child: TextFormField(
            controller: controller,
            readOnly: readOnly,
            onTap: onTap,
            keyboardType: keyboardType,
            cursorColor: const Color(0xFFF73D5C),
            decoration: InputDecoration(
              prefixIcon: icon != null 
                  ? Icon(icon, color: const Color(0xFFF73D5C).withValues(alpha: 0.7))
                  : null,
              hintText: 'Enter $label',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: icon != null ? screenWidth * 0.02 : screenWidth * 0.04,
                vertical: screenHeight * 0.020,
              ),
            ),
            style: TextStyle(
              fontSize: screenWidth * 0.04,
              color: readOnly ? Colors.grey.shade600 : Colors.black,
            ),
          ),
        ),
      ],
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