import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showSplash = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFEEEE),
        body: Center(
          child: SvgPicture.asset(
            'assets/sositsplash.svg',
            width: 718.61,
            height: 718.61,
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      return const LoginPage();
    }
  }
}
    


