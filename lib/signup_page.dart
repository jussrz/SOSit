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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                const Text(
                  'Create an\naccount',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 32),


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
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.person, color: Colors.grey),
                          hintText: 'Email',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 18),
                        ),
                        keyboardType: TextInputType.emailAddress,
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

                const SizedBox(height: 20),

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
                          contentPadding: const EdgeInsets.symmetric(vertical: 18),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        obscureText: _obscurePassword,
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

                const SizedBox(height: 20),

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
                          contentPadding: const EdgeInsets.symmetric(vertical: 18),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                        obscureText: _obscureConfirmPassword,
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

                const SizedBox(height: 12),

                // Terms
                Padding(
                  padding: const EdgeInsets.only(left: 4.0, top: 4.0),
                  child: RichText(
                    text: TextSpan(
                      text: 'By clicking the ',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
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

                const SizedBox(height: 24),

                // Create Account Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF73D5C),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _signup,
                    child: const Text(
                      'Create Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // OR Continue with
                Row(
                  children: const [
                    Expanded(child: Divider(thickness: 1)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        '- OR Continue with -',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(thickness: 1)),
                  ],
                ),

                const SizedBox(height: 24),

                // Social Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: const CircleBorder(),
                        side: const BorderSide(color: Color(0xFFF73D5C)),
                        padding: const EdgeInsets.all(16),
                      ),
                      onPressed: () {
                        // TODO: Google signup
                      },
                      child: const FaIcon(
                        FontAwesomeIcons.google,
                        color: Color(0xFFF73D5C),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 24),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: const CircleBorder(),
                        side: const BorderSide(color: Color(0xFFF73D5C)),
                        padding: const EdgeInsets.all(16),
                      ),
                      onPressed: () {
                        // TODO: Facebook signup
                      },
                      child: const FaIcon(
                        FontAwesomeIcons.facebookF,
                        color: Color(0xFFF73D5C),
                        size: 28,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Already have account
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'I Already Have an Account ',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      },
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          color: Color(0xFFF73D5C),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
