import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'signup_page.dart';
import 'admin_signup_page.dart';
import 'home_screen.dart'; // Import HomeScreen directly
import 'admin_home_screen.dart';
import 'police_dashboard.dart';
import 'tanod_dashboard.dart';
import 'services/parent_notification_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _submitted = false;
  String? _errorMsg;
  bool _showAdminSignup = false;
  bool _checkingAdminStatus = true;

  final RegExp _emailRegex =
      RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");

  @override
  void initState() {
    super.initState();
    _checkAdminExists();
  }

  Future<void> _checkAdminExists() async {
    try {
      // Check if any admin exists in the database
      final adminCount = await Supabase.instance.client
          .from('admin')
          .select('id')
          .count(CountOption.exact);

      setState(() {
        _showAdminSignup =
            adminCount.count == 0; // Show only if no admins exist
        _checkingAdminStatus = false;
      });
    } catch (e) {
      debugPrint('Error checking admin status: $e');
      setState(() {
        _showAdminSignup = true; // Show by default if error occurs
        _checkingAdminStatus = false;
      });
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Enter an email';
    if (!_emailRegex.hasMatch(value)) return 'Enter a valid email format';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter a password';
    return null;
  }

  Future<void> _login() async {
    setState(() {
      _submitted = true;
      _errorMsg = null;
    });

    final emailError = _validateEmail(_emailController.text.trim());
    final passwordError = _validatePassword(_passwordController.text.trim());

    if (emailError != null || passwordError != null) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = response.user;
      if (user == null) {
        setState(() => _errorMsg = "Login failed. Please try again.");
        return;
      }

      // Check if user is an admin first
      final adminData = await Supabase.instance.client
          .from('admin')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (adminData != null) {
        // User is an admin, redirect to admin home screen
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
        );
        return;
      }

      // If not admin, check if user exists in the user table and get their role
      final userData = await Supabase.instance.client
          .from('user')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (userData != null && userData['role'] != null) {
        // Navigate based on user role
        if (userData['role'] == 'police') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PoliceDashboard()),
          );
        } else if (userData['role'] == 'tanod') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const TanodDashboard()),
          );
        } else {
          // Initialize parent notification service for regular/parent users
          try {
            await ParentNotificationService().initialize();
            debugPrint('ParentNotificationService initialized after login');
          } catch (e) {
            debugPrint('Error initializing ParentNotificationService after login: $e');
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else {
        // Default fallback
        // Initialize parent notification service for default users
        try {
          await ParentNotificationService().initialize();
          debugPrint('ParentNotificationService initialized after login (fallback)');
        } catch (e) {
          debugPrint('Error initializing ParentNotificationService after login (fallback): $e');
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() => _errorMsg = "Incorrect email or password");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();
    bool isLoading = false;
    String? message;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Reset Password',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your email address and we\'ll send you a link to reset your password.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: 'Enter your email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFFF73D5C),
                      width: 2,
                    ),
                  ),
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: message!.contains('Error')
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        message!.contains('Error')
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: message!.contains('Error')
                            ? Colors.red
                            : Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          message!,
                          style: TextStyle(
                            color: message!.contains('Error')
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final email = emailController.text.trim();
                      if (email.isEmpty) {
                        setState(() {
                          message = 'Error: Please enter your email address';
                        });
                        return;
                      }

                      if (!email.contains('@')) {
                        setState(() {
                          message = 'Error: Please enter a valid email address';
                        });
                        return;
                      }

                      setState(() {
                        isLoading = true;
                        message = null;
                      });

                      try {
                        await Supabase.instance.client.auth
                            .resetPasswordForEmail(
                          email,
                          redirectTo: 'io.supabase.flutter://reset-password',
                        );

                        setState(() {
                          isLoading = false;
                          message =
                              'Password reset link sent! Check your email inbox.';
                        });

                        // Auto-close dialog after 2 seconds on success
                        Future.delayed(const Duration(seconds: 2), () {
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        });
                      } catch (e) {
                        setState(() {
                          isLoading = false;
                          message = 'Error: ${e.toString()}';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF73D5C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Send Reset Link'),
            ),
          ],
        ),
      ),
    );
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: screenHeight * 0.1),

              // Title
              Text(
                'Welcome\nBack!',
                style: TextStyle(
                  fontSize: screenWidth * 0.08,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),

              SizedBox(height: screenHeight * 0.06),

              // General error message
              if (_errorMsg != null) ...[
                Container(
                  padding: EdgeInsets.all(12),
                  margin: EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                  ),
                ),
              ],

              // Email Field
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        prefixIcon:
                            Icon(Icons.person, color: Colors.grey.shade600),
                        hintText: 'Email',
                        hintStyle: TextStyle(color: Colors.grey.shade600),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            vertical: screenHeight * 0.025),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(fontSize: screenWidth * 0.04),
                    ),
                  ),
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

              // Password Field
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        prefixIcon:
                            Icon(Icons.lock, color: Colors.grey.shade600),
                        hintText: 'Password',
                        hintStyle: TextStyle(color: Colors.grey.shade600),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            vertical: screenHeight * 0.025),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      style: TextStyle(fontSize: screenWidth * 0.04),
                    ),
                  ),
                  if (_submitted) ...[
                    Builder(
                      builder: (context) {
                        final error =
                            _validatePassword(_passwordController.text);
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

              // Forgot Password
              Padding(
                padding: EdgeInsets.only(top: screenHeight * 0.01, right: 4.0),
                child: Row(
                  children: [
                    const Spacer(),
                    GestureDetector(
                      onTap: _showForgotPasswordDialog,
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

              SizedBox(height: screenHeight * 0.04),

              // Login Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF73D5C),
                    padding:
                        EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)
                      : Text(
                          'Login',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: screenWidth * 0.045,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              SizedBox(height: screenHeight * 0.04),

              // OR Continue with
              Row(
                children: [
                  Expanded(
                      child:
                          Divider(thickness: 1, color: Colors.grey.shade300)),
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
                  Expanded(
                      child:
                          Divider(thickness: 1, color: Colors.grey.shade300)),
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

              // Create Account
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Don\'t have an account? ',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: screenWidth * 0.035,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const SignupPage()),
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

              // Conditional Admin Signup Link
              if (!_checkingAdminStatus && _showAdminSignup) ...[
                SizedBox(height: screenHeight * 0.02),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Administrator? ',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: screenWidth * 0.035,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AdminSignupPage()),
                        ).then((_) =>
                            _checkAdminExists()); // Refresh admin status after returning
                      },
                      child: Text(
                        'Signup as Admin',
                        style: TextStyle(
                          color: const Color(0xFFF73D5C),
                          fontSize: screenWidth * 0.035,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              SizedBox(height: screenHeight * 0.06),
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
        border: Border.all(color: const Color(0xFFF73D5C), width: 2),
      ),
      child: Center(
        child: FaIcon(
          icon,
          color: const Color(0xFFF73D5C),
          size: screenWidth * 0.05,
        ),
      ),
    );
  }
}
