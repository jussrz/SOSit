import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';

class AdminSignupPage extends StatefulWidget {
  const AdminSignupPage({super.key});

  @override
  State<AdminSignupPage> createState() => _AdminSignupPageState();
}

class _AdminSignupPageState extends State<AdminSignupPage> {
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    setState(() {
      _submitted = true;
    });

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Check if admin already exists with this email
      final existingAdmin = await Supabase.instance.client
          .from('admin')
          .select('admin_email')
          .eq('admin_email', _emailController.text.trim())
          .maybeSingle();

      if (existingAdmin != null) {
        throw Exception('An admin account with this email already exists');
      }

      // 1. Create auth account in Supabase
      final res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.user == null) throw Exception('Failed to create user');

      final userId = res.user!.id;

      // 2. Insert into admin table directly (bypass RLS if needed)
      await Supabase.instance.client.from('admin').insert({
        'id': userId,
        'admin_firstname': _firstNameController.text.trim(),
        'admin_lastname': _lastNameController.text.trim(),
        'admin_email': _emailController.text.trim(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin account created successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Signup failed: ${e.toString()}';

        // Handle specific error cases
        if (e.toString().contains('already exists')) {
          errorMessage = 'An admin account with this email already exists';
        } else if (e.toString().contains('User already registered')) {
          errorMessage =
              'This email is already registered. Please use a different email or login instead.';
        } else if (e.toString().contains('duplicate key')) {
          errorMessage = 'An admin account with this email already exists';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Validators
  String? _validateRequired(String? value) =>
      (value == null || value.isEmpty) ? 'This field is required' : null;

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

                // Back button
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                SizedBox(height: screenHeight * 0.02),

                // Title with admin badge
                Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings,
                      color: const Color(0xFFFF4081),
                      size: screenWidth * 0.08,
                    ),
                    SizedBox(width: screenWidth * 0.03),
                    Expanded(
                      child: Text(
                        'Create Admin\nAccount',
                        style: TextStyle(
                          fontSize: screenWidth * 0.08,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: screenHeight * 0.04),

                // First Name Field
                _buildTextField(_firstNameController, 'First Name',
                    Icons.person_outline, _validateRequired),

                SizedBox(height: screenHeight * 0.02),

                // Last Name Field
                _buildTextField(_lastNameController, 'Last Name',
                    Icons.person_outline, _validateRequired),

                SizedBox(height: screenHeight * 0.02),

                // Email Field
                _buildTextField(
                    _emailController, 'Email', Icons.email, _validateEmail),

                SizedBox(height: screenHeight * 0.02),

                // Password Field
                _buildTextField(
                  _passwordController,
                  'Password',
                  Icons.lock,
                  _validatePassword,
                  obscureText: _obscurePassword,
                  toggleObscure: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),

                SizedBox(height: screenHeight * 0.02),

                // Confirm Password Field
                _buildTextField(
                  _confirmPasswordController,
                  'Confirm Password',
                  Icons.lock,
                  _validateConfirmPassword,
                  obscureText: _obscureConfirmPassword,
                  toggleObscure: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),

                SizedBox(height: screenHeight * 0.04),

                // Create Admin Account Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4081),
                      padding:
                          EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _signup,
                    child: _isLoading
                        ? CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2)
                        : Text(
                            'Create Admin Account',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: screenWidth * 0.045,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                SizedBox(height: screenHeight * 0.03),

                // Back to login
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
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
                          color: const Color(0xFFFF4081),
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

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon,
    String? Function(String?)? validator, {
    bool obscureText = false,
    VoidCallback? toggleObscure,
  }) {
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
            obscureText: obscureText,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.grey.shade600),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade600),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(vertical: screenHeight * 0.025),
              errorStyle: TextStyle(height: 0),
              suffixIcon: toggleObscure != null
                  ? IconButton(
                      icon: Icon(
                        obscureText ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey.shade600,
                      ),
                      onPressed: toggleObscure,
                    )
                  : null,
            ),
            style: TextStyle(fontSize: screenWidth * 0.04),
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
}
