import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'services/emergency_service.dart';
import 'signup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://ctsnpupbpcznwbbtqdln.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN0c25wdXBicGN6bndiYnRxZGxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDgzNjMxMjksImV4cCI6MjA2MzkzOTEyOX0.qerDMur3ms75KP2ahzQV6znO2Ri4NLtOAZorUf6soag',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BLEService()),
        ChangeNotifierProvider(create: (_) => EmergencyService()),
        // Connect BLE alerts to Emergency service
        ChangeNotifierProxyProvider2<BLEService, EmergencyService,
            EmergencyAlertHandler>(
          create: (_) => EmergencyAlertHandler(),
          update: (_, bleService, emergencyService, handler) {
            handler?.updateServices(bleService, emergencyService);
            return handler!;
          },
        ),
      ],
      child: MaterialApp(
        title: 'SOSit App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          fontFamily: 'Roboto',
        ),
        home: const SignupPage(),
      ),
    );
  }
}

// Handler to connect BLE service alerts to Emergency service
class EmergencyAlertHandler extends ChangeNotifier {
  BLEService? _bleService;
  EmergencyService? _emergencyService;
  String _lastProcessedAlert = "";

  void updateServices(
      BLEService bleService, EmergencyService emergencyService) {
    // Remove old listener if exists
    if (_bleService != null) {
      _bleService!.removeListener(_handleBLEUpdate);
    }

    _bleService = bleService;
    _emergencyService = emergencyService;

    // Listen for BLE alerts and forward to emergency service
    bleService.addListener(_handleBLEUpdate);
  }

  void _handleBLEUpdate() {
    if (_bleService?.lastAlert.isNotEmpty == true &&
        _emergencyService != null) {
      // Parse the alert from BLE service
      String alert = _bleService!.lastAlert;

      // Avoid processing the same alert multiple times
      if (alert == _lastProcessedAlert) return;
      _lastProcessedAlert = alert;

      // Extract alert type from the alert string
      if (alert.toUpperCase().contains('REGULAR')) {
        _emergencyService!.handleEmergencyAlert('REGULAR', null);
      } else if (alert.toUpperCase().contains('CRITICAL')) {
        _emergencyService!.handleEmergencyAlert('CRITICAL', null);
      } else if (alert.toUpperCase().contains('CHECKIN')) {
        _emergencyService!.handleEmergencyAlert('CHECKIN', null);
      } else if (alert.toUpperCase().contains('CANCEL')) {
        _emergencyService!.handleEmergencyAlert('CANCEL', null);
      }
    }
  }

  @override
  void dispose() {
    _bleService?.removeListener(_handleBLEUpdate);
    super.dispose();
  }
}
