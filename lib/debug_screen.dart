import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';

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
      body: Consumer<BLEService>(
        builder: (context, bleService, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      ],
                    ),
                  ),
                ),

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
                          '• Service UUID: ${BLEService.SERVICE_UUID}\n'
                          '• Alert Characteristic: ${BLEService.ALERT_CHAR_UUID}',
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
}
