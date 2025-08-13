import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'signup_page.dart';
import 'home_screen.dart'; // Add this import

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitted = false;
  String? _emailError;
  String? _passwordError;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _submitted = true;
      _emailError = null;
      _passwordError = null;
      _isLoading = true;
    });

    // Validate fields manually for bottom error display
    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _emailError = 'Email is required';
        _isLoading = false;
      });
      return;
    } else if (!_emailController.text.contains('@') || !_emailController.text.contains('.com')) {
      setState(() {
        _emailError = 'Invalid email format';
        _isLoading = false;
      });
      return;
    }

    if (_passwordController.text.trim().isEmpty) {
      setState(() {
        _passwordError = 'Password is required';
        _isLoading = false;
      });
      return;
    }

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (response.user != null) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Handle specific error types
          String errorMessage = e.toString().toLowerCase();
          
          if (errorMessage.contains('invalid login credentials') || 
              errorMessage.contains('invalid_credentials') ||
              errorMessage.contains('invalid_grant')) {
            // Default to email not found for invalid credentials
            _emailError = 'Email not found';
          } else if (errorMessage.contains('email not confirmed')) {
            _emailError = 'Please verify your email address';
          } else if (errorMessage.contains('too many requests')) {
            _emailError = 'Too many attempts. Please try again later';
          } else if (errorMessage.contains('user not found') || 
                     errorMessage.contains('email not found')) {
            _emailError = 'Email not found';
          } else if (errorMessage.contains('wrong password') ||
                     errorMessage.contains('incorrect password')) {
            _passwordError = 'Wrong password';
          } else {
            // Default to email not found for unknown errors
            _emailError = 'Email not found';
          }ß
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06), // 6% of screen width
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: isSmallScreen ? 16 : 32),
                    Text(
                      'Welcome\nBack!',
                      style: TextStyle(
                        fontSize: screenWidth * 0.09, // Dynamic font size based on screen width
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.left,
                    ),
                    SizedBox(height: isSmallScreen ? 24 : 36),

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
                              contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.025), // Dynamic padding
                            ),
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(fontSize: screenWidth * 0.045), // Dynamic text size
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }
                              if (!value.contains('@') || !value.contains('.com')) {
                                return null;
                              }
                              return null;
                            },
                          ),
                        ),
                        if (_submitted && _emailError != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 4),
                            child: Text(
                              _emailError!,
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
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
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }
                              return null;
                            },
                          ),
                        ),
                        if (_submitted && _passwordError != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 4),
                            child: Text(
                              _passwordError!,
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                      ],
                    ),

                    // Forgot Password
                    Padding(
                      padding: EdgeInsets.only(top: screenHeight * 0.01, right: 4.0),
                      child: Row(
                        children: [
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              // TODO: Implement forgot password
                            },
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: const Color(0xFFF73D5C),
                                fontSize: screenWidth * 0.035,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.035),

                    // Login Button
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
                        onPressed: _isLoading ? null : _login,
                        child: _isLoading
                            ? SizedBox(
                                height: screenWidth * 0.05,
                                width: screenWidth * 0.05,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                'Login',
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
                        // Google
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            shape: const CircleBorder(),
                            side: const BorderSide(color: Color(0xFFF73D5C)),
                            padding: EdgeInsets.all(screenWidth * 0.04),
                          ),
                          onPressed: () {
                            // TODO: Google login
                          },
                          child: FaIcon(
                            FontAwesomeIcons.google,
                            color: const Color(0xFFF73D5C),
                            size: screenWidth * 0.07,
                          ),
                        ),
                        SizedBox(width: screenWidth * 0.06),
                        // Facebook
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            shape: const CircleBorder(),
                            side: const BorderSide(color: Color(0xFFF73D5C)),
                            padding: EdgeInsets.all(screenWidth * 0.04),
                          ),
                          onPressed: () {
                            // TODO: Facebook login
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

                    // Create Account / Sign Up
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Create An Account ',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: screenWidth * 0.035,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(builder: (_) => const SignupPage()),
                            );
                          },
                          child: Text(
                            'Sign Up',
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
        ],
      ),
    );
  }
}