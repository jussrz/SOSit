// lib/services/ble_service.dart - Enhanced Version
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BLEService extends ChangeNotifier {
  // ESP32 Constants - Must match your ESP32 code
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

  BLEService() {
    _initialize();
  }

  Future<void> _initialize() async {
    debugPrint('🔵 Initializing Enhanced BLE Service...');

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

    debugPrint('🔵 Enhanced BLE Service initialized');
  }

  Future<void> _checkBluetoothState() async {
    try {
      BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
      _updateBluetoothState(state);
    } catch (e) {
      debugPrint('❌ Error checking Bluetooth state: $e');
      _isBluetoothOn = false;
      _updateConnectionStatus("Bluetooth Error");
    }
  }

  Future<void> _checkPairedDevices() async {
    try {
      if (Platform.isAndroid) {
        // On Android, we can check bonded devices
        List<BluetoothDevice> bondedDevices =
            await FlutterBluePlus.bondedDevices;

        for (var device in bondedDevices) {
          if (device.platformName == DEVICE_NAME) {
            _isPaired = true;
            _deviceId = device.remoteId.toString();
            debugPrint('📱 Found paired SOSit device: ${device.platformName}');
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking paired devices: $e');
    }
    notifyListeners();
  }

  void _updateBluetoothState(BluetoothAdapterState state) {
    bool wasOn = _isBluetoothOn;
    _isBluetoothOn = state == BluetoothAdapterState.on;

    debugPrint('🔵 Bluetooth state: $state');

    if (!_isBluetoothOn) {
      _updateConnectionStatus("Bluetooth is OFF");
      _isConnected = false;
      _isConnecting = false;
      _isScanning = false;
      _connectedDevice = null;
      _characteristic = null;
      _stopTimers();
    } else if (!wasOn && _isBluetoothOn) {
      // Bluetooth just turned on
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
    debugPrint('📱 Status: $status');
    notifyListeners();
  }

  Future<void> _startAutoScanning() async {
    if (!_isBluetoothOn || _isConnected || _isScanning) return;

    debugPrint('🔍 Starting auto-scan for panic button...');
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

  Future<void> startScan({int timeoutSeconds = 15}) async {
    if (!_isBluetoothOn) {
      debugPrint('❌ Cannot scan - Bluetooth is off');
      _updateConnectionStatus("Bluetooth is OFF");
      return;
    }

    if (_isScanning) {
      debugPrint('⚠️ Already scanning');
      return;
    }

    try {
      _isScanning = true;
      _foundDevices.clear();
      _updateConnectionStatus("Scanning for devices...");
      notifyListeners();

      debugPrint('🔍 Starting BLE scan...');

      // Start scanning with and without service filter
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: timeoutSeconds),
        // Try without service filter first for broader detection
      );

      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          debugPrint(
              '📡 Found device: ${result.device.platformName} - ${result.device.remoteId}');

          // Check if it's our panic button by name or service
          bool isTargetDevice = false;

          if (result.device.platformName == DEVICE_NAME ||
              result.advertisementData.localName == DEVICE_NAME) {
            isTargetDevice = true;
          }

          // Also check for our service UUID in advertised services
          if (result.advertisementData.serviceUuids
              .contains(Guid(SERVICE_UUID))) {
            isTargetDevice = true;
          }

          if (isTargetDevice) {
            debugPrint('🎯 Found panic button: ${result.device.platformName}');

            if (!_foundDevices
                .any((d) => d.remoteId == result.device.remoteId)) {
              _foundDevices.add(result.device);
              _signalStrength = result.rssi;
              _updateConnectionStatus("Panic Button Found - Connecting...");

              // Auto-connect to the panic button
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
          if (!_isConnected && _foundDevices.isEmpty) {
            _updateConnectionStatus("Panic Button Not Found");
            // Retry scanning after a delay if auto-reconnect is enabled
            if (_autoReconnect) {
              Timer(const Duration(seconds: 10), () => _startAutoScanning());
            }
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Scan error: $e');
      _isScanning = false;
      _updateConnectionStatus("Scan Error: ${e.toString()}");
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;

    try {
      await FlutterBluePlus.stopScan();
      _isScanning = false;
      debugPrint('🛑 Scan stopped');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error stopping scan: $e');
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_isConnected || _isConnecting) {
      debugPrint('⚠️ Already connected or connecting to a device');
      return;
    }

    try {
      _isConnecting = true;
      debugPrint('🔗 Connecting to: ${device.platformName}');
      _updateConnectionStatus("Connecting to Panic Button...");

      // Stop scanning first
      await stopScan();

      // Connect to the device with retries
      int maxRetries = 3;
      bool connected = false;

      for (int attempt = 1; attempt <= maxRetries && !connected; attempt++) {
        try {
          debugPrint('🔗 Connection attempt $attempt/$maxRetries');
          await device.connect(timeout: const Duration(seconds: 15));
          connected = true;
        } catch (e) {
          debugPrint('❌ Connection attempt $attempt failed: $e');
          if (attempt < maxRetries) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }

      if (!connected) {
        throw Exception('Failed to connect after $maxRetries attempts');
      }

      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      debugPrint('🔍 Discovered ${services.length} services');

      // Find our service and characteristic
      BluetoothService? targetService;
      for (var service in services) {
        debugPrint('📋 Service: ${service.uuid}');
        if (service.uuid == Guid(SERVICE_UUID)) {
          targetService = service;
          break;
        }
      }

      if (targetService == null) {
        throw Exception(
            'ESP32 service not found. Make sure your ESP32 is running the correct firmware.');
      }

      BluetoothCharacteristic? targetCharacteristic;
      for (var characteristic in targetService.characteristics) {
        debugPrint('📝 Characteristic: ${characteristic.uuid}');
        if (characteristic.uuid == Guid(CHARACTERISTIC_UUID)) {
          targetCharacteristic = characteristic;
          break;
        }
      }

      if (targetCharacteristic == null) {
        throw Exception('ESP32 characteristic not found');
      }

      // Set up the connection
      _connectedDevice = device;
      _characteristic = targetCharacteristic;
      _isConnected = true;
      _isConnecting = false;
      _isPaired = true;
      _deviceId = device.remoteId.toString();
      _updateConnectionStatus("Panic Button Connected");

      // Save device for reconnection
      await _saveConnectedDevice(device);

      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((state) {
        _handleConnectionStateChange(state);
      });

      // Enable notifications to receive data from ESP32
      await _characteristic!.setNotifyValue(true);

      // Listen for incoming data
      _characteristicSubscription = _characteristic!.lastValueStream.listen(
        _handleIncomingData,
        onError: (error) {
          debugPrint('❌ Characteristic error: $error');
        },
      );

      // Send initial status request
      await sendMessage("STATUS");

      // Start heartbeat
      _startHeartbeat();

      debugPrint('✅ Successfully connected to panic button');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Connection failed: $e');
      _isConnected = false;
      _isConnecting = false;
      _connectedDevice = null;
      _characteristic = null;
      _updateConnectionStatus("Connection Failed: ${e.toString()}");

      // Retry connection after a delay
      if (_autoReconnect) {
        Timer(const Duration(seconds: 5), () => _startAutoScanning());
      }

      notifyListeners();
    }
  }

  void _handleConnectionStateChange(BluetoothConnectionState state) {
    debugPrint('🔗 Connection state changed: $state');

    if (state == BluetoothConnectionState.disconnected) {
      _isConnected = false;
      _isConnecting = false;
      _connectedDevice = null;
      _characteristic = null;
      _updateConnectionStatus("Panic Button Disconnected");
      _stopTimers();

      // Auto-reconnect if enabled
      if (_autoReconnect && _isBluetoothOn) {
        Timer(const Duration(seconds: 3), () => _startAutoScanning());
      }

      notifyListeners();
    }
  }

  void _handleIncomingData(List<int> data) {
    try {
      String message = utf8.decode(data);
      debugPrint('📨 Received: $message');
      _lastHeartbeat = DateTime.now();

      // Parse different message types
      if (message.startsWith('STATE:')) {
        _deviceState = message.substring(6);
      } else if (message.startsWith('{') && message.contains('ALERT')) {
        // JSON alert message
        Map<String, dynamic> alertData = json.decode(message);
        _handleAlert(alertData);
      } else if (message.startsWith('{') && message.contains('BATTERY')) {
        // JSON battery message
        Map<String, dynamic> batteryData = json.decode(message);
        _batteryLevel = batteryData['value'] ?? _batteryLevel;
      } else if (message == 'BTN_PRESS') {
        debugPrint('🚨 Button pressed!');
      } else if (message == 'BTN_RELEASE') {
        debugPrint('✋ Button released');
      } else if (message == 'PONG') {
        debugPrint('🏓 Heartbeat response received');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error handling incoming data: $e');
    }
  }

  void _handleAlert(Map<String, dynamic> alertData) {
    String alertType = alertData['level'] ?? 'UNKNOWN';
    int timestamp = alertData['timestamp'] ?? 0;
    int battery = alertData['battery'] ?? _batteryLevel;

    _lastAlert = '$alertType at ${DateTime.now().toString()}';
    _batteryLevel = battery;

    debugPrint('🚨 ALERT: $alertType (Battery: $battery%)');

    // Send acknowledgment back to ESP32
    sendMessage("ACK");

    // Trigger emergency response based on alert type
    _triggerEmergencyResponse(alertType, alertData);
  }

  void _triggerEmergencyResponse(
      String alertType, Map<String, dynamic> alertData) {
    debugPrint('🚨 Emergency Response: $alertType');
    // This will be handled by the emergency service through the main.dart handler
  }

  Future<void> sendMessage(String message) async {
    if (!_isConnected || _characteristic == null) {
      debugPrint('❌ Cannot send message - not connected');
      return;
    }

    try {
      List<int> bytes = utf8.encode(message);
      await _characteristic!.write(bytes);
      debugPrint('📤 Sent: $message');
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
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
      debugPrint('💾 Saved device for reconnection');
    } catch (e) {
      debugPrint('❌ Error saving device: $e');
    }
  }

  Future<void> _loadSavedDevice() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('last_panic_button_id');

      if (deviceId != null && _isBluetoothOn) {
        _deviceId = deviceId;
        debugPrint('🔍 Looking for saved device: $deviceId');
        // We'll try to reconnect during scanning
      }
    } catch (e) {
      debugPrint('❌ Error loading saved device: $e');
    }
  }

  Future<void> disconnect() async {
    _autoReconnect = false; // Temporarily disable auto-reconnect
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        debugPrint('🔌 Manually disconnected');
      } catch (e) {
        debugPrint('❌ Error disconnecting: $e');
      }
    }
    // Re-enable auto-reconnect after a delay
    Timer(const Duration(seconds: 2), () {
      _autoReconnect = true;
    });
  }

  void setAutoReconnect(bool enabled) {
    _autoReconnect = enabled;
    debugPrint('🔄 Auto-reconnect: $enabled');
    notifyListeners();
  }

  // Get detailed connection info
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

  // Method to trigger manual emergency (for testing or app-initiated alerts)
  Future<void> triggerManualEmergency(String alertType) async {
    if (!_isConnected) {
      debugPrint('❌ Cannot trigger manual emergency - not connected');
      return;
    }

    Map<String, dynamic> alertData = {
      'type': 'ALERT',
      'level': alertType,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'battery': _batteryLevel,
      'source': 'MANUAL'
    };

    _handleAlert(alertData);
  }
}
