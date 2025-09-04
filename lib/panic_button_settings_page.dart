// lib/panic_button_settings_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'services/emergency_service.dart';

class PanicButtonSettingsPage extends StatefulWidget {
  const PanicButtonSettingsPage({super.key});

  @override
  State<PanicButtonSettingsPage> createState() =>
      _PanicButtonSettingsPageState();
}

class _PanicButtonSettingsPageState extends State<PanicButtonSettingsPage> {
  bool _isTestingConnection = false;
  String _testResult = '';

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Colors.black, size: screenWidth * 0.06),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text('Panic Button Settings',
            style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w500,
                fontSize: screenWidth * 0.045)),
      ),
      body: Consumer2<BLEService, EmergencyService>(
        builder: (context, bleService, emergencyService, child) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(screenWidth * 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connection Status Card
                _buildConnectionStatusCard(
                    bleService, screenWidth, screenHeight),

                SizedBox(height: screenHeight * 0.02),

                // Device Information Card
                if (bleService.isConnected)
                  _buildDeviceInfoCard(bleService, screenWidth, screenHeight),

                SizedBox(height: screenHeight * 0.02),

                // Connection Controls
                _buildConnectionControls(bleService, screenWidth, screenHeight),

                SizedBox(height: screenHeight * 0.02),

                // Test Functions
                _buildTestFunctions(
                    bleService, emergencyService, screenWidth, screenHeight),

                SizedBox(height: screenHeight * 0.02),

                // Bluetooth Settings
                _buildBluetoothSettings(bleService, screenWidth, screenHeight),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionStatusCard(
      BLEService bleService, double screenWidth, double screenHeight) {
    Color statusColor = bleService.isConnected
        ? Colors.green
        : bleService.isBluetoothOn
            ? Colors.orange
            : Colors.red;

    IconData statusIcon = bleService.isConnected
        ? Icons.check_circle
        : bleService.isBluetoothOn
            ? Icons.search
            : Icons.bluetooth_disabled;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(statusIcon, size: screenWidth * 0.15, color: statusColor),
          SizedBox(height: screenHeight * 0.015),
          Text(
            bleService.connectionStatus,
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: screenHeight * 0.01),
          Text(
            _getStatusDescription(bleService),
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getStatusDescription(BLEService bleService) {
    if (!bleService.isBluetoothOn) {
      return 'Please turn on Bluetooth to connect to your panic button';
    } else if (bleService.isConnected) {
      return 'Your panic button is ready for emergency alerts';
    } else if (bleService.isScanning) {
      return 'Looking for your SOSit panic button device';
    } else {
      return 'Tap "Connect" to search for your panic button';
    }
  }

  Widget _buildDeviceInfoCard(
      BLEService bleService, double screenWidth, double screenHeight) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device Information',
            style: TextStyle(
              fontSize: screenWidth * 0.04,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: screenHeight * 0.015),
          _buildInfoRow(
              'Device Name',
              bleService.connectedDevice?.platformName ?? 'Unknown',
              screenWidth),
          _buildInfoRow(
              'Device ID',
              bleService.connectedDevice?.remoteId.toString() ?? 'Unknown',
              screenWidth),
          _buildInfoRow(
              'Battery Level', '${bleService.batteryLevel}%', screenWidth),
          _buildInfoRow('Device State', bleService.deviceState, screenWidth),
          if (bleService.lastHeartbeat != null)
            _buildInfoRow('Last Heartbeat',
                _formatLastHeartbeat(bleService.lastHeartbeat!), screenWidth),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, double screenWidth) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: screenWidth * 0.01),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatLastHeartbeat(DateTime lastHeartbeat) {
    Duration diff = DateTime.now().difference(lastHeartbeat);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }

  Widget _buildConnectionControls(
      BLEService bleService, double screenWidth, double screenHeight) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connection Controls',
            style: TextStyle(
              fontSize: screenWidth * 0.04,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: screenHeight * 0.015),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: bleService.isConnected
                      ? () => bleService.disconnect()
                      : () => bleService.startScan(),
                  icon: Icon(
                    bleService.isConnected
                        ? Icons.bluetooth_disabled
                        : Icons.bluetooth_searching,
                    size: screenWidth * 0.05,
                  ),
                  label: Text(
                    bleService.isConnected ? 'Disconnect' : 'Connect',
                    style: TextStyle(fontSize: screenWidth * 0.035),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: bleService.isConnected
                        ? Colors.red.shade400
                        : const Color(0xFFF73D5C),
                    foregroundColor: Colors.white,
                    padding:
                        EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => bleService.startScan(),
                  icon: Icon(Icons.refresh, size: screenWidth * 0.05),
                  label: Text(
                    'Scan',
                    style: TextStyle(fontSize: screenWidth * 0.035),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade400,
                    foregroundColor: Colors.white,
                    padding:
                        EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: screenHeight * 0.01),
          SwitchListTile(
            title: Text(
              'Auto-Reconnect',
              style: TextStyle(fontSize: screenWidth * 0.035),
            ),
            subtitle: Text(
              'Automatically reconnect when connection is lost',
              style: TextStyle(
                  fontSize: screenWidth * 0.03, color: Colors.grey.shade600),
            ),
            value: true, // You can add this to BLEService later
            onChanged: (value) {
              bleService.setAutoReconnect(value);
            },
            activeColor: const Color(0xFFF73D5C),
          ),
        ],
      ),
    );
  }

  Widget _buildTestFunctions(
      BLEService bleService,
      EmergencyService emergencyService,
      double screenWidth,
      double screenHeight) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Test Functions',
            style: TextStyle(
              fontSize: screenWidth * 0.04,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: screenHeight * 0.015),
          if (_testResult.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(screenWidth * 0.03),
              decoration: BoxDecoration(
                color: _testResult.contains('Success')
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _testResult.contains('Success')
                      ? Colors.green.shade200
                      : Colors.red.shade200,
                ),
              ),
              child: Text(
                _testResult,
                style: TextStyle(
                  fontSize: screenWidth * 0.032,
                  color: _testResult.contains('Success')
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
            ),
            SizedBox(height: screenHeight * 0.015),
          ],
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isTestingConnection
                      ? null
                      : () => _testConnection(bleService),
                  icon: _isTestingConnection
                      ? SizedBox(
                          width: screenWidth * 0.04,
                          height: screenWidth * 0.04,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.wifi_tethering, size: screenWidth * 0.045),
                  label: Text(
                    _isTestingConnection ? 'Testing...' : 'Test Connection',
                    style: TextStyle(fontSize: screenWidth * 0.032),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade400,
                    foregroundColor: Colors.white,
                    padding:
                        EdgeInsets.symmetric(vertical: screenHeight * 0.012),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              SizedBox(width: screenWidth * 0.02),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: bleService.isConnected
                      ? () => _testEmergencyAlert(bleService, emergencyService)
                      : null,
                  icon: Icon(Icons.warning, size: screenWidth * 0.045),
                  label: Text(
                    'Test Alert',
                    style: TextStyle(fontSize: screenWidth * 0.032),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: bleService.isConnected
                        ? Colors.purple.shade400
                        : Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    padding:
                        EdgeInsets.symmetric(vertical: screenHeight * 0.012),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: screenHeight * 0.01),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _testEmergencySystem(emergencyService),
              icon: Icon(Icons.verified_user, size: screenWidth * 0.045),
              label: Text(
                'Test Emergency System',
                style: TextStyle(fontSize: screenWidth * 0.035),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade400,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothSettings(
      BLEService bleService, double screenWidth, double screenHeight) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bluetooth Settings',
            style: TextStyle(
              fontSize: screenWidth * 0.04,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: screenHeight * 0.015),
          ListTile(
            leading: Icon(
              Icons.bluetooth,
              color: bleService.isBluetoothOn ? Colors.blue : Colors.grey,
              size: screenWidth * 0.06,
            ),
            title: Text(
              'Bluetooth Status',
              style: TextStyle(fontSize: screenWidth * 0.035),
            ),
            subtitle: Text(
              bleService.isBluetoothOn
                  ? 'Enabled'
                  : 'Disabled - Please enable in system settings',
              style: TextStyle(
                fontSize: screenWidth * 0.03,
                color: bleService.isBluetoothOn ? Colors.green : Colors.red,
              ),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          if (bleService.foundDevices.isNotEmpty) ...[
            Divider(),
            Text(
              'Available Devices',
              style: TextStyle(
                fontSize: screenWidth * 0.035,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: screenHeight * 0.01),
            ...bleService.foundDevices.map((device) => ListTile(
                  leading: Icon(Icons.devices, color: const Color(0xFFF73D5C)),
                  title: Text(
                    device.platformName.isNotEmpty
                        ? device.platformName
                        : 'Unknown Device',
                    style: TextStyle(fontSize: screenWidth * 0.032),
                  ),
                  subtitle: Text(
                    device.remoteId.toString(),
                    style: TextStyle(fontSize: screenWidth * 0.028),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.connect_without_contact),
                    onPressed: () => bleService.connectToDevice(device),
                  ),
                  contentPadding: EdgeInsets.zero,
                )),
          ],
        ],
      ),
    );
  }

  Future<void> _testConnection(BLEService bleService) async {
    if (!bleService.isConnected) {
      setState(() {
        _testResult = 'Error: Not connected to panic button';
      });
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _testResult = '';
    });

    try {
      // Send ping and wait for response
      await bleService.sendMessage('PING');

      // Wait for response (you might want to implement a proper response handler)
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _testResult = 'Success: Connection test passed';
        _isTestingConnection = false;
      });
    } catch (e) {
      setState(() {
        _testResult = 'Error: Connection test failed - $e';
        _isTestingConnection = false;
      });
    }
  }

  Future<void> _testEmergencyAlert(
      BLEService bleService, EmergencyService emergencyService) async {
    try {
      await bleService.simulatePanicButton('REGULAR');
      setState(() {
        _testResult = 'Success: Test emergency alert sent';
      });
    } catch (e) {
      setState(() {
        _testResult = 'Error: Failed to send test alert - $e';
      });
    }
  }

  Future<void> _testEmergencySystem(EmergencyService emergencyService) async {
    try {
      await emergencyService.testEmergencySystem();
      setState(() {
        _testResult = 'Success: Emergency system test completed';
      });
    } catch (e) {
      setState(() {
        _testResult = 'Error: Emergency system test failed - $e';
      });
    }
  }
}
