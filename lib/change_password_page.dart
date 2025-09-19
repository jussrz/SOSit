import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _submitted = false;
  String? _currentPasswordError;
  String? _newPasswordError;
  String? _confirmPasswordError;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    setState(() {
      _submitted = true;
      _currentPasswordError = null;
      _newPasswordError = null;
      _confirmPasswordError = null;
    });

    // Manual validation
    if (_currentPasswordController.text.trim().isEmpty) {
      setState(() {
        _currentPasswordError = 'Current password is required';
      });
      return;
    }

    if (_newPasswordController.text.trim().isEmpty) {
      setState(() {
        _newPasswordError = 'New password is required';
      });
      return;
    }

    if (_newPasswordController.text.length < 6) {
      setState(() {
        _newPasswordError = 'Password must be at least 6 characters';
      });
      return;
    }

    if (_confirmPasswordController.text.trim().isEmpty) {
      setState(() {
        _confirmPasswordError = 'Please confirm your password';
      });
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() {
        _confirmPasswordError = 'Passwords do not match';
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // First, verify current password by attempting to sign in
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser?.email == null) {
        throw Exception('No user logged in');
      }

      // Verify current password
      await Supabase.instance.client.auth.signInWithPassword(
        email: currentUser!.email!,
        password: _currentPasswordController.text.trim(),
      );

      // If verification successful, update password
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordController.text.trim()),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          String errorString = e.toString().toLowerCase();

          if (errorString.contains('invalid login credentials') ||
              errorString.contains('invalid_credentials') ||
              errorString.contains('wrong password')) {
            _currentPasswordError = 'Current password is incorrect';
          } else if (errorString.contains('weak password') ||
              errorString.contains('password too short')) {
            _newPasswordError =
                'Password is too weak. Use at least 6 characters';
          } else if (errorString.contains('same password')) {
            _newPasswordError =
                'New password must be different from current password';
          } else if (errorString.contains('no user logged in')) {
            _currentPasswordError = 'Please log in again to change password';
          } else {
            _currentPasswordError = 'Failed to update password';
          }
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

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Colors.black, size: screenWidth * 0.06),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          'Change Password',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: screenWidth * 0.045,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(screenWidth * 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: screenHeight * 0.01),

              // Main content card
              Container(
                padding: EdgeInsets.all(screenWidth * 0.06),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current Password Field
                    Text(
                      'Current Password',
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade50,
                      ),
                      child: TextFormField(
                        controller: _currentPasswordController,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.lock_outline, 
                              color: const Color(0xFFF73D5C).withOpacity(0.7)),
                          hintText: 'Enter current password',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: screenHeight * 0.020),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureCurrentPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(() =>
                                _obscureCurrentPassword = !_obscureCurrentPassword),
                          ),
                        ),
                        obscureText: _obscureCurrentPassword,
                      ),
                    ),
                    if (_submitted && _currentPasswordError != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Text(
                          _currentPasswordError!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),

                    SizedBox(height: screenHeight * 0.025),

                    // New Password Field
                    Text(
                      'New Password',
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade50,
                      ),
                      child: TextFormField(
                        controller: _newPasswordController,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.lock, 
                              color: const Color(0xFFF73D5C).withOpacity(0.7)),
                          hintText: 'Enter new password',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: screenHeight * 0.020),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureNewPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(
                                () => _obscureNewPassword = !_obscureNewPassword),
                          ),
                        ),
                        obscureText: _obscureNewPassword,
                      ),
                    ),
                    if (_submitted && _newPasswordError != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Text(
                          _newPasswordError!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),

                    SizedBox(height: screenHeight * 0.025),

                    // Confirm Password Field
                    Text(
                      'Confirm New Password',
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade50,
                      ),
                      child: TextFormField(
                        controller: _confirmPasswordController,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.lock, 
                              color: const Color(0xFFF73D5C).withOpacity(0.7)),
                          hintText: 'Confirm new password',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: screenHeight * 0.020),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(() =>
                                _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                        obscureText: _obscureConfirmPassword,
                      ),
                    ),
                    if (_submitted && _confirmPasswordError != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4),
                        child: Text(
                          _confirmPasswordError!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),

                    SizedBox(height: screenHeight * 0.04),

                    // Update Button
                    SizedBox(
                      width: double.infinity,
                      height: screenHeight * 0.06,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF73D5C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          elevation: 2,
                        ),
                        onPressed: _isLoading ? null : _changePassword,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                'Update Password',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: screenWidth * 0.045,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),

                    SizedBox(height: screenHeight * 0.02),

                    // Security tip
                    Container(
                      padding: EdgeInsets.all(screenWidth * 0.04),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF73D5C).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFF73D5C).withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.security,
                            color: const Color(0xFFF73D5C),
                            size: screenWidth * 0.05,
                          ),
                          SizedBox(width: screenWidth * 0.03),
                          Expanded(
                            child: Text(
                              'Use a strong password with at least 6 characters for better security.',
                              style: TextStyle(
                                fontSize: screenWidth * 0.032,
                                color: const Color(0xFFF73D5C),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
