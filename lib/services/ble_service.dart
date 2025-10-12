// lib/services/ble_service.dart - Debug Version for ESP32-S3
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BLEService extends ChangeNotifier {
  // ESP32 Constants - Matching your ESP32 code exactly
  static const String serviceUuid = "12345678-1234-5678-9abc-123456789abc";
  static const String statusCharUuid = "12345678-1234-5678-9abc-123456789abd";
  static const String alertCharUuid = "12345678-1234-5678-9abc-123456789abe";
  static const String batteryCharUuid = "12345678-1234-5678-9abc-123456789abf";
  static const String deviceName = "SOSit!Button";

  // Private variables
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _statusCharacteristic;
  BluetoothCharacteristic? _alertCharacteristic;
  BluetoothCharacteristic? _batteryCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _statusSubscription;
  StreamSubscription<List<int>>? _alertSubscription;
  StreamSubscription<List<int>>? _batterySubscription;
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

  // Alert callback
  Function(String, Map<String, dynamic>)? _onAlertReceived;

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
            'Bonded device: ${device.platformName} (${device.remoteId})',
          );
          if (device.platformName.contains("SOSit") ||
              device.platformName.contains("ESP32") ||
              device.platformName == deviceName) {
            _isPaired = true;
            _deviceId = device.remoteId.toString();
            _addDebugLog(
              'Found potential panic button: ${device.platformName}',
            );
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
      _statusCharacteristic = null;
      _alertCharacteristic = null;
      _batteryCharacteristic = null;
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

      bool allGranted = statuses.values.every(
        (status) =>
            status == PermissionStatus.granted ||
            status == PermissionStatus.limited,
      );

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
              : result.advertisementData.advName;

          _addDebugLog(
            'Found device: $deviceName (${result.device.remoteId}) RSSI: ${result.rssi}',
          );

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

            if (!_foundDevices.any(
              (d) => d.remoteId == result.device.remoteId,
            )) {
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
            'Scan completed. Found ${_foundDevices.length} target devices, ${_scannedDevices.length} total devices',
          );

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
          'Checking ${bondedDevices.length} bonded devices for ESP32...',
        );

        for (var device in bondedDevices) {
          String deviceName = device.platformName;
          _addDebugLog('Bonded device: $deviceName (${device.remoteId})');

          if (_isTargetDevice(deviceName, null)) {
            _addDebugLog('Found bonded ESP32 device: $deviceName');

            // Add to found devices and try to connect
            if (!_foundDevices.any((d) => d.remoteId == device.remoteId)) {
              _foundDevices.add(device);
              _updateConnectionStatus(
                "Bonded Panic Button Found - Connecting...",
              );

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
    if (deviceName == deviceName) {
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
        result.advertisementData.serviceUuids.any(
          (uuid) => uuid.toString().toLowerCase().contains(
                serviceUuid.toLowerCase(),
              ),
        )) {
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
        'Connecting to: ${device.platformName} (${device.remoteId})',
      );
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

      // Look for our panic button service
      BluetoothService? panicService;
      BluetoothCharacteristic? statusChar;
      BluetoothCharacteristic? alertChar;
      BluetoothCharacteristic? batteryChar;

      // Find the panic button service
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() ==
            serviceUuid.toLowerCase()) {
          panicService = service;
          _addDebugLog('Found panic button service: ${service.uuid}');
          break;
        }
      }

      if (panicService != null) {
        // Find all characteristics
        for (var characteristic in panicService.characteristics) {
          String charUUID = characteristic.uuid.toString().toLowerCase();

          if (charUUID == statusCharUuid.toLowerCase()) {
            statusChar = characteristic;
            _addDebugLog('Found status characteristic: ${characteristic.uuid}');
          } else if (charUUID == alertCharUuid.toLowerCase()) {
            alertChar = characteristic;
            _addDebugLog('Found alert characteristic: ${characteristic.uuid}');
          } else if (charUUID == batteryCharUuid.toLowerCase()) {
            batteryChar = characteristic;
            _addDebugLog(
              'Found battery characteristic: ${characteristic.uuid}',
            );
          }
        }
      } else {
        // Fallback to any writable characteristic for basic connectivity
        _addDebugLog(
          'Panic button service not found, looking for any writable characteristic...',
        );
        for (var service in services) {
          for (var char in service.characteristics) {
            if (char.properties.write ||
                char.properties.writeWithoutResponse ||
                char.properties.notify) {
              statusChar = char;
              _addDebugLog(
                'Found fallback writable characteristic: ${char.uuid}',
              );
              break;
            }
          }
          if (statusChar != null) break;
        }
      }

      // Set up the connection
      _connectedDevice = device;
      _statusCharacteristic = statusChar;
      _alertCharacteristic = alertChar;
      _batteryCharacteristic = batteryChar;
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

      // Set up characteristic notifications
      await _setupCharacteristicNotifications();

      _startHeartbeat();
      _addDebugLog('Successfully connected to panic button');

      // Set up fallback callback if none exists
      if (_onAlertReceived == null) {
        _addDebugLog('No callback set, setting up emergency callback directly');
        // Set up a direct emergency service callback
        setAlertCallback((alertType, alertData) {
          debugPrint('🚨 DIRECT EMERGENCY ALERT: $alertType');
          debugPrint('🚨 Alert data: $alertData');
          // Direct emergency handling
          _handleDirectEmergencyAlert(alertType, alertData);
        });
        _addDebugLog('Direct emergency callback set up successfully');
      }

      notifyListeners();
    } catch (e) {
      _addDebugLog('Connection failed: $e');
      _isConnected = false;
      _isConnecting = false;
      _connectedDevice = null;
      _statusCharacteristic = null;
      _alertCharacteristic = null;
      _batteryCharacteristic = null;
      _updateConnectionStatus("Connection Failed: ${e.toString()}");

      if (_autoReconnect) {
        Timer(const Duration(seconds: 5), () => _startAutoScanning());
      }

      notifyListeners();
    }
  }

  // Set up notifications for all characteristics
  Future<void> _setupCharacteristicNotifications() async {
    // Status characteristic
    if (_statusCharacteristic != null &&
        _statusCharacteristic!.properties.notify) {
      try {
        await _statusCharacteristic!.setNotifyValue(true);
        _statusSubscription = _statusCharacteristic!.lastValueStream.listen(
          _handleStatusUpdate,
          onError: (error) =>
              _addDebugLog('Status characteristic error: $error'),
        );
        _addDebugLog('Status notifications enabled');
      } catch (e) {
        _addDebugLog('Could not enable status notifications: $e');
      }
    }

    // Alert characteristic
    if (_alertCharacteristic != null &&
        _alertCharacteristic!.properties.notify) {
      try {
        await _alertCharacteristic!.setNotifyValue(true);
        _alertSubscription = _alertCharacteristic!.lastValueStream.listen(
          _handleAlertUpdate,
          onError: (error) =>
              _addDebugLog('Alert characteristic error: $error'),
        );
        _addDebugLog('Alert notifications enabled');
      } catch (e) {
        _addDebugLog('Could not enable alert notifications: $e');
      }
    }

    // Battery characteristic
    if (_batteryCharacteristic != null &&
        _batteryCharacteristic!.properties.notify) {
      try {
        await _batteryCharacteristic!.setNotifyValue(true);
        _batterySubscription = _batteryCharacteristic!.lastValueStream.listen(
          _handleBatteryUpdate,
          onError: (error) =>
              _addDebugLog('Battery characteristic error: $error'),
        );
        _addDebugLog('Battery notifications enabled');
      } catch (e) {
        _addDebugLog('Could not enable battery notifications: $e');
      }
    }
  }

  // Handle status updates from ESP32
  void _handleStatusUpdate(List<int> data) {
    try {
      String statusMessage = utf8.decode(data);
      _addDebugLog('Status update: $statusMessage');
      _deviceState = statusMessage;
      _lastHeartbeat = DateTime.now();
      notifyListeners();
    } catch (e) {
      _addDebugLog('Error handling status update: $e');
    }
  }

  // Handle alert updates from ESP32
  void _handleAlertUpdate(List<int> data) {
    try {
      String alertMessage = utf8.decode(data);
      _addDebugLog('ALERT RECEIVED: "$alertMessage" (${data.length} bytes)');
      _addDebugLog('Raw bytes: ${data.toString()}');
      _lastHeartbeat = DateTime.now();

      // IMPORTANT: Trigger alert in the Flutter app
      if (alertMessage != "none" && alertMessage.isNotEmpty) {
        _addDebugLog('Processing alert: $alertMessage');

        // Convert to uppercase for consistency
        String normalizedAlert = alertMessage.toUpperCase();
        _addDebugLog('Normalized alert: $normalizedAlert');

        if (_onAlertReceived != null) {
          _addDebugLog('Calling alert callback...');
          Map<String, dynamic> alertData = {
            'level': normalizedAlert,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'device_id': _deviceId,
            'battery': _batteryLevel,
          };
          _onAlertReceived!(normalizedAlert, alertData);
          _addDebugLog('Alert callback completed');
        } else {
          _addDebugLog('ERROR: No alert callback set!');
        }
      } else {
        _addDebugLog('Alert ignored: "$alertMessage" (none or empty)');
      }
      _lastAlert = '$alertMessage at ${DateTime.now().toString()}';
      notifyListeners();
    } catch (e) {
      _addDebugLog('Error handling alert update: $e');
    }
  }

  // Handle battery updates from ESP32
  void _handleBatteryUpdate(List<int> data) {
    try {
      if (data.isNotEmpty) {
        _batteryLevel = data[0]; // Battery sent as single byte
        _addDebugLog('Battery update: $_batteryLevel%');
        _lastHeartbeat = DateTime.now();
        notifyListeners();
      }
    } catch (e) {
      _addDebugLog('Error handling battery update: $e');
    }
  }

  void _handleDirectEmergencyAlert(
    String alertType,
    Map<String, dynamic> alertData,
  ) {
    try {
      debugPrint('🏥 Handling direct emergency alert: $alertType');

      // Basic emergency response logic
      switch (alertType.toUpperCase()) {
        case 'REGULAR':
          debugPrint('⚠️ REGULAR emergency alert triggered!');
          // Handle regular emergency
          break;
        case 'CRITICAL':
          debugPrint('🚨 CRITICAL emergency alert triggered!');
          // Handle critical emergency
          break;
        case 'CANCEL':
          debugPrint('❌ Emergency alert cancelled');
          // Handle cancellation
          break;
        case 'CHECKIN':
          debugPrint('✅ Check-in received');
          // Handle check-in
          break;
        default:
          debugPrint('❓ Unknown alert type: $alertType');
      }

      // Update last alert for other listeners
      _lastAlert = '$alertType at ${DateTime.now().toString()}';
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error handling direct emergency alert: $e');
    }
  }

  // Set alert callback for external handling
  void setAlertCallback(Function(String, Map<String, dynamic>) callback) {
    _onAlertReceived = callback;
    _addDebugLog('Alert callback set successfully');
  }

  void _handleConnectionStateChange(BluetoothConnectionState state) {
    _addDebugLog('Connection state changed: $state');

    if (state == BluetoothConnectionState.disconnected) {
      _isConnected = false;
      _isConnecting = false;
      _connectedDevice = null;
      _statusCharacteristic = null;
      _alertCharacteristic = null;
      _batteryCharacteristic = null;
      _updateConnectionStatus("Panic Button Disconnected");
      _stopTimers();

      if (_autoReconnect && _isBluetoothOn) {
        Timer(const Duration(seconds: 3), () => _startAutoScanning());
      }

      notifyListeners();
    }
  }

  Future<void> sendMessage(String message) async {
    if (!_isConnected || _statusCharacteristic == null) {
      _addDebugLog('Cannot send message - not connected');
      return;
    }

    try {
      List<int> bytes = utf8.encode(message);

      // Try different write methods based on characteristic properties
      if (_statusCharacteristic!.properties.writeWithoutResponse) {
        await _statusCharacteristic!.write(bytes, withoutResponse: true);
        _addDebugLog('Sent (no response): $message');
      } else if (_statusCharacteristic!.properties.write) {
        await _statusCharacteristic!.write(bytes);
        _addDebugLog('Sent (with response): $message');
      } else {
        _addDebugLog('Characteristic does not support writing');
        return;
      }
    } catch (e) {
      _addDebugLog('Error sending message: $e');

      // Try to find a different writable characteristic
      if (_connectedDevice != null) {
        _addDebugLog(
          'Attempting to find alternative writable characteristic...',
        );
        await _findAlternativeCharacteristic();
      }
    }
  }

  Future<void> _findAlternativeCharacteristic() async {
    if (_connectedDevice == null) return;

    try {
      List<BluetoothService> services =
          await _connectedDevice!.discoverServices();

      for (var service in services) {
        for (var char in service.characteristics) {
          if ((char.properties.write || char.properties.writeWithoutResponse) &&
              char.uuid.toString() != _statusCharacteristic?.uuid.toString()) {
            _statusCharacteristic = char;
            _addDebugLog(
              'Switched to alternative characteristic: ${char.uuid}',
            );
            return;
          }
        }
      }
    } catch (e) {
      _addDebugLog('Error finding alternative characteristic: $e');
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

    // Simulate alert directly using our callback
    if (_onAlertReceived != null) {
      Map<String, dynamic> alertData = {
        'type': 'ALERT',
        'level': alertType,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'battery': _batteryLevel,
      };
      _onAlertReceived!(alertType, alertData);
    }

    _lastAlert = '$alertType at ${DateTime.now().toString()}';
    notifyListeners();
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
    _statusSubscription?.cancel();
    _alertSubscription?.cancel();
    _batterySubscription?.cancel();
    _bluetoothStateSubscription?.cancel();
    _stopTimers();
    super.dispose();
  }
}
