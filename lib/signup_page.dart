import 'package:flutter/material.dart';
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
  String _selectedRole = 'User';
  File? _proofFile;
  
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _stationCodeController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _idNumberController.dispose();
    _stationCodeController.dispose();
    super.dispose();
  }

  Future<void> _pickProofFile() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null && mounted) {
      setState(() {
        _proofFile = File(image.path);
      });
    }
  }

  Future<void> _signup() async {
    if (!mounted) return;

    setState(() {
      _submitted = true;
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
      _isLoading = true;
    });

    // Basic validation
    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _emailError = 'Email is required.';
        _isLoading = false;
      });
      return;
    }
    // More comprehensive email validation
    String email = _emailController.text.trim();
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      setState(() {
        _emailError = 'Please enter a valid email address';
        _isLoading = false;
      });
      return;
    }
    if (_passwordController.text.trim().isEmpty) {
      setState(() {
        _passwordError = 'Password is required.';
        _isLoading = false;
      });
      return;
    }
    if (_confirmPasswordController.text.trim().isEmpty) {
      setState(() {
        _confirmPasswordError = 'Please confirm your password.';
        _isLoading = false;
      });
      return;
    }
    if (_confirmPasswordController.text != _passwordController.text) {
      setState(() {
        _confirmPasswordError = 'Passwords do not match.';
        _isLoading = false;
      });
      return;
    }

    // Additional validation for authority roles
    if (_selectedRole != 'User') {
      if (_fullNameController.text.trim().isEmpty ||
          _phoneController.text.trim().isEmpty ||
          _idNumberController.text.trim().isEmpty ||
          (_selectedRole == 'PNP' && _stationCodeController.text.trim().isEmpty) ||
          _proofFile == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please fill all required fields and upload proof document')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }
    }

    try {
      // Step 1: Create auth account
      final AuthResponse res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.user == null) throw Exception('Failed to create user');

      // Step 2: Upload proof document if role is Authority
      String? proofUrl;
      if (_selectedRole != 'User' && _proofFile != null) {
        final fileBytes = await _proofFile!.readAsBytes();
        final filePath = '${_selectedRole}_${DateTime.now().millisecondsSinceEpoch}.jpg';

        await Supabase.instance.client.storage
            .from('credentials_proof')
            .uploadBinary(filePath, fileBytes);

        proofUrl = Supabase.instance.client.storage
            .from('credentials_proof')
            .getPublicUrl(filePath);
      }

      // Step 3: Create profile based on role
      if (_selectedRole == 'User') {
        await Supabase.instance.client.from('citizens').insert({
          'id': res.user!.id,
          'email': res.user!.email,
          'full_name': _fullNameController.text.trim(),
          'phone_number': _phoneController.text.trim(),
          'created_at': DateTime.now().toIso8601String(),
        });
      } else {
        await Supabase.instance.client.from('authority_accounts').insert({
          'id': res.user!.id,
          'email': res.user!.email,
          'full_name': _fullNameController.text.trim(),
          'phone_number': _phoneController.text.trim(),
          'role': _selectedRole, // 'PNP' or 'Tanod'
          'id_number': _idNumberController.text.trim(),
          'station_code': _selectedRole == 'PNP' ? _stationCodeController.text.trim() : null,
          'credentials_proof_url': proofUrl,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_selectedRole == 'User' 
              ? 'Account created successfully!' 
              : 'Account created. Please wait for verification of your credentials.'),
          ),
        );
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signup failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final isSmallScreen = screenHeight < 650;
    
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
                SizedBox(height: isSmallScreen ? 16 : 32),
                Text(
                  'Create an\naccount',
                  style: TextStyle(
                    fontSize: screenWidth * 0.08,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 24 : 32),

                // Email Field
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.person, color: Colors.grey),
                          hintText: 'Email',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(fontSize: screenWidth * 0.045),
                      ),
                    ),
                    if (_submitted && _emailController.text.trim().isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 4),
                        child: Text('Email is required.', style: TextStyle(color: Colors.red, fontSize: 12)),
                      )
                    else if (_submitted &&
                        _emailController.text.isNotEmpty &&
                        !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(_emailController.text))
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 4),
                        child: Text('Invalid email format.', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                  ],
                ),

                SizedBox(height: screenHeight * 0.025),

                // Full Name Field
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextFormField(
                    controller: _fullNameController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.person_outline, color: Colors.grey),
                      hintText: 'Full Name',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                    ),
                    style: TextStyle(fontSize: screenWidth * 0.045),
                  ),
                ),

                SizedBox(height: screenHeight * 0.025),

                // Phone Number Field
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.phone, color: Colors.grey),
                      hintText: 'Phone Number',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                    ),
                    keyboardType: TextInputType.phone,
                    style: TextStyle(fontSize: screenWidth * 0.045),
                  ),
                ),

                SizedBox(height: screenHeight * 0.025),

                // Role Selector
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.badge, color: Colors.grey),
                      border: InputBorder.none,
                    ),
                    items: ['User', 'PNP', 'Tanod'].map((String role) {
                      return DropdownMenuItem<String>(
                        value: role,
                        child: Text(role),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedRole = newValue!;
                      });
                    },
                  ),
                ),

                // Authority-specific fields
                if (_selectedRole != 'User') ...[
                  SizedBox(height: screenHeight * 0.025),
                  
                  // ID Number Field
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextFormField(
                      controller: _idNumberController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.badge, color: Colors.grey),
                        hintText: 'ID Number',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                      ),
                      style: TextStyle(fontSize: screenWidth * 0.045),
                    ),
                  ),

                  if (_selectedRole == 'PNP') ...[
                    SizedBox(height: screenHeight * 0.025),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextFormField(
                        controller: _stationCodeController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.location_city, color: Colors.grey),
                          hintText: 'Station Code',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                        ),
                        style: TextStyle(fontSize: screenWidth * 0.045),
                      ),
                    ),
                  ],

                  SizedBox(height: screenHeight * 0.025),
                  ElevatedButton.icon(
                    onPressed: _pickProofFile,
                    icon: const Icon(Icons.upload_file),
                    label: Text(_proofFile == null ? 'Upload Credentials Proof' : 'Document Selected'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFFF73D5C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'Please upload a clear photo of your ID or authorization document',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: screenWidth * 0.035,
                      ),
                    ),
                  ),
                ],

                SizedBox(height: screenHeight * 0.025),

                // Password Field
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock, color: Colors.grey),
                          hintText: 'Password',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        style: TextStyle(fontSize: screenWidth * 0.045),
                      ),
                    ),
                    if (_submitted && _passwordController.text.trim().isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 4),
                        child: Text('Password is required.', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                  ],
                ),

                SizedBox(height: screenHeight * 0.025),

                // Confirm Password Field
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextFormField(
                        controller: _confirmPasswordController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock, color: Colors.grey),
                          hintText: 'Confirm Password',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                        obscureText: _obscureConfirmPassword,
                        style: TextStyle(fontSize: screenWidth * 0.045),
                      ),
                    ),
                    if (_submitted && _confirmPasswordController.text.trim().isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 4),
                        child: Text('Please confirm your password.', style: TextStyle(color: Colors.red, fontSize: 12)),
                      )
                    else if (_submitted &&
                        _confirmPasswordController.text.isNotEmpty &&
                        _confirmPasswordController.text != _passwordController.text)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 4),
                        child: Text('Passwords do not match.', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                  ],
                ),

                SizedBox(height: screenHeight * 0.015),

                // Terms
                Padding(
                  padding: const EdgeInsets.only(left: 4.0, top: 4.0),
                  child: RichText(
                    text: TextSpan(
                      text: 'By clicking the ',
                      style: TextStyle(color: Colors.black54, fontSize: screenWidth * 0.035),
                      children: [
                        TextSpan(
                          text: 'Create Account',
                          style: const TextStyle(color: Color(0xFFF73D5C)),
                        ),
                        const TextSpan(
                          text: ' button, you agree\nto the public offer',
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: screenHeight * 0.03),

                // Create Account Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF73D5C),
                      padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _signup,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'Create Account',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: screenWidth * 0.045,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                ),

                SizedBox(height: screenHeight * 0.04),

                // Already have account
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'I Already Have an Account ',
                      style: TextStyle(
                        color: Colors.black54,
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
                          color: const Color(0xFFF73D5C),
                          fontSize: screenWidth * 0.035,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: screenHeight * 0.06),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
