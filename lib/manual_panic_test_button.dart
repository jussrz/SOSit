// ============================================================
// TEMPORARY TEST: Manual Panic Alert Button
// ============================================================
// Add this to your home screen or settings page to test
// the flow without needing BLE to work
// ============================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManualPanicTestButton extends StatelessWidget {
  const ManualPanicTestButton({super.key});

  Future<void> _triggerTestAlert(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ User not authenticated')),
      );
      return;
    }

    try {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔔 Triggering test alert...'),
          duration: Duration(seconds: 2),
        ),
      );

      debugPrint('📝 TEST: Inserting panic alert into database...');

      // Step 1: Insert into panic_alerts
      final panicAlertResponse = await supabase
          .from('panic_alerts')
          .insert({
            'user_id': userId,
            'alert_level': 'CRITICAL',
            'timestamp': DateTime.now().toIso8601String(),
            'latitude': 7.1907,
            'longitude': 125.4553,
            'location': 'TEST LOCATION - Davao City',
            'battery_level': 85,
            'acknowledged': false,
          })
          .select()
          .single();

      final panicAlertId = panicAlertResponse['id'] as int;
      debugPrint('✅ TEST: Panic alert created with ID: $panicAlertId');

      // Step 2: Call Edge Function
      debugPrint('🚀 TEST: Calling Edge Function...');
      final response = await supabase.functions.invoke(
        'send-parent-alerts',
        body: {
          'alert': {
            'id': 'test-${DateTime.now().millisecondsSinceEpoch}',
            'panic_alert_id': panicAlertId,
            'user_id': userId,
            'alert_type': 'CRITICAL',
            'timestamp': DateTime.now().toIso8601String(),
            'latitude': 7.1907,
            'longitude': 125.4553,
            'address': 'TEST LOCATION - Davao City',
            'battery_level': 85,
            'status': 'ACTIVE',
          }
        },
      );

      debugPrint('📬 TEST: Edge Function Response: ${response.data}');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Test alert sent!\nPanic Alert ID: $panicAlertId\n'
              'Check parent device for notification!',
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ TEST: Error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _triggerTestAlert(context),
      icon: const Icon(Icons.bug_report),
      label: const Text('TEST: Trigger Panic Alert'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}

// ============================================================
// HOW TO USE:
// ============================================================
// Add this widget to your home screen or settings page:
//
// const ManualPanicTestButton(),
//
// This will create a button that manually triggers the alert
// without needing BLE to work. Use this to test the complete flow.
// ============================================================
