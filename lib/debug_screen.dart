import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'services/emergency_service.dart';

class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Debug'),
        backgroundColor: const Color(0xFFF73D5C),
        foregroundColor: Colors.white,
      ),
      body: Consumer2<BLEService, EmergencyService>(
        builder: (context, bleService, emergencyService, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Button Pattern Information Card
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'ESP32 Button Patterns',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Colors.blue.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildPatternInfo(
                            '2 Presses',
                            'Regular Alert',
                            'Sends alert to emergency contacts after 30 seconds',
                            Colors.orange),
                        _buildPatternInfo('3 Presses', 'Cancel Alert',
                            'Cancels any active emergency alert', Colors.green),
                        _buildPatternInfo(
                            'Long Press (3s)',
                            'Critical Alert',
                            'Immediate emergency - sends alert right away!',
                            Colors.red),
                        const SizedBox(height: 8),
                        Text(
                          'Make sure your ESP32 sends: "2", "3", "LONG", "DOUBLE", "TRIPLE", etc.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Connection Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connection Status',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        _buildStatusRow('Bluetooth',
                            bleService.isBluetoothOn ? 'ON' : 'OFF'),
                        _buildStatusRow(
                            'Connected', bleService.isConnected ? 'YES' : 'NO'),
                        _buildStatusRow(
                            'Scanning', bleService.isScanning ? 'YES' : 'NO'),
                        _buildStatusRow('Status', bleService.connectionStatus),
                        if (bleService.isConnected) ...[
                          _buildStatusRow(
                              'Device',
                              bleService.connectedDevice?.platformName ??
                                  'Unknown'),
                          _buildStatusRow(
                              'Battery', '${bleService.batteryLevel}%'),
                          _buildStatusRow(
                              'Signal', '${bleService.signalStrength} dBm'),
                        ],
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Last Alert Received',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildStatusRow(
                            'Last Alert',
                            bleService.lastAlert.isNotEmpty
                                ? bleService.lastAlert
                                : 'None'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Control Buttons
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Controls',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton(
                              onPressed: bleService.isScanning
                                  ? null
                                  : () => bleService.startScan(),
                              child: const Text('Start Scan'),
                            ),
                            ElevatedButton(
                              onPressed: bleService.isScanning
                                  ? () => bleService.stopScan()
                                  : null,
                              child: const Text('Stop Scan'),
                            ),
                            ElevatedButton(
                              onPressed: bleService.isConnected
                                  ? () => bleService.disconnect()
                                  : null,
                              child: const Text('Disconnect'),
                            ),
                            ElevatedButton(
                              onPressed: bleService.isConnected
                                  ? () =>
                                      bleService.simulatePanicButton('REGULAR')
                                  : null,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange),
                              child: const Text('Test Regular'),
                            ),
                            ElevatedButton(
                              onPressed: bleService.isConnected
                                  ? () =>
                                      bleService.simulatePanicButton('CRITICAL')
                                  : null,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red),
                              child: const Text('Test Critical'),
                            ),
                            ElevatedButton(
                              onPressed: bleService.isConnected
                                  ? () =>
                                      bleService.simulatePanicButton('CHECKIN')
                                  : null,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue),
                              child: const Text('Test Check-in'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // New ESP32 Button Pattern Tests
                        Text('ESP32 Button Pattern Tests:',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton(
                              onPressed: bleService.isConnected
                                  ? () => bleService.simulateButtonPress('2')
                                  : null,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange),
                              child: const Text('2 Presses (Regular)'),
                            ),
                            ElevatedButton(
                              onPressed: bleService.isConnected
                                  ? () => bleService.simulateButtonPress('3')
                                  : null,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green),
                              child: const Text('3 Presses (Cancel)'),
                            ),
                            ElevatedButton(
                              onPressed: bleService.isConnected
                                  ? () => bleService.simulateButtonPress('LONG')
                                  : null,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red),
                              child: const Text('Long Press (Critical)'),
                            ),
                            ElevatedButton(
                              onPressed: bleService.isConnected
                                  ? () =>
                                      bleService.simulateButtonPress('DOUBLE')
                                  : null,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade300),
                              child: const Text('Test "DOUBLE"'),
                            ),
                            ElevatedButton(
                              onPressed: bleService.isConnected
                                  ? () =>
                                      bleService.simulateButtonPress('TRIPLE')
                                  : null,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade300),
                              child: const Text('Test "TRIPLE"'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // ESP32 Exact Message Tests
                        Text('ESP32 Exact Messages:',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.purple.shade800,
                                  fontWeight: FontWeight.bold,
                                )),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // Direct Callback Test
                            ElevatedButton(
                              onPressed: () {
                                print(
                                    '🔥 DEBUG: Manual callback test button pressed');
                                // Test the callback chain through BLE service
                                bleService.testCallback();
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple.shade600),
                              child: const Text('Test Callback Chain'),
                            ),

                            // Push Notification Test Buttons
                            ElevatedButton(
                              onPressed: () {
                                emergencyService
                                    .handleEmergencyAlert('REGULAR', {
                                  'test': true,
                                  'timestamp':
                                      DateTime.now().millisecondsSinceEpoch,
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade600),
                              child: const Text('Test Regular Push'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                emergencyService
                                    .handleEmergencyAlert('CRITICAL', {
                                  'test': true,
                                  'timestamp':
                                      DateTime.now().millisecondsSinceEpoch,
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade600),
                              child: const Text('Test Critical Push'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                emergencyService
                                    .handleEmergencyAlert('CANCEL', {
                                  'test': true,
                                  'timestamp':
                                      DateTime.now().millisecondsSinceEpoch,
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600),
                              child: const Text('Test Cancel Push'),
                            ),
                            const SizedBox(
                                width: double.infinity), // Force new row

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton(
                                  onPressed: bleService.isConnected
                                      ? () => bleService
                                          .simulateButtonPress('regular')
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange.shade600),
                                  child: const Text('ESP32: "regular"'),
                                ),
                                ElevatedButton(
                                  onPressed: bleService.isConnected
                                      ? () => bleService
                                          .simulateButtonPress('critical')
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade600),
                                  child: const Text('ESP32: "critical"'),
                                ),
                                ElevatedButton(
                                  onPressed: bleService.isConnected
                                      ? () => bleService
                                          .simulateButtonPress('cancel')
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade600),
                                  child: const Text('ESP32: "cancel"'),
                                ),
                              ],
                            ),
                          ], // Close Wrap children
                        ), // Close Wrap
                      ], // Close Column children
                    ), // Close Padding
                  ), // Close Card
                ), // Close Expanded

                const SizedBox(height: 16),

                // Scanned Devices
                if (bleService.scannedDevices.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scanned Devices (${bleService.scannedDevices.length})',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 200,
                            child: ListView.builder(
                              itemCount: bleService.scannedDevices.length,
                              itemBuilder: (context, index) {
                                final device = bleService.scannedDevices[index];
                                final deviceName = device['name'].toString();
                                final isEsp32 =
                                    deviceName.toUpperCase().contains('ESP32');

                                return Card(
                                  color: isEsp32 ? Colors.green.shade50 : null,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: ListTile(
                                    dense: true,
                                    title: Text(
                                      deviceName.isEmpty
                                          ? 'Unknown Device'
                                          : deviceName,
                                      style: TextStyle(
                                        fontWeight: isEsp32
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isEsp32
                                            ? Colors.green.shade800
                                            : null,
                                      ),
                                    ),
                                    subtitle: Text(
                                      device['id'],
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text('${device['rssi']} dBm'),
                                        if (isEsp32)
                                          const Icon(Icons.star,
                                              color: Colors.green, size: 16),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // Debug Log
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Debug Log',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                bleService.debugLog.clear();
                              },
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 300,
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: bleService.debugLog.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No debug messages yet',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              : ListView.builder(
                                  reverse: true,
                                  itemCount: bleService.debugLog.length,
                                  itemBuilder: (context, index) {
                                    final log = bleService.debugLog[
                                        bleService.debugLog.length - 1 - index];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 1),
                                      child: Text(
                                        log,
                                        style: TextStyle(
                                          color: log.contains('ERROR') ||
                                                  log.contains('Error')
                                              ? Colors.red.shade300
                                              : log.contains('Found') ||
                                                      log.contains('Connected')
                                                  ? Colors.green.shade300
                                                  : Colors.white,
                                          fontSize: 11,
                                          fontFamily: 'Courier',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Connection Info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Technical Info',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Looking for:\n'
                          '• Device Name: "SOSit!Button"\n'
                          '• Or any ESP32 device\n'
                          '• Service UUID: ${BLEService.serviceUuid}\n'
                          '• Alert Characteristic: ${BLEService.alertCharUuid}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: _getStatusColor(label, value),
                fontWeight: _shouldBoldStatus(label, value)
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String label, String value) {
    if (label == 'Bluetooth' && value == 'ON') return Colors.green;
    if (label == 'Bluetooth' && value == 'OFF') return Colors.red;
    if (label == 'Connected' && value == 'YES') return Colors.green;
    if (label == 'Connected' && value == 'NO') return Colors.red;
    if (label == 'Scanning' && value == 'YES') return Colors.orange;
    if (value.contains('Connected')) return Colors.green;
    if (value.contains('Error') || value.contains('Failed')) return Colors.red;
    return Colors.black87;
  }

  bool _shouldBoldStatus(String label, String value) {
    return (label == 'Connected' && value == 'YES') ||
        (label == 'Bluetooth' && value == 'OFF') ||
        value.contains('Error') ||
        value.contains('Connected');
  }

  Widget _buildPatternInfo(
      String pattern, String alertType, String description, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            margin: const EdgeInsets.only(top: 4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      pattern,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '→ $alertType',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
