// lib/ble_test_page.dart - Enhanced BLE Testing Page
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';

class BLETestPage extends StatefulWidget {
  const BLETestPage({super.key});

  @override
  State<BLETestPage> createState() => _BLETestPageState();
}

class _BLETestPageState extends State<BLETestPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panic Button Detection'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Consumer<BLEService>(
        builder: (context, bleService, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connection Status Card
                Card(
                  color: bleService.isConnected
                      ? Colors.green[100]
                      : Colors.red[100],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Panic Button Status',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          bleService.connectionStatus,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: bleService.isConnected
                                ? Colors.green[800]
                                : Colors.red[800],
                          ),
                        ),
                        if (bleService.isConnected) ...[
                          const SizedBox(height: 8),
                          Text(
                              'Device: ${bleService.connectedDevice?.platformName ?? "Unknown"}'),
                          Text('Device ID: ${bleService.deviceId}'),
                          Text('Battery: ${bleService.batteryLevel}%'),
                          if (bleService.lastHeartbeat != null)
                            Text(
                                'Last Contact: ${_formatTime(bleService.lastHeartbeat!)}'),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Control Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(
                            bleService.isScanning ? Icons.stop : Icons.search),
                        label: Text(bleService.isScanning
                            ? 'Stop Scan'
                            : 'Scan for Devices'),
                        onPressed: bleService.isScanning
                            ? () => bleService.stopScan()
                            : () => bleService.startScan(timeoutSeconds: 30),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: bleService.isScanning
                              ? Colors.orange
                              : Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (bleService.isConnected)
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.link_off),
                          label: const Text('Disconnect'),
                          onPressed: () => bleService.disconnect(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // Alert Testing Section - NEWLY ADDED
                if (bleService.isConnected) ...[
                  Card(
                    color: Colors.orange[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alert Testing',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Simulate different panic button alerts:',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton(
                                onPressed: () =>
                                    bleService.simulatePanicButton('REGULAR'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Regular Alert'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    bleService.simulatePanicButton('CRITICAL'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Critical Alert'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    bleService.simulatePanicButton('CHECKIN'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Check-In'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    bleService.simulatePanicButton('CANCEL'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Cancel Alert'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // System Status
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'System Status',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _buildStatusRow(
                            'Bluetooth',
                            bleService.isBluetoothOn ? 'ON' : 'OFF',
                            bleService.isBluetoothOn
                                ? Colors.green
                                : Colors.red),
                        _buildStatusRow(
                            'Scanning',
                            bleService.isScanning ? 'YES' : 'NO',
                            bleService.isScanning
                                ? Colors.orange
                                : Colors.grey),
                        _buildStatusRow(
                            'Connected',
                            bleService.isConnected ? 'YES' : 'NO',
                            bleService.isConnected
                                ? Colors.green
                                : Colors.grey),
                        _buildStatusRow(
                            'Auto-Reconnect',
                            bleService.autoReconnect ? 'ON' : 'OFF',
                            bleService.autoReconnect
                                ? Colors.blue
                                : Colors.grey),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Scanned Devices
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detected Devices (${bleService.scannedDevices.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: bleService.scannedDevices.isEmpty
                                ? const Center(
                                    child:
                                        Text('No devices found. Try scanning.'))
                                : ListView.builder(
                                    itemCount: bleService.scannedDevices.length,
                                    itemBuilder: (context, index) {
                                      final device =
                                          bleService.scannedDevices[index];
                                      final isPanicButton =
                                          _isPotentialPanicButton(
                                              device['name']);

                                      return Card(
                                        color: isPanicButton
                                            ? Colors.green[50]
                                            : null,
                                        child: ListTile(
                                          leading: Icon(
                                            isPanicButton
                                                ? Icons.warning
                                                : Icons.bluetooth,
                                            color: isPanicButton
                                                ? Colors.red
                                                : Colors.blue,
                                          ),
                                          title: Text(
                                            device['name'].isEmpty
                                                ? 'Unknown Device'
                                                : device['name'],
                                            style: TextStyle(
                                              fontWeight: isPanicButton
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text('ID: ${device['id']}'),
                                              Text(
                                                  'RSSI: ${device['rssi']} dBm'),
                                            ],
                                          ),
                                          trailing: isPanicButton
                                              ? ElevatedButton(
                                                  onPressed: () =>
                                                      _connectToDevice(
                                                          bleService,
                                                          device['device']),
                                                  child: const Text('Connect'),
                                                )
                                              : null,
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
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

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  bool _isPotentialPanicButton(String name) {
    final panicKeywords = [
      'panic',
      'emergency',
      'sos',
      'esp32',
      'button',
      'alert',
      'sosit'
    ];
    final lowercaseName = name.toLowerCase();
    return panicKeywords.any((keyword) => lowercaseName.contains(keyword));
  }

  void _connectToDevice(BLEService bleService, dynamic device) {
    // This would connect to a specific device
    // Implementation depends on the BLEService API
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}
