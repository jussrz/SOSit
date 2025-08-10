import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginDetailsPage extends StatefulWidget {
  const LoginDetailsPage({super.key});

  @override
  State<LoginDetailsPage> createState() => _LoginDetailsPageState();
}

class _LoginDetailsPageState extends State<LoginDetailsPage> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentEmail();
  }

  void _loadCurrentEmail() {
    final user = supabase.auth.currentUser;
    if (user?.email != null) {
      _emailController.text = user!.email!;
    }
  }

  Future<void> _updateEmail() async {
    if (_emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a new email address')),
      );
      return;
    }

    if (_emailController.text.trim() == supabase.auth.currentUser?.email) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New email must be different from current email')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await supabase.auth.updateUser(
        UserAttributes(email: _emailController.text.trim()),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email update request sent! Please check your new email to confirm the change.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePassword() async {
    if (_currentPasswordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your current password')),
      );
      return;
    }

    if (_newPasswordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a new password')),
      );
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match')),
      );
      return;
    }

    if (_newPasswordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // First verify current password by attempting to sign in
      final email = supabase.auth.currentUser?.email;
      if (email != null) {
        await supabase.auth.signInWithPassword(
          email: email,
          password: _currentPasswordController.text.trim(),
        );

        // If sign in successful, update password
        await supabase.auth.updateUser(
          UserAttributes(password: _newPasswordController.text.trim()),
        );

        // Clear password fields
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to update password';
        if (e.toString().contains('Invalid login credentials')) {
          errorMessage = 'Current password is incorrect';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text('Login Details', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w500)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Email Section
              const Text('Email Address', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black)),
              const SizedBox(height: 16),
              
              _buildTextField('New Email Address', _emailController, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF73D5C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isLoading ? null : _updateEmail,
                  child: _isLoading 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Update Email', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),

              const SizedBox(height: 32),

              // Password Section
              const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black)),
              const SizedBox(height: 16),

              _buildPasswordField('Current Password', _currentPasswordController, _obscureCurrentPassword, () {
                setState(() => _obscureCurrentPassword = !_obscureCurrentPassword);
              }),
              const SizedBox(height: 12),

              _buildPasswordField('New Password', _newPasswordController, _obscureNewPassword, () {
                setState(() => _obscureNewPassword = !_obscureNewPassword);
              }),
              const SizedBox(height: 12),

              _buildPasswordField('Confirm New Password', _confirmPasswordController, _obscureConfirmPassword, () {
                setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
              }),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF73D5C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isLoading ? null : _updatePassword,
                  child: _isLoading 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Update Password', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        cursorColor: const Color(0xFFF73D5C),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
        style: const TextStyle(fontSize: 16, color: Colors.black),
      ),
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller, bool obscure, VoidCallback toggleObscure) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        cursorColor: const Color(0xFFF73D5C),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey,
            ),
            onPressed: toggleObscure,
          ),
        ),
        style: const TextStyle(fontSize: 16, color: Colors.black),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
