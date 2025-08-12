import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'login_page.dart';
import 'home_screen.dart'; // Add this import

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  bool _submitted = false;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    setState(() {
      _submitted = true;
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
    });

    // Manual validation for error display
    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _emailError = 'Email is required.';
      });
    } else if (!_emailController.text.contains('@') || !_emailController.text.contains('.com')) {
      setState(() {
        _emailError = 'Invalid email format.';
      });
    }

    if (_passwordController.text.trim().isEmpty) {
      setState(() {
        _passwordError = 'Password is required.';
      });
    }

    if (_confirmPasswordController.text.trim().isEmpty) {
      setState(() {
        _confirmPasswordError = 'Please confirm your password.';
      });
    } else if (_confirmPasswordController.text != _passwordController.text) {
      setState(() {
        _confirmPasswordError = 'Passwords do not match.';
      });
    }

    if (_emailError != null || _passwordError != null || _confirmPasswordError != null) {
      return;
    }

    if (_formKey.currentState!.validate()) {
      try {
        final AuthResponse res = await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // Create initial profile with email
        if (res.user != null) {
          await Supabase.instance.client.from('profiles').upsert({
            'id': res.user!.id,
            'email': res.user!.email,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        }

        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()), // This will now use the correct HomeScreen
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Signup failed: $e')),
          );
        }
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
                        validator: (value) {
                          // No error text here, handled below
                          return null;
                        },
                      ),
                    ),
                    if (_submitted && _emailController.text.trim().isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 4),
                        child: Text('Email is required.', style: TextStyle(color: Colors.red, fontSize: 12)),
                      )
                    else if (_submitted &&
                        _emailController.text.isNotEmpty &&
                        (!_emailController.text.contains('@') || !_emailController.text.contains('.com')))
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 4),
                        child: Text('Invalid email format.', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                  ],
                ),

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
                        validator: (value) {
                          // No error text here, handled below
                          return null;
                        },
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
                        validator: (value) {
                          // No error text here, handled below
                          return null;
                        },
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
                    onPressed: _signup,
                    child: Text(
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

                // OR Continue with
                Row(
                  children: [
                    const Expanded(child: Divider(thickness: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        '- OR Continue with -',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: screenWidth * 0.035,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider(thickness: 1)),
                  ],
                ),

                SizedBox(height: screenHeight * 0.03),

                // Social Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: const CircleBorder(),
                        side: const BorderSide(color: Color(0xFFF73D5C)),
                        padding: EdgeInsets.all(screenWidth * 0.04),
                      ),
                      onPressed: () {
                        // TODO: Google signup
                      },
                      child: FaIcon(
                        FontAwesomeIcons.google,
                        color: const Color(0xFFF73D5C),
                        size: screenWidth * 0.07,
                      ),
                    ),
                    SizedBox(width: screenWidth * 0.06),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: const CircleBorder(),
                        side: const BorderSide(color: Color(0xFFF73D5C)),
                        padding: EdgeInsets.all(screenWidth * 0.04),
                      ),
                      onPressed: () {
                        // TODO: Facebook signup
                      },
                      child: FaIcon(
                        FontAwesomeIcons.facebookF,
                        color: const Color(0xFFF73D5C),
                        size: screenWidth * 0.07,
                      ),
                    ),
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
                        color: Colors.black54,
                        fontSize: screenWidth * 0.035,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
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
