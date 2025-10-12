import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/ble_service.dart';
import 'services/emergency_service.dart';
import 'splash_screen.dart';
import 'notifications/firebase_messaging_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔹 Initialize Supabase
  await Supabase.initialize(
    url: 'https://ctsnpupbpcznwbbtqdln.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN0c25wdXBicGN6bndiYnRxZGxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDgzNjMxMjksImV4cCI6MjA2MzkzOTEyOX0.qerDMur3ms75KP2ahzQV6znO2Ri4NLtOAZorUf6soag',
  );

  // Initialize Firebase Messaging (FCM)
  try {
    // Ensure Firebase core is initialized before using any Firebase APIs
    await Firebase.initializeApp();
    await FirebaseMessagingService.initialize();
  } catch (e) {
    debugPrint('⚠️ FirebaseMessaging init error: $e');
  }

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
        home: const SplashScreen(),
      ),
    );
  }
}

// Handler to connect BLE service alerts to Emergency service
class EmergencyAlertHandler extends ChangeNotifier {
  BLEService? _bleService;
  EmergencyService? _emergencyService;
  String _lastProcessedAlert = "";
  bool _callbackSetup = false;

  void updateServices(
      BLEService bleService, EmergencyService emergencyService) {
    debugPrint('🔄 EmergencyAlertHandler: updateServices called');

    // Remove old listener if exists
    if (_bleService != null) {
      _bleService!.removeListener(_handleBLEUpdate);
    }

    _bleService = bleService;
    _emergencyService = emergencyService;

    // Set up direct callback for ESP32 alerts
    debugPrint('🔄 EmergencyAlertHandler: Setting up alert callback...');
    _setupCallback();
    debugPrint('🔄 EmergencyAlertHandler: Alert callback setup complete');

    // Also listen for BLE state changes and forward to emergency service
    bleService.addListener(_handleBLEUpdate);
  }

  void _setupCallback() {
    if (_bleService != null && _emergencyService != null && !_callbackSetup) {
      _bleService!.setAlertCallback(_handleDirectAlert);
      _callbackSetup = true;
      debugPrint('✅ EmergencyAlertHandler: Callback successfully set up');
    }
  }

  // Try to set up callback even if called directly
  void ensureCallbackSetup(
      BLEService? bleService, EmergencyService? emergencyService) {
    if (bleService != null && emergencyService != null && !_callbackSetup) {
      _bleService = bleService;
      _emergencyService = emergencyService;
      _setupCallback();
      debugPrint('🔧 EmergencyAlertHandler: Manual callback setup completed');
    }
  }

  // Direct callback handler for ESP32 alerts
  void _handleDirectAlert(String alertType, Map<String, dynamic> alertData) {
    if (_emergencyService != null) {
      debugPrint('🚨 PROCESSING DIRECT ESP32 ALERT: $alertType');
      debugPrint('🚨 Alert data: $alertData');
      _emergencyService!.handleEmergencyAlert(alertType, alertData);
      debugPrint('🚨 Emergency service called successfully');
    } else {
      debugPrint('❌ ERROR: Emergency service is null!');
    }
  }

  void _handleBLEUpdate() {
    if (_bleService?.lastAlert.isNotEmpty == true &&
        _emergencyService != null) {
      String alert = _bleService!.lastAlert;

      // Avoid processing the same alert multiple times
      if (alert == _lastProcessedAlert) return;
      _lastProcessedAlert = alert;

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
