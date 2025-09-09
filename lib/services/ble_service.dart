// lib/services/ble_service.dart - Debug Version for ESP32-S3
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BLEService extends ChangeNotifier {
  // ESP32 Constants - Made more flexible for detection
  static const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String CHARACTERISTIC_UUID =
      "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String DEVICE_NAME = "SOSit!Button";

  // Private variables
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _characteristicSubscription;
  StreamSubscription<BluetoothAdapterState>? _bluetoothStateSubscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  // State properties
  bool _isScanning = false;
  bool _isConnected = false;
  bool _isBluetoothOn = false;
  bool _isPaired = false;
  bool _isConnecting = false;
  String _deviceState = "DISCONNECTED";
  int _batteryLevel = 100;
  final List<BluetoothDevice> _foundDevices = [];
  String _lastAlert = "";
  String _connectionStatus = "Panic Button Not Connected";
  bool _autoReconnect = true;
  DateTime? _lastHeartbeat;
  String _deviceId = "";
  int _signalStrength = 0;

  // Debug information
  final List<String> _debugLog = [];
  final List<Map<String, dynamic>> _scannedDevices = [];

  // Enhanced getters
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isBluetoothOn => _isBluetoothOn;
  bool get isPaired => _isPaired;
  bool get isConnecting => _isConnecting;
  String get deviceState => _deviceState;
  int get batteryLevel => _batteryLevel;
  List<BluetoothDevice> get foundDevices => _foundDevices;
  String get lastAlert => _lastAlert;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  String get connectionStatus => _connectionStatus;
  DateTime? get lastHeartbeat => _lastHeartbeat;
  String get deviceId => _deviceId;
  int get signalStrength => _signalStrength;
  bool get autoReconnect => _autoReconnect;
  List<String> get debugLog => _debugLog;
  List<Map<String, dynamic>> get scannedDevices => _scannedDevices;

  BLEService() {
    _initialize();
  }

  void _addDebugLog(String message) {
    _debugLog.add("${DateTime.now().toString().substring(11, 19)}: $message");
    if (_debugLog.length > 50) {
      _debugLog.removeAt(0);
    }
    debugPrint('BLE DEBUG: $message');
    notifyListeners();
  }

  Future<void> _initialize() async {
    _addDebugLog('Initializing Enhanced BLE Service...');

    // Check initial Bluetooth state
    await _checkBluetoothState();

    // Listen to Bluetooth state changes
    _bluetoothStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      _updateBluetoothState(state);
    });

    // Check for previously paired devices
    await _checkPairedDevices();

    // Load saved device and try to reconnect
    await _loadSavedDevice();

    // Start automatic scanning if Bluetooth is on
    if (_isBluetoothOn) {
      _startAutoScanning();
    }

    _addDebugLog('Enhanced BLE Service initialized');
  }

  Future<void> _checkBluetoothState() async {
    try {
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      _updateBluetoothState(state);
    } catch (e) {
      _addDebugLog('Error checking Bluetooth state: $e');
      _isBluetoothOn = false;
      _updateConnectionStatus("Bluetooth Error");
    }
  }

  Future<void> _checkPairedDevices() async {
    try {
      if (Platform.isAndroid) {
        List<BluetoothDevice> bondedDevices =
            await FlutterBluePlus.bondedDevices;
        _addDebugLog('Found ${bondedDevices.length} bonded devices');

        for (var device in bondedDevices) {
          _addDebugLog(
              'Bonded device: ${device.platformName} (${device.remoteId})');
          if (device.platformName.contains("SOSit") ||
              device.platformName.contains("ESP32") ||
              device.platformName == DEVICE_NAME) {
            _isPaired = true;
            _deviceId = device.remoteId.toString();
            _addDebugLog(
                'Found potential panic button: ${device.platformName}');
          }
        }
      }
    } catch (e) {
      _addDebugLog('Error checking paired devices: $e');
    }
    notifyListeners();
  }

  void _updateBluetoothState(BluetoothAdapterState state) {
    bool wasOn = _isBluetoothOn;
    _isBluetoothOn = state == BluetoothAdapterState.on;

    _addDebugLog('Bluetooth state: $state');

    if (!_isBluetoothOn) {
      _updateConnectionStatus("Bluetooth is OFF");
      _isConnected = false;
      _isConnecting = false;
      _isScanning = false;
      _connectedDevice = null;
      _characteristic = null;
      _stopTimers();
    } else if (!wasOn && _isBluetoothOn) {
      _updateConnectionStatus("Bluetooth ON - Initializing...");
      _checkPairedDevices().then((_) {
        if (_isPaired) {
          _updateConnectionStatus("Paired Device Found - Connecting...");
        } else {
          _updateConnectionStatus("Bluetooth ON - Searching...");
        }
        _startAutoScanning();
      });
    }

    notifyListeners();
  }

  void _updateConnectionStatus(String status) {
    _connectionStatus = status;
    _addDebugLog('Status: $status');
    notifyListeners();
  }

  Future<void> _startAutoScanning() async {
    if (!_isBluetoothOn || _isConnected || _isScanning) return;

    _addDebugLog('Starting auto-scan for panic button...');
    _updateConnectionStatus("Searching for Panic Button...");

    await _requestPermissions();
    await startScan();
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
      ].request();

      _addDebugLog('Permission statuses: $statuses');

      bool allGranted = statuses.values.every((status) =>
          status == PermissionStatus.granted ||
          status == PermissionStatus.limited);

      if (!allGranted) {
        _updateConnectionStatus("Bluetooth Permissions Required");
        return false;
      }
    }
    return true;
  }

  Future<void> startScan({int timeoutSeconds = 20}) async {
    if (!_isBluetoothOn) {
      _addDebugLog('Cannot scan - Bluetooth is off');
      _updateConnectionStatus("Bluetooth is OFF");
      return;
    }

    if (_isScanning) {
      _addDebugLog('Already scanning');
      return;
    }

    try {
      _isScanning = true;
      _foundDevices.clear();
      _scannedDevices.clear();
      _updateConnectionStatus("Scanning for devices...");
      notifyListeners();

      _addDebugLog('Starting BLE scan...');

      // Start broad scan to detect ANY ESP32 device
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: timeoutSeconds),
        // No service filter to detect all devices
      );

      // Also try to connect to bonded devices
      await _checkBondedDevicesForConnection();

      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          String deviceName = result.device.platformName.isNotEmpty
              ? result.device.platformName
              : result.advertisementData.localName;

          _addDebugLog(
              'Found device: $deviceName (${result.device.remoteId}) RSSI: ${result.rssi}');

          // Store all scanned devices for debugging
          _scannedDevices.add({
            'name': deviceName,
            'id': result.device.remoteId.toString(),
            'rssi': result.rssi,
            'services': result.advertisementData.serviceUuids
                .map((e) => e.toString())
                .toList(),
          });

          // Check if it's our panic button by various criteria
          bool isTargetDevice = _isTargetDevice(deviceName, result);

          if (isTargetDevice) {
            _addDebugLog('Target device identified: $deviceName');

            if (!_foundDevices
                .any((d) => d.remoteId == result.device.remoteId)) {
              _foundDevices.add(result.device);
              _signalStrength = result.rssi;
              _updateConnectionStatus("Panic Button Found - Connecting...");

              // Auto-connect to the first found device
              connectToDevice(result.device);
            }
          }
        }
        notifyListeners();
      });

      // Handle scan completion
      Timer(Duration(seconds: timeoutSeconds), () {
        if (_isScanning) {
          stopScan();
          _addDebugLog(
              'Scan completed. Found ${_foundDevices.length} target devices, ${_scannedDevices.length} total devices');

          if (!_isConnected && _foundDevices.isEmpty) {
            _updateConnectionStatus("Panic Button Not Found");
            if (_autoReconnect) {
              Timer(const Duration(seconds: 10), () => _startAutoScanning());
            }
          }
        }
      });
    } catch (e) {
      _addDebugLog('Scan error: $e');
      _isScanning = false;
      _updateConnectionStatus("Scan Error: ${e.toString()}");
      notifyListeners();
    }
  }

  Future<void> _checkBondedDevicesForConnection() async {
    if (Platform.isAndroid) {
      try {
        List<BluetoothDevice> bondedDevices =
            await FlutterBluePlus.bondedDevices;
        _addDebugLog(
            'Checking ${bondedDevices.length} bonded devices for ESP32...');

        for (var device in bondedDevices) {
          String deviceName = device.platformName;
          _addDebugLog('Bonded device: $deviceName (${device.remoteId})');

          if (_isTargetDevice(deviceName, null)) {
            _addDebugLog('Found bonded ESP32 device: $deviceName');

            // Add to found devices and try to connect
            if (!_foundDevices.any((d) => d.remoteId == device.remoteId)) {
              _foundDevices.add(device);
              _updateConnectionStatus(
                  "Bonded Panic Button Found - Connecting...");

              // Try to connect to bonded device
              connectToDevice(device);
              return; // Connect to first found bonded device
            }
          }
        }
      } catch (e) {
        _addDebugLog('Error checking bonded devices: $e');
      }
    }
  }

  bool _isTargetDevice(String deviceName, ScanResult? result) {
    // Check by exact name
    if (deviceName == DEVICE_NAME) {
      _addDebugLog('Found device by exact name match');
      return true;
    }

    // Check if it's any ESP32 device
    if (deviceName.toUpperCase().contains('ESP32')) {
      _addDebugLog('Found ESP32 device: $deviceName');
      return true;
    }

    // Check if it contains "SOSit"
    if (deviceName.toUpperCase().contains('SOSIT')) {
      _addDebugLog('Found SOSit device: $deviceName');
      return true;
    }

    // Check for ESP32-S3 specific patterns
    if (deviceName.toUpperCase().contains('ESP32-S3') ||
        deviceName.toUpperCase().contains('ESP32S3')) {
      _addDebugLog('Found ESP32-S3 device: $deviceName');
      return true;
    }

    // Check if device name is empty but has our service UUID
    if (result != null &&
        result.advertisementData.serviceUuids.any((uuid) => uuid
            .toString()
            .toLowerCase()
            .contains(SERVICE_UUID.toLowerCase()))) {
      _addDebugLog('Found device with our service UUID');
      return true;
    }

    // Check for common ESP32 default names
    List<String> esp32Names = [
      'ESP32',
      'ESP_',
      'ESPRESSIF',
      'ESP32_',
      'ESP32-',
      'ARDUINO',
    ];

    for (String name in esp32Names) {
      if (deviceName.toUpperCase().contains(name)) {
        _addDebugLog('Found ESP32-like device: $deviceName');
        return true;
      }
    }

    return false;
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;

    try {
      await FlutterBluePlus.stopScan();
      _isScanning = false;
      _addDebugLog('Scan stopped');
      notifyListeners();
    } catch (e) {
      _addDebugLog('Error stopping scan: $e');
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_isConnected || _isConnecting) {
      _addDebugLog('Already connected or connecting to a device');
      return;
    }

    try {
      _isConnecting = true;
      _addDebugLog(
          'Connecting to: ${device.platformName} (${device.remoteId})');
      _updateConnectionStatus("Connecting to ${device.platformName}...");

      await stopScan();

      // Connect with multiple attempts
      int maxRetries = 3;
      bool connected = false;

      for (int attempt = 1; attempt <= maxRetries && !connected; attempt++) {
        try {
          _addDebugLog('Connection attempt $attempt/$maxRetries');
          await device.connect(timeout: const Duration(seconds: 15));
          connected = true;
          _addDebugLog('Connection successful!');
        } catch (e) {
          _addDebugLog('Connection attempt $attempt failed: $e');
          if (attempt < maxRetries) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }

      if (!connected) {
        throw Exception('Failed to connect after $maxRetries attempts');
      }

      // Discover services
      _addDebugLog('Discovering services...');
      List<BluetoothService> services = await device.discoverServices();
      _addDebugLog('Discovered ${services.length} services');

      // Log all services for debugging
      for (var service in services) {
        _addDebugLog('Service: ${service.uuid}');
        for (var char in service.characteristics) {
          _addDebugLog('  Characteristic: ${char.uuid}');
        }
      }

      // Try to find our service, but also look for any writable characteristic
      BluetoothService? targetService;
      BluetoothCharacteristic? targetCharacteristic;

      // First, try to find our specific service
      for (var service in services) {
        if (service.uuid
            .toString()
            .toLowerCase()
            .contains(SERVICE_UUID.toLowerCase())) {
          targetService = service;
          _addDebugLog('Found our target service');
          break;
        }
      }

      // If we found our service, look for our characteristic
      if (targetService != null) {
        for (var characteristic in targetService.characteristics) {
          if (characteristic.uuid
              .toString()
              .toLowerCase()
              .contains(CHARACTERISTIC_UUID.toLowerCase())) {
            targetCharacteristic = characteristic;
            _addDebugLog('Found our target characteristic');
            break;
          }
        }
      } else {
        // If we can't find our specific service, look for any service with writable characteristics
        _addDebugLog(
            'Target service not found, looking for any writable characteristic...');
        for (var service in services) {
          for (var char in service.characteristics) {
            if (char.properties.write ||
                char.properties.writeWithoutResponse ||
                char.properties.notify) {
              targetService = service;
              targetCharacteristic = char;
              _addDebugLog('Found writable characteristic: ${char.uuid}');
              break;
            }
          }
          if (targetCharacteristic != null) break;
        }
      }

      // Set up the connection
      _connectedDevice = device;
      _characteristic = targetCharacteristic;
      _isConnected = true;
      _isConnecting = false;
      _isPaired = true;
      _deviceId = device.remoteId.toString();
      _updateConnectionStatus("Connected to ${device.platformName}");

      await _saveConnectedDevice(device);

      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((state) {
        _handleConnectionStateChange(state);
      });

      // Try to enable notifications if possible
      if (targetCharacteristic != null &&
          targetCharacteristic.properties.notify) {
        try {
          await targetCharacteristic.setNotifyValue(true);
          _addDebugLog('Notifications enabled');

          _characteristicSubscription =
              targetCharacteristic.lastValueStream.listen(
            _handleIncomingData,
            onError: (error) {
              _addDebugLog('Characteristic error: $error');
            },
          );
        } catch (e) {
          _addDebugLog('Could not enable notifications: $e');
        }
      }

      // Try to send initial status request if we can write
      if (targetCharacteristic != null &&
          (targetCharacteristic.properties.write ||
              targetCharacteristic.properties.writeWithoutResponse)) {
        try {
          await sendMessage("STATUS");
        } catch (e) {
          _addDebugLog('Could not send initial message: $e');
        }
      }

      _startHeartbeat();
      _addDebugLog('Successfully connected to panic button');
      notifyListeners();
    } catch (e) {
      _addDebugLog('Connection failed: $e');
      _isConnected = false;
      _isConnecting = false;
      _connectedDevice = null;
      _characteristic = null;
      _updateConnectionStatus("Connection Failed: ${e.toString()}");

      if (_autoReconnect) {
        Timer(const Duration(seconds: 5), () => _startAutoScanning());
      }

      notifyListeners();
    }
  }

  void _handleConnectionStateChange(BluetoothConnectionState state) {
    _addDebugLog('Connection state changed: $state');

    if (state == BluetoothConnectionState.disconnected) {
      _isConnected = false;
      _isConnecting = false;
      _connectedDevice = null;
      _characteristic = null;
      _updateConnectionStatus("Panic Button Disconnected");
      _stopTimers();

      if (_autoReconnect && _isBluetoothOn) {
        Timer(const Duration(seconds: 3), () => _startAutoScanning());
      }

      notifyListeners();
    }
  }

  void _handleIncomingData(List<int> data) {
    try {
      String message = utf8.decode(data);
      _addDebugLog('Received: $message');
      _lastHeartbeat = DateTime.now();

      // Parse different message types
      if (message.startsWith('STATE:')) {
        _deviceState = message.substring(6);
      } else if (message.startsWith('{') && message.contains('ALERT')) {
        Map<String, dynamic> alertData = json.decode(message);
        _handleAlert(alertData);
      } else if (message.startsWith('{') && message.contains('BATTERY')) {
        Map<String, dynamic> batteryData = json.decode(message);
        _batteryLevel = batteryData['value'] ?? _batteryLevel;
      } else if (message == 'BTN_PRESS') {
        _addDebugLog('Button pressed detected!');
        // Simulate an alert for testing
        _simulateButtonAlert('REGULAR');
      } else if (message == 'BTN_RELEASE') {
        _addDebugLog('Button released');
      } else if (message == 'PONG') {
        _addDebugLog('Heartbeat response received');
      }

      notifyListeners();
    } catch (e) {
      _addDebugLog('Error handling incoming data: $e');
    }
  }

  void _simulateButtonAlert(String alertType) {
    Map<String, dynamic> alertData = {
      'type': 'ALERT',
      'level': alertType,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'battery': _batteryLevel,
    };
    _handleAlert(alertData);
  }

  void _handleAlert(Map<String, dynamic> alertData) {
    String alertType = alertData['level'] ?? 'UNKNOWN';
    int timestamp = alertData['timestamp'] ?? 0;
    int battery = alertData['battery'] ?? _batteryLevel;

    _lastAlert = '$alertType at ${DateTime.now().toString()}';
    _batteryLevel = battery;

    _addDebugLog('ALERT: $alertType (Battery: $battery%)');

    // Send acknowledgment back if possible
    sendMessage("ACK");

    notifyListeners();
  }

  Future<void> sendMessage(String message) async {
    if (!_isConnected || _characteristic == null) {
      _addDebugLog('Cannot send message - not connected');
      return;
    }

    try {
      List<int> bytes = utf8.encode(message);
      if (_characteristic!.properties.write) {
        await _characteristic!.write(bytes);
      } else if (_characteristic!.properties.writeWithoutResponse) {
        await _characteristic!.write(bytes, withoutResponse: true);
      }
      _addDebugLog('Sent: $message');
    } catch (e) {
      _addDebugLog('Error sending message: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        sendMessage("PING");
      } else {
        timer.cancel();
      }
    });
  }

  void _stopTimers() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
  }

  Future<void> _saveConnectedDevice(BluetoothDevice device) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_panic_button_id', device.remoteId.toString());
      await prefs.setString('last_panic_button_name', device.platformName);
      _addDebugLog('Saved device for reconnection');
    } catch (e) {
      _addDebugLog('Error saving device: $e');
    }
  }

  Future<void> _loadSavedDevice() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('last_panic_button_id');

      if (_isBluetoothOn) {
        String? deviceId0;
        _addDebugLog('Looking for saved device: $deviceId');
      }
    } catch (e) {
      _addDebugLog('Error loading saved device: $e');
    }
  }

  Future<void> disconnect() async {
    _autoReconnect = false;
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        _addDebugLog('Manually disconnected');
      } catch (e) {
        _addDebugLog('Error disconnecting: $e');
      }
    }
    Timer(const Duration(seconds: 2), () {
      _autoReconnect = true;
    });
  }

  void setAutoReconnect(bool enabled) {
    _autoReconnect = enabled;
    _addDebugLog('Auto-reconnect: $enabled');
    notifyListeners();
  }

  // Test method to simulate panic button press
  Future<void> simulatePanicButton(String alertType) async {
    _addDebugLog('Simulating panic button: $alertType');
    _simulateButtonAlert(alertType);
  }

  Map<String, dynamic> getConnectionInfo() {
    return {
      'isBluetoothOn': _isBluetoothOn,
      'isConnected': _isConnected,
      'isPaired': _isPaired,
      'isScanning': _isScanning,
      'isConnecting': _isConnecting,
      'deviceName': _connectedDevice?.platformName ?? 'N/A',
      'deviceId': _deviceId,
      'batteryLevel': _batteryLevel,
      'signalStrength': _signalStrength,
      'lastHeartbeat': _lastHeartbeat?.toString() ?? 'N/A',
      'deviceState': _deviceState,
      'autoReconnect': _autoReconnect,
      'foundDevices': _foundDevices.length,
      'scannedDevices': _scannedDevices.length,
    };
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _characteristicSubscription?.cancel();
    _bluetoothStateSubscription?.cancel();
    _stopTimers();
    super.dispose();
  }
}
