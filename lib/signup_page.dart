import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Add this import
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'login_page.dart';
import 'home_screen.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _selectedRole; // Change to nullable
  File? _proofFile;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthdateController = TextEditingController();

  // Citizen fields
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  // Tanod fields
  final _idNumberController = TextEditingController();
  final _tanodCredentialsController = TextEditingController();

  // Police fields
  final _stationNameController = TextEditingController();
  final _policeCredentialsController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _birthdateController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _idNumberController.dispose();
    _tanodCredentialsController.dispose();
    _stationNameController.dispose();
    _policeCredentialsController.dispose();
    super.dispose();
  }

  Future<void> _pickProofFile() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      setState(() {
        _proofFile = File(image.path);
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000), // Default to year 2000
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFF4081), // Pink color for header and selected date
              onPrimary: Colors.white, // Text color on primary
              surface: Colors.white, // Background color
              onSurface: Colors.black, // Text color
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _birthdateController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _signup() async {
    setState(() {
      _submitted = true; // Set this first to trigger error display
    });
    
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.user == null) throw Exception('Failed to create user');

      final userId = res.user!.id;

      // Insert basic user info
      final userData = {
        'id': userId,
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'birthdate': _birthdateController.text.trim(),
        'role': _selectedRole,
      };

      if (_selectedRole == 'citizen') {
        userData['first_name'] = _firstNameController.text.trim();
        userData['middle_name'] = _middleNameController.text.trim();
        userData['last_name'] = _lastNameController.text.trim();
        await Supabase.instance.client.from('user').insert(userData);
      } else if (_selectedRole == 'tanod') {
        // Upload proof if exists
        String? proofUrl;
        if (_proofFile != null) {
          final fileBytes = await _proofFile!.readAsBytes();
          final filePath = 'tanod_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await Supabase.instance.client.storage.from('credentials_proof').uploadBinary(filePath, fileBytes);
          proofUrl = Supabase.instance.client.storage.from('credentials_proof').getPublicUrl(filePath);
        }

        await Supabase.instance.client.from('tanod').insert({
          'id': userId,
          'email': _emailController.text.trim(),
          'id_number': _idNumberController.text.trim(),
          'credentials_url': proofUrl ?? _tanodCredentialsController.text.trim(),
        });
      } else if (_selectedRole == 'police') {
        String? proofUrl;
        if (_proofFile != null) {
          final fileBytes = await _proofFile!.readAsBytes();
          final filePath = 'police_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await Supabase.instance.client.storage.from('credentials_proof').uploadBinary(filePath, fileBytes);
          proofUrl = Supabase.instance.client.storage.from('credentials_proof').getPublicUrl(filePath);
        }

        await Supabase.instance.client.from('police').insert({
          'id': userId,
          'email': _emailController.text.trim(),
          'station_name': _stationNameController.text.trim(),
          'credentials_url': proofUrl ?? _policeCredentialsController.text.trim(),
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_selectedRole == 'citizen'
              ? 'Account created successfully!'
              : 'Account created. Please wait for verification of your credentials.'),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Validators
  String? _validateRequired(String? value) => (value == null || value.isEmpty) ? 'This field is required' : null;
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Enter an email';
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!regex.hasMatch(value)) return 'Enter a valid email format';
    return null;
  }
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter a password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }
  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'Confirm your password';
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }
  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return 'Phone number is required';
    // Remove any spaces or special characters
    String cleanedValue = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanedValue.length != 11) return 'Phone number must be 11 digits';
    if (!cleanedValue.startsWith('09')) return 'Phone number must start with 09';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: screenHeight * 0.04),
                
                // Title
                Text(
                  'Create an\naccount',
                  style: TextStyle(
                    fontSize: screenWidth * 0.08,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                
                SizedBox(height: screenHeight * 0.04),

                // Email Field - only show for citizen
                if (_selectedRole == 'citizen') ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextFormField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.person, color: Colors.grey.shade600),
                            hintText: 'Email',
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                            errorStyle: TextStyle(height: 0), // Hide default error text
                          ),
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(fontSize: screenWidth * 0.04),
                          // Remove validator completely
                        ),
                      ),
                      // Custom error display
                      if (_submitted) ...[
                        Builder(
                          builder: (context) {
                            final error = _validateEmail(_emailController.text);
                            if (error != null) {
                              return Padding(
                                padding: EdgeInsets.only(left: 8, top: 4),
                                child: Text(
                                  error,
                                  style: TextStyle(color: Colors.red, fontSize: 12),
                                ),
                              );
                            }
                            return SizedBox.shrink();
                          },
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: screenHeight * 0.02),
                ],

                // Birthdate Field - only show for citizen
                if (_selectedRole == 'citizen') ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextFormField(
                          controller: _birthdateController,
                          readOnly: true,
                          onTap: _selectDate,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.calendar_today, color: Colors.grey.shade600),
                            hintText: 'Date of Birth',
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                            errorStyle: TextStyle(height: 0),
                          ),
                          style: TextStyle(fontSize: screenWidth * 0.04),
                          // Remove validator completely
                        ),
                      ),
                      if (_submitted) ...[
                        Builder(
                          builder: (context) {
                            final error = _validateRequired(_birthdateController.text);
                            if (error != null) {
                              return Padding(
                                padding: EdgeInsets.only(left: 8, top: 4),
                                child: Text(
                                  error,
                                  style: TextStyle(color: Colors.red, fontSize: 12),
                                ),
                              );
                            }
                            return SizedBox.shrink();
                          },
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: screenHeight * 0.02),
                ],

                // Phone Field
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextFormField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.phone, color: Colors.grey.shade600),
                          hintText: 'Phone Number',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                          errorStyle: TextStyle(height: 0),
                        ),
                        keyboardType: TextInputType.phone,
                        style: TextStyle(fontSize: screenWidth * 0.04),
                        // Remove validator completely
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                      ),
                    ),
                    if (_submitted) ...[
                      Builder(
                        builder: (context) {
                          final error = _validatePhone(_phoneController.text);
                          if (error != null) {
                            return Padding(
                              padding: EdgeInsets.only(left: 8, top: 4),
                              child: Text(
                                error,
                                style: TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            );
                          }
                          return SizedBox.shrink();
                        },
                      ),
                    ],
                  ],
                ),

                SizedBox(height: screenHeight * 0.02),

                // Password Field
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.lock, color: Colors.grey.shade600),
                          hintText: 'Password',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                          errorStyle: TextStyle(height: 0),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.grey.shade600,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        style: TextStyle(fontSize: screenWidth * 0.04),
                        // Remove validator completely
                      ),
                    ),
                    if (_submitted) ...[
                      Builder(
                        builder: (context) {
                          final error = _validatePassword(_passwordController.text);
                          if (error != null) {
                            return Padding(
                              padding: EdgeInsets.only(left: 8, top: 4),
                              child: Text(
                                error,
                                style: TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            );
                          }
                          return SizedBox.shrink();
                        },
                      ),
                    ],
                  ],
                ),

                SizedBox(height: screenHeight * 0.02),

                // Confirm Password Field
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.lock, color: Colors.grey.shade600),
                          hintText: 'Confirm Password',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                          errorStyle: TextStyle(height: 0),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.grey.shade600,
                            ),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                        style: TextStyle(fontSize: screenWidth * 0.04),
                        // Remove validator completely
                      ),
                    ),
                    if (_submitted) ...[
                      Builder(
                        builder: (context) {
                          final error = _validateConfirmPassword(_confirmPasswordController.text);
                          if (error != null) {
                            return Padding(
                              padding: EdgeInsets.only(left: 8, top: 4),
                              child: Text(
                                error,
                                style: TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            );
                          }
                          return SizedBox.shrink();
                        },
                      ),
                    ],
                  ],
                ),

                SizedBox(height: screenHeight * 0.02),

                // Role Selector
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.badge, color: Colors.grey.shade600),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: screenHeight * 0.025,
                        horizontal: 12,
                      ),
                    ),
                    hint: Text(
                      'Select a role',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: screenWidth * 0.04,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'citizen', child: Text('Citizen')),
                      DropdownMenuItem(value: 'tanod', child: Text('Tanod')),
                      DropdownMenuItem(value: 'police', child: Text('Police')),
                    ],
                    onChanged: (val) => setState(() => _selectedRole = val),
                    style: TextStyle(fontSize: screenWidth * 0.04, color: Colors.black),
                  ),
                ),

                SizedBox(height: screenHeight * 0.02),

                // Role-specific fields
                if (_selectedRole == 'citizen') ...[
                  _buildTextField(_firstNameController, 'First Name', Icons.person_outline, _validateRequired),
                  SizedBox(height: screenHeight * 0.02),
                  _buildTextField(_middleNameController, 'Middle Name', Icons.person_outline, null),
                  SizedBox(height: screenHeight * 0.02),
                  _buildTextField(_lastNameController, 'Last Name', Icons.person_outline, _validateRequired),
                  SizedBox(height: screenHeight * 0.02),
                ],

                if (_selectedRole == 'tanod') ...[
                  _buildTextField(_idNumberController, 'ID Number', Icons.badge, _validateRequired),
                  SizedBox(height: screenHeight * 0.02),
                  _buildUploadButton('Upload Credentials Proof'),
                  SizedBox(height: screenHeight * 0.02),
                ],

                if (_selectedRole == 'police') ...[
                  _buildTextField(_stationNameController, 'Station Name', Icons.location_city, _validateRequired),
                  SizedBox(height: screenHeight * 0.02),
                  _buildUploadButton('Upload Credentials Proof'),
                  SizedBox(height: screenHeight * 0.02),
                ],

                // Terms text
                Padding(
                  padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                  child: RichText(
                    text: TextSpan(
                      text: 'By clicking the ',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: screenWidth * 0.035),
                      children: [
                        TextSpan(
                          text: 'Create Account',
                          style: TextStyle(color: Color(0xFFFF4081), fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: ' button, you agree\nto the '),
                        TextSpan(
                          text: 'Terms and Conditions',
                          style: TextStyle(color: Color(0xFFFF4081), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: screenHeight * 0.02),

                // Create Account Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF4081),
                      padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _signup,
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        : Text(
                            'Create Account',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: screenWidth * 0.045,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                SizedBox(height: screenHeight * 0.03),

                // OR Continue with
                Row(
                  children: [
                    Expanded(child: Divider(thickness: 1, color: Colors.grey.shade300)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '- OR Continue with -',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: screenWidth * 0.035,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(thickness: 1, color: Colors.grey.shade300)),
                  ],
                ),

                SizedBox(height: screenHeight * 0.03),

                // Social Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSocialButton(FontAwesomeIcons.google),
                    SizedBox(width: screenWidth * 0.06),
                    _buildSocialButton(FontAwesomeIcons.facebookF),
                  ],
                ),

                SizedBox(height: screenHeight * 0.04),

                // Already have account
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'I Already Have an Account ',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: screenWidth * 0.035,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      },
                      child: Text(
                        'Login',
                        style: TextStyle(
                          color: Color(0xFFFF4081),
                          fontSize: screenWidth * 0.035,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: screenHeight * 0.04),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, String? Function(String?)? validator) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.grey.shade600),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade600),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
              errorStyle: TextStyle(height: 0),
            ),
            style: TextStyle(fontSize: screenWidth * 0.04),
            // Remove validator completely
          ),
        ),
        if (_submitted && validator != null) ...[
          Builder(
            builder: (context) {
              final error = validator(controller.text);
              if (error != null) {
                return Padding(
                  padding: EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    error,
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                );
              }
              return SizedBox.shrink();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildUploadButton(String text) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: _pickProofFile,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.upload_file, color: Colors.grey.shade600),
              SizedBox(width: 12),
              Text(
                _proofFile == null ? text : 'Document Selected',
                style: TextStyle(
                  color: _proofFile == null ? Colors.grey.shade600 : Colors.black,
                  fontSize: screenWidth * 0.04,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton(IconData icon) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Container(
      width: screenWidth * 0.12,
      height: screenWidth * 0.12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Color(0xFFFF4081), width: 2),
      ),
      child: Center(
        child: FaIcon(
          icon,
          color: Color(0xFFFF4081),
          size: screenWidth * 0.05,
        ),
      ),
    );
  }
}