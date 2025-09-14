import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashboard_router.dart';
import 'home_screen.dart';

class MainAppWrapper extends StatefulWidget {
  const MainAppWrapper({super.key});

  @override
  State<MainAppWrapper> createState() => _MainAppWrapperState();
}

class _MainAppWrapperState extends State<MainAppWrapper> {
  bool _isLoading = true;
  Widget? _currentScreen;

  @override
  void initState() {
    super.initState();
    _determineInitialScreen();

    // Listen for auth state changes to re-route when needed
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        _determineInitialScreen();
      }
    });
  }

  Future<void> _determineInitialScreen() async {
    setState(() => _isLoading = true);

    try {
      final screen = await DashboardRouter.getAppropriateScreen();

      if (mounted) {
        setState(() {
          _currentScreen = screen;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error determining initial screen: $e');
      if (mounted) {
        setState(() {
          _currentScreen = const HomeScreen(); // Fallback
          _isLoading = false;
        });
      }
    }
  }

  /// Call this method when user's emergency contact status might have changed
  Future<void> refreshDashboard() async {
    await _determineInitialScreen();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Color(0xFFF73D5C),
              ),
              SizedBox(height: 16),
              Text(
                'Loading dashboard...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _currentScreen ?? const HomeScreen();
  }
}
