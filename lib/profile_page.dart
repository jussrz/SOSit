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

  // Add missing controllers
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _birthdateController = TextEditingController();

  // Second emergency contact controllers
  final TextEditingController _emergencyName2Controller = TextEditingController();
  final TextEditingController _emergencyPhone2Controller = TextEditingController();
  final TextEditingController _relationship2Controller = TextEditingController();

  // Change contact ID tracking back to String?
  String? _firstContactId;
  String? _secondContactId;

  String _profilePhotoUrl = '';
  File? _newProfilePhoto;
  bool _isEditingPhoto = false;
  bool _isLoading = false;
  bool _showSecondContact = false;
  bool _hasSecondContact = false;

  // Add controllers for "Other" text inputs
  final TextEditingController _otherRelationshipController = TextEditingController();
  final TextEditingController _otherRelationship2Controller = TextEditingController();

  // Add state variables to track if "Other" is selected
  bool _isOtherSelected = false;
  bool _isOther2Selected = false;

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
      final userData = await supabase
          .from('user')
          .select()
          .eq('id', userId)
          .single();

      debugPrint('User data from database: $userData');

      // Load emergency contacts from 'emergency_contacts' table
      final emergencyData = await supabase
          .from('emergency_contacts')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true);

      debugPrint('Emergency contacts from database: $emergencyData');

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
        _emailController.text = userData['email'] ?? supabase.auth.currentUser?.email ?? '';
        _profilePhotoUrl = userData['profile_photo_url'] ?? '';

        // Clear previous emergency contact data
        _firstContactId = null;
        _secondContactId = null;
        _emergencyNameController.clear();
        _emergencyPhoneController.clear();
        _relationshipController.clear();
        _emergencyName2Controller.clear();
        _emergencyPhone2Controller.clear();
        _relationship2Controller.clear();
        _hasSecondContact = false;
        _showSecondContact = false;

        // Emergency contacts with ID tracking (String instead of int)
        if (emergencyData.isNotEmpty) {
          // First emergency contact
          _firstContactId = emergencyData[0]['id']?.toString();
          _emergencyNameController.text = emergencyData[0]['emergency_contact_name'] ?? '';
          _emergencyPhoneController.text = emergencyData[0]['emergency_contact_phone'] ?? '';
          
          // Handle "Other:" relationships
          String relationship = emergencyData[0]['emergency_contact_relationship'] ?? '';
          if (relationship.startsWith('Other: ')) {
            _relationshipController.text = 'Other';
            _otherRelationshipController.text = relationship.substring(7); // Remove "Other: " prefix
            _isOtherSelected = true;
          } else {
            _relationshipController.text = relationship;
            _otherRelationshipController.clear();
            _isOtherSelected = false;
          }
        }

        if (emergencyData.length > 1) {
          // Second emergency contact
          _secondContactId = emergencyData[1]['id']?.toString();
          _emergencyName2Controller.text = emergencyData[1]['emergency_contact_name'] ?? '';
          _emergencyPhone2Controller.text = emergencyData[1]['emergency_contact_phone'] ?? '';
          
          // Handle "Other:" relationships
          String relationship2 = emergencyData[1]['emergency_contact_relationship'] ?? '';
          if (relationship2.startsWith('Other: ')) {
            _relationship2Controller.text = 'Other';
            _otherRelationship2Controller.text = relationship2.substring(7); // Remove "Other: " prefix
            _isOther2Selected = true;
          } else {
            _relationship2Controller.text = relationship2;
            _otherRelationship2Controller.clear();
            _isOther2Selected = false;
          }
          _hasSecondContact = true;
          _showSecondContact = true;
        }

        _isLoading = false;
      });

      debugPrint('Profile loaded successfully');
      debugPrint('First contact ID: $_firstContactId');
      debugPrint('Second contact ID: $_secondContactId');
      debugPrint('Emergency contacts loaded: ${emergencyData.length}');

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

  String _normalizeRelationship(String relationship) {
    if (relationship.isNotEmpty) {
      String normalizedRelationship = relationship.toLowerCase();
      switch (normalizedRelationship) {
        case 'spouse':
          return 'Spouse';
        case 'mother':
          return 'Mother';
        case 'father':
          return 'Father';
        case 'parent':
          return 'Mother';
        case 'sibling':
          return 'Sibling';
        case 'friend':
          return 'Friend';
        case 'relative':
        case 'other':
          return 'Relative';
        default:
          if (['Spouse', 'Mother', 'Father', 'Sibling', 'Friend', 'Relative'].contains(relationship)) {
            return relationship;
          } else {
            return 'Relative';
          }
      }
    }
    return '';
  }

  void _addSecondEmergencyContact() {
    setState(() {
      _showSecondContact = true;
      // Clear the fields for new input
      _emergencyName2Controller.clear();
      _emergencyPhone2Controller.clear();
      _relationship2Controller.clear();
    });
  }

  Future<void> _removeFirstEmergencyContact() async {
    final confirmed = await _showRemoveConfirmationDialog('Delete this contact?');
    final userId = supabase.auth.currentUser?.id;
    if (!confirmed || _firstContactId == null || userId == null) return;

    try {
      final deleted = await supabase
          .from('emergency_contacts')
          .delete()
          .eq('id', _firstContactId!)              // uuid OR int, both ok if policy allows
          .eq('user_id', userId)                   // helpful with RLS
          .select();                               // return the deleted rows

      final didDelete = deleted is List && deleted.isNotEmpty;

      if (!didDelete) {
        // Most likely RLS blocked it. Tell the user/dev clearly.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not delete contact (RLS policy likely missing).'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _firstContactId = null;
        _emergencyNameController.clear();
        _emergencyPhoneController.clear();
        _relationshipController.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact deleted.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }

      await _loadUserProfile();
    } catch (e) {
      debugPrint('Error removing first contact: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing contact: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _removeSecondEmergencyContact() async {
    final confirmed = await _showRemoveConfirmationDialog('Delete this contact?');
    final userId = supabase.auth.currentUser?.id;
    if (!confirmed || _secondContactId == null || userId == null) return;

    try {
      final deleted = await supabase
          .from('emergency_contacts')
          .delete()
          .eq('id', _secondContactId!)
          .eq('user_id', userId)
          .select();

      final didDelete = deleted is List && deleted.isNotEmpty;

      if (!didDelete) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not delete contact (RLS policy likely missing).'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _secondContactId = null;
        _emergencyName2Controller.clear();
        _emergencyPhone2Controller.clear();
        _relationship2Controller.clear();
        _showSecondContact = false;
        _hasSecondContact = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact deleted.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }

      await _loadUserProfile();
    } catch (e) {
      debugPrint('Error removing second contact: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing contact: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<bool> _showRemoveConfirmationDialog(String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete contact'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), 
            child: const Text('Cancel')
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red), 
            child: const Text('Delete')
          ),
        ],
      ),
    ) ?? false;
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

  // Helper method to get the final relationship value
  String _getFinalRelationship(String selectedRelationship, String otherText) {
    if (selectedRelationship == 'Other' && otherText.trim().isNotEmpty) {
      return 'Other: ${otherText.trim()}';
    }
    return selectedRelationship;
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Update user table
      await supabase.from('user').update({
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'birthdate': _birthdateController.text.trim(),
        'phone': _userPhoneController.text.trim(),
        'email': _emailController.text.trim(),
      }).eq('id', userId);

      // Handle first emergency contact
      if (_emergencyNameController.text.trim().isNotEmpty &&
          _emergencyPhoneController.text.trim().isNotEmpty &&
          _relationshipController.text.trim().isNotEmpty) {
        
        final contactData = {
          'user_id': userId,
          'emergency_contact_name': _emergencyNameController.text.trim(),
          'emergency_contact_phone': _emergencyPhoneController.text.trim(),
          'emergency_contact_relationship': _getFinalRelationship(_relationshipController.text, _otherRelationshipController.text),
        };

        if (_firstContactId != null) {
          // Update existing contact
          await supabase
              .from('emergency_contacts')
              .update(contactData)
              .eq('id', _firstContactId!);
        } else {
          // Insert new contact and store its ID
          final inserted = await supabase
              .from('emergency_contacts')
              .insert(contactData)
              .select()
              .single();
          _firstContactId = inserted['id']?.toString(); // Convert to String safely
        }
      } else if (_firstContactId != null) {
        // If fields are empty but contact exists, delete it
        await supabase
            .from('emergency_contacts')
            .delete()
            .eq('id', _firstContactId!);
        _firstContactId = null;
      }

      // Handle second emergency contact
      if (_showSecondContact && 
          _emergencyName2Controller.text.trim().isNotEmpty &&
          _emergencyPhone2Controller.text.trim().isNotEmpty &&
          _relationship2Controller.text.trim().isNotEmpty) {
        
        final contactData = {
          'user_id': userId,
          'emergency_contact_name': _emergencyName2Controller.text.trim(),
          'emergency_contact_phone': _emergencyPhone2Controller.text.trim(),
          'emergency_contact_relationship': _getFinalRelationship(_relationship2Controller.text, _otherRelationship2Controller.text),
        };

        if (_secondContactId != null) {
          // Update existing contact
          await supabase
              .from('emergency_contacts')
              .update(contactData)
              .eq('id', _secondContactId!);
        } else {
          // Insert new contact and store its ID
          final inserted = await supabase
              .from('emergency_contacts')
              .insert(contactData)
              .select()
              .single();
          _secondContactId = inserted['id']?.toString(); // Convert to String safely
        }
      } else if (_secondContactId != null) {
        // If fields are empty but contact exists, delete it
        await supabase
            .from('emergency_contacts')
            .delete()
            .eq('id', _secondContactId!);
        _secondContactId = null;
        setState(() {
          _showSecondContact = false;
          _hasSecondContact = false;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Reload to verify changes and get correct IDs
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
        title: const Text('User Information', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w500)),
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
                      child: (_newProfilePhoto == null && _profilePhotoUrl.isEmpty)
                          ? Icon(Icons.person, size: 40, color: Colors.grey[600])
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
                          child: const Icon(Icons.edit, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Personal Details Section
              const Text('Personal Details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black)),
              const SizedBox(height: 16),

              _buildTextField('Full Name', _fullNameController),
              const SizedBox(height: 12),
              _buildTextField('Date of Birth', _birthdateController, readOnly: true, onTap: () async {
                DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: _birthdateController.text.isNotEmpty 
                      ? DateTime.tryParse(_birthdateController.text) ?? DateTime(2000, 1, 1) 
                      : DateTime(2000, 1, 1),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _birthdateController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                }
              }),
              const SizedBox(height: 12),
              _buildTextField('Phone Number', _userPhoneController, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _buildTextField('Email Address', _emailController, readOnly: true),

              const SizedBox(height: 32),

              // Emergency Contact Section
              const Text('Emergency Contacts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black)),
              const SizedBox(height: 16),

              // First Emergency Contact with Remove Button
              Row(
                children: [
                  const Expanded(
                    child: Text('Emergency Contact', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Colors.black87)),
                  ),
                  // Show remove button if contact exists (based on ID, not text)
                  if (_firstContactId != null)
                    TextButton.icon(
                      onPressed: _removeFirstEmergencyContact,
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      label: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              _buildTextField('Emergency Contact Name', _emergencyNameController),
              const SizedBox(height: 12),
              _buildDropdownTextField('Relationship to User', _relationshipController, _otherRelationshipController, (isOther) {
                setState(() => _isOtherSelected = isOther);
              }),
              if (_isOtherSelected) ...[
                const SizedBox(height: 12),
                _buildTextField('Specify relationship', _otherRelationshipController),
              ],
              const SizedBox(height: 12),
              _buildTextField('Emergency Contact\'s Phone Number', _emergencyPhoneController, keyboardType: TextInputType.phone),

              // Second Emergency Contact Section
              if (_showSecondContact) ...[
                const SizedBox(height: 24),

                // Second Emergency Contact with Remove Button
                Row(
                  children: [
                    const Expanded(
                      child: Text('Second Emergency Contact', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black)),
                    ),
                    // Show remove button if contact exists (based on ID, not text)
                    if (_secondContactId != null)
                      TextButton.icon(
                        onPressed: _removeSecondEmergencyContact,
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                        label: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 12)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                _buildTextField('Emergency Contact Name 2', _emergencyName2Controller),
                const SizedBox(height: 12),
                _buildDropdownTextField('Relationship to User 2', _relationship2Controller, _otherRelationship2Controller, (isOther) {
                  setState(() => _isOther2Selected = isOther);
                }),
                if (_isOther2Selected) ...[
                  const SizedBox(height: 12),
                  _buildTextField('Specify relationship', _otherRelationship2Controller),
                ],
                const SizedBox(height: 12),
                _buildTextField('Emergency Contact\'s Phone Number 2', _emergencyPhone2Controller, keyboardType: TextInputType.phone),
              ],

              const SizedBox(height: 32),

              // Add Button - only show if no second contact exists in database
              if (!_hasSecondContact && !_showSecondContact)
                Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFF73D5C), width: 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextButton.icon(
                    onPressed: _addSecondEmergencyContact,
                    icon: const Icon(Icons.add, color: Color(0xFFF73D5C), size: 18),
                    label: const Text('Add Emergency Contact', style: TextStyle(color: Color(0xFFF73D5C), fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                ),

              // Conditional spacing - less space when no add button is shown
              SizedBox(height: (!_hasSecondContact && !_showSecondContact) ? 16 : 8),

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
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Save', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {
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
        cursorColor: const Color(0xFFF73D5C), // Add cursor color
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
        style: TextStyle(
          fontSize: 16, 
          color: (readOnly && label == 'Email Address') ? Colors.grey.shade500 : Colors.black,
        ),
      ),
    );
  }

  Widget _buildDropdownTextField(String label, TextEditingController controller, TextEditingController otherController, Function(bool) onOtherSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<String>(
        value: controller.text.isNotEmpty && 
               ['Spouse', 'Mother', 'Father', 'Sibling', 'Friend', 'Relative', 'Other'].contains(controller.text) 
               ? controller.text 
               : null,
        items: const [
          DropdownMenuItem(value: 'Spouse', child: Text('Spouse')),
          DropdownMenuItem(value: 'Mother', child: Text('Mother')),
          DropdownMenuItem(value: 'Father', child: Text('Father')),
          DropdownMenuItem(value: 'Sibling', child: Text('Sibling')),
          DropdownMenuItem(value: 'Friend', child: Text('Friend')),
          DropdownMenuItem(value: 'Relative', child: Text('Relative')),
          DropdownMenuItem(value: 'Other', child: Text('Other')),
        ],
        onChanged: (val) {
          setState(() {
            controller.text = val ?? '';
            if (val == 'Other') {
              onOtherSelected(true);
            } else {
              onOtherSelected(false);
              otherController.clear(); // Clear the other text field when not "Other"
            }
          });
        },
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
        style: const TextStyle(fontSize: 16, color: Colors.black),
      ),
    );
  }

  Widget _buildDropdownField(String label, TextEditingController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: controller.text.isNotEmpty && 
                     ['Spouse', 'Parent', 'Sibling', 'Friend', 'Relative'].contains(controller.text) 
                     ? controller.text 
                     : null,
              items: const [
                DropdownMenuItem(value: 'Spouse', child: Text('Spouse')),
                DropdownMenuItem(value: 'Parent', child: Text('Parent')),
                DropdownMenuItem(value: 'Sibling', child: Text('Sibling')),
                DropdownMenuItem(value: 'Friend', child: Text('Friend')),
                DropdownMenuItem(value: 'Relative', child: Text('Relative')),
              ],
              onChanged: (val) {
                setState(() {
                  controller.text = val ?? '';
                });
              },
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              style: const TextStyle(fontSize: 16, color: Colors.black),
              alignment: Alignment.centerRight,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCleanTextField(String label, TextEditingController controller, {
    bool readOnly = false,
    VoidCallback? onTap,
    TextInputType? keyboardType,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: controller,
              readOnly: readOnly,
              onTap: onTap,
              keyboardType: keyboardType,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
                hintStyle: TextStyle(color: Color(0xFF999999)),
              ),
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    // Remove _dobController.dispose(); since we're using _birthdateController
    _userPhoneController.dispose();
    _emailController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _relationshipController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _birthdateController.dispose();
    _emergencyName2Controller.dispose();
    _emergencyPhone2Controller.dispose();
    _relationship2Controller.dispose();
    _otherRelationshipController.dispose();
    _otherRelationship2Controller.dispose();
    super.dispose();
  }
}

