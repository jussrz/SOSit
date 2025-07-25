import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_selection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://ctsnpupbpcznwbbtqdln.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN0c25wdXBicGN6bndiYnRxZGxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDgzNjMxMjksImV4cCI6MjA2MzkzOTEyOX0.qerDMur3ms75KP2ahzQV6znO2Ri4NLtOAZorUf6soag',
  );
  runApp(SOSitApp());
}

class SOSitApp extends StatelessWidget {
  const SOSitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SOSit',
      debugShowCheckedModeBanner: false,
      home: LandingPage(),
    );
  }
}

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => AuthSelectionPage()),
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Image.asset('assets/sositlogo.png'),
          ),
        ),
      ),
    );
  }
}
