import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OtpPage extends StatefulWidget {
  final String email;
  final String password;
  final Map<String, dynamic> extraData;

  const OtpPage({
    super.key,
    required this.email,
    required this.password,
    required this.extraData,
  });

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final _otpCtrl = TextEditingController();
  final _sb = Supabase.instance.client;
  bool _loading = false;

  Future<void> _verifyOtp() async {
    setState(() => _loading = true);
    try {
      final res = await _sb.auth.verifyOtp(
        type: OtpType.email, // 📌 verify email
        token: _otpCtrl.text.trim(),
        email: widget.email,
      );

      if (res.user == null) {
        throw Exception("OTP verification failed.");
      }

      // ✅ Insert user profile after verification
      await _sb.from('users').insert({
        'id': res.user!.id,
        'role': widget.extraData['role'],
        'first_name': widget.extraData['first_name'],
        'middle_name': widget.extraData['middle_name'],
        'last_name': widget.extraData['last_name'],
        'birthdate': widget.extraData['birthdate'],
        'phone': widget.extraData['phone'],
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Signup successful!")),
        );
        Navigator.pop(context); // go back or move to home
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("OTP error: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify Email")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("Enter the OTP sent to your email"),
            TextField(
              controller: _otpCtrl,
              decoration: const InputDecoration(labelText: "OTP Code"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _verifyOtp,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text("Verify"),
            )
          ],
        ),
      ),
    );
  }
}
