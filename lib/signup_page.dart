import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'login_page.dart';

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

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthdateController = TextEditingController();

  // Citizen fields
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();

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
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFF4081),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _birthdateController.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
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
      // 1. Create auth account in Supabase
      final res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.user == null) throw Exception('Failed to create user');

      final userId = res.user!.id;

      // 2. Insert into user table as citizen
      final userData = {
        'id': userId,
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': 'citizen',
        'first_name': _firstNameController.text.trim().isNotEmpty
            ? _firstNameController.text.trim()
            : null,
        'middle_name': _middleNameController.text.trim().isNotEmpty
            ? _middleNameController.text.trim()
            : null,
        'last_name': _lastNameController.text.trim().isNotEmpty
            ? _lastNameController.text.trim()
            : null,
        'birthdate': _birthdateController.text.trim().isNotEmpty
            ? _birthdateController.text.trim()
            : null,
      };

      await Supabase.instance.client.from('user').insert(userData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created successfully!')),
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

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return 'Phone number is required';
    String cleanedValue = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanedValue.length != 11) return 'Phone number must be 11 digits';
    if (!cleanedValue.startsWith('09')) {
      return 'Phone number must start with 09';
    }
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

                Text(
                  'Create an\naccount',
                  style: TextStyle(
                    fontSize: screenWidth * 0.08,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),

                SizedBox(height: screenHeight * 0.04),

                // Email Field
                _buildTextField(
                    _emailController, 'Email', Icons.person, _validateEmail),

                SizedBox(height: screenHeight * 0.02),

                // Birthdate
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
                          prefixIcon: Icon(Icons.calendar_today,
                              color: Colors.grey.shade600),
                          hintText: 'Date of Birth',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              vertical: screenHeight * 0.025),
                          errorStyle: TextStyle(height: 0),
                        ),
                        style: TextStyle(fontSize: screenWidth * 0.04),
                      ),
                    ),
                    if (_submitted) ...[
                      Builder(
                        builder: (context) {
                          final error =
                              _validateRequired(_birthdateController.text);
                          if (error != null) {
                            return Padding(
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: Text(error,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 12)),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ],
                ),

                SizedBox(height: screenHeight * 0.02),

                // Phone
                _buildTextField(_phoneController, 'Phone Number', Icons.phone,
                    _validatePhone,
                    keyboardType: TextInputType.phone,
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ]),

                SizedBox(height: screenHeight * 0.02),

                // Password
                _buildPasswordField(
                    _passwordController, 'Password', _validatePassword, true),

                SizedBox(height: screenHeight * 0.02),

                // Confirm Password
                _buildPasswordField(_confirmPasswordController,
                    'Confirm Password', _validateConfirmPassword, false),

                SizedBox(height: screenHeight * 0.02),

                // Citizen fields
                _buildTextField(_firstNameController, 'First Name',
                    Icons.person_outline, _validateRequired),
                SizedBox(height: screenHeight * 0.02),
                _buildTextField(
                    _middleNameController, 'Middle Name', Icons.person_outline, null),
                SizedBox(height: screenHeight * 0.02),
                _buildTextField(_lastNameController, 'Last Name',
                    Icons.person_outline, _validateRequired),
                SizedBox(height: screenHeight * 0.02),

                Padding(
                  padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                  child: RichText(
                    text: TextSpan(
                      text: 'By clicking the ',
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: screenWidth * 0.035),
                      children: const [
                        TextSpan(
                          text: 'Create Account',
                          style: TextStyle(
                              color: Color(0xFFF73D5C),
                              fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: ' button, you agree\nto the '),
                        TextSpan(
                          text: 'Terms and Conditions',
                          style: TextStyle(
                              color: Color(0xFFF73D5C),
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: screenHeight * 0.02),

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
                    onPressed: _isLoading ? null : _signup,
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2)
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

                Row(
                  children: [
                    Expanded(
                        child: Divider(
                            thickness: 1, color: Colors.grey.shade300)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '- OR Continue with -',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: screenWidth * 0.035,
                        ),
                      ),
                    ),
                    Expanded(
                        child: Divider(
                            thickness: 1, color: Colors.grey.shade300)),
                  ],
                ),

                SizedBox(height: screenHeight * 0.03),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSocialButton(FontAwesomeIcons.google),
                    SizedBox(width: screenWidth * 0.06),
                    _buildSocialButton(FontAwesomeIcons.facebookF),
                  ],
                ),

                SizedBox(height: screenHeight * 0.04),

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
                          MaterialPageRoute(
                              builder: (_) => const LoginPage()),
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

                SizedBox(height: screenHeight * 0.04),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String hint, IconData icon,
      String? Function(String?)? validator,
      {TextInputType? keyboardType, List<TextInputFormatter>? formatters}) {
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
            keyboardType: keyboardType,
            inputFormatters: formatters,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.grey.shade600),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade600),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(vertical: screenHeight * 0.025),
              errorStyle: const TextStyle(height: 0),
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
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPasswordField(TextEditingController controller, String hint,
      String? Function(String?)? validator, bool isMainPassword) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final obscure =
        isMainPassword ? _obscurePassword : _obscureConfirmPassword;

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
            obscureText: obscure,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.lock, color: Colors.grey.shade600),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade600),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(vertical: screenHeight * 0.025),
              errorStyle: const TextStyle(height: 0),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey.shade600,
                ),
                onPressed: () {
                  setState(() {
                    if (isMainPassword) {
                      _obscurePassword = !_obscurePassword;
                    } else {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    }
                  });
                },
              ),
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
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ],
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
