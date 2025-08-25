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
  String _selectedRole = 'citizen';
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

  Future<void> _signup() async {
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
                  style: TextStyle(fontSize: screenWidth * 0.08, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: isSmallScreen ? 24 : 32),

                // Email
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person),
                    hintText: 'Email',
                  ),
                  validator: _validateEmail,
                ),
                SizedBox(height: 16),

                // Birthdate
                TextFormField(
                  controller: _birthdateController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.calendar_today),
                    hintText: 'YYYY-MM-DD',
                  ),
                  validator: _validateRequired,
                ),
                SizedBox(height: 16),

                // Phone
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.phone),
                    hintText: 'Phone Number',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: _validateRequired,
                ),
                SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock),
                    hintText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: _validatePassword,
                ),
                SizedBox(height: 16),

                // Confirm Password
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock),
                    hintText: 'Confirm Password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                  validator: _validateConfirmPassword,
                ),
                SizedBox(height: 16),

                // Role Selector
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  items: const [
                    DropdownMenuItem(value: 'citizen', child: Text('Citizen')),
                    DropdownMenuItem(value: 'tanod', child: Text('Tanod')),
                    DropdownMenuItem(value: 'police', child: Text('Police')),
                  ],
                  onChanged: (val) => setState(() => _selectedRole = val!),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.badge),
                  ),
                ),
                SizedBox(height: 16),

                // Citizen Fields
                if (_selectedRole == 'citizen') ...[
                  TextFormField(
                    controller: _firstNameController,
                    decoration: const InputDecoration(hintText: 'First Name'),
                    validator: _validateRequired,
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _middleNameController,
                    decoration: const InputDecoration(hintText: 'Middle Name'),
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    controller: _lastNameController,
                    decoration: const InputDecoration(hintText: 'Last Name'),
                    validator: _validateRequired,
                  ),
                  SizedBox(height: 16),
                ],

                // Tanod Fields
                if (_selectedRole == 'tanod') ...[
                  TextFormField(
                    controller: _idNumberController,
                    decoration: const InputDecoration(hintText: 'ID Number'),
                    validator: _validateRequired,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pickProofFile,
                    icon: const Icon(Icons.upload_file),
                    label: Text(_proofFile == null ? 'Upload Credentials Proof' : 'Document Selected'),
                  ),
                  SizedBox(height: 16),
                ],

                // Police Fields
                if (_selectedRole == 'police') ...[
                  TextFormField(
                    controller: _stationNameController,
                    decoration: const InputDecoration(hintText: 'Station Name'),
                    validator: _validateRequired,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pickProofFile,
                    icon: const Icon(Icons.upload_file),
                    label: Text(_proofFile == null ? 'Upload Credentials Proof' : 'Document Selected'),
                  ),
                  SizedBox(height: 16),
                ],

                // Signup Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signup,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Create Account'),
                  ),
                ),

                // Already have an account? Login
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                    },
                    child: const Text(
                      "Already have an account? Login",
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: screenHeight * 0.04),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
