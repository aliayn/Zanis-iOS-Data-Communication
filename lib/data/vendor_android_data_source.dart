import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

enum VendorAndroidEventType { data, status, deviceInfo, networkInterface, bulkTransfer, interruptTransfer }

class VendorAndroidEvent {
  final DateTime timestamp;
  final VendorAndroidEventType type;
  final dynamic payload;

  VendorAndroidEvent({
    required this.timestamp,
    required this.type,
    required this.payload,
  });

  factory VendorAndroidEvent.fromData({
    required VendorAndroidEventType type,
    required dynamic payload,
  }) {
    return VendorAndroidEvent(
      timestamp: DateTime.now(),
      type: type,
      payload: payload,
    );
  }
}

@singleton
class VendorAndroidDataSource {
  static const String _channelName = 'com.zanis.vendor_usb';
  static const String _eventChannelName = 'com.zanis.vendor_usb/events';

  late final MethodChannel _methodChannel;
  late final EventChannel _eventChannel;

  StreamSubscription<dynamic>? _eventSubscription;
  bool _isInitialized = false;
  bool _isConnected = false;
  Map<String, dynamic>? _currentDevice;

  final StreamController<VendorAndroidEvent> _eventController = StreamController<VendorAndroidEvent>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();

  VendorAndroidDataSource() {
    if (Platform.isAndroid) {
      _init();
    } else {
      _log('Not running on Android, vendor USB functionality disabled');
    }
  }

  void _init() {
    _log('Initializing Vendor-Specific Android USB Data Source');

    _methodChannel = const MethodChannel(_channelName);
    _eventChannel = const EventChannel(_eventChannelName);

    _setupEventStream();
    _initializeNativeUsb();
  }

  void _setupEventStream() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        _handleNativeEvent(event);
      },
      onError: (error) {
        _log('Event stream error: $error');
      },
    );
  }

  void _handleNativeEvent(dynamic event) {
    try {
      if (event is! Map) {
        _log('Received invalid event format: $event');
        return;
      }

      final eventMap = Map<String, dynamic>.from(event);
      final eventType = eventMap['type'] as String?;
      final payload = eventMap['payload'];

      if (eventType == null) {
        _log('Received event with null type: $eventMap');
        return;
      }

      switch (eventType) {
        case 'device_attached':
          _handleDeviceAttached(payload);
          break;
        case 'device_detached':
          _handleDeviceDetached(payload);
          break;
        case 'data_received':
          _handleDataReceived(payload);
          break;
        case 'connection_status':
          _handleConnectionStatus(payload);
          break;
        case 'bulk_transfer_result':
          _handleBulkTransferResult(payload);
          break;
        case 'interrupt_transfer_result':
          _handleInterruptTransferResult(payload);
          break;
        case 'log':
          _log('Native: ${payload ?? ""}');
          break;
        default:
          _log('Unknown event type: $eventType');
      }
    } catch (e) {
      _log('Error handling native event: $e');
    }
  }

  void _handleDeviceAttached(dynamic payload) {
    if (payload is Map) {
      try {
        final deviceInfo = Map<String, dynamic>.from(payload);
        _currentDevice = deviceInfo;

        // Enhanced logging for debugging
        final totalEndpoints = deviceInfo['totalEndpoints'] ?? 0;
        final endpointDetails = deviceInfo['endpointDetails'] ?? '';
        final deviceClass = deviceInfo['deviceClass'] ?? 0;
        final isMfi = isMfiDevice(deviceInfo);

        _sendEvent(VendorAndroidEvent.fromData(
          type: VendorAndroidEventType.deviceInfo,
          payload: {
            'vid': deviceInfo['vendorId']?.toString() ?? '0',
            'pid': deviceInfo['productId']?.toString() ?? '0',
            'deviceName': deviceInfo['deviceName'] ?? 'Unknown',
            'manufacturerName': deviceInfo['manufacturerName'] ?? 'Unknown',
            'productName': deviceInfo['productName'] ?? 'Unknown',
            'hasEndpoints': deviceInfo['hasEndpoints'] ?? false,
            'totalEndpoints': totalEndpoints,
            'endpointDetails': endpointDetails,
            'deviceClass': deviceClass,
            'isMfiDevice': isMfi,
          },
        ));

        _log(
            'Vendor USB device attached: ${deviceInfo['productName']} (VID: 0x${deviceInfo['vendorId']?.toRadixString(16)}, PID: 0x${deviceInfo['productId']?.toRadixString(16)})');
        _log('Device details: Endpoints=$totalEndpoints, Class=$deviceClass, MFi=$isMfi');
        if (endpointDetails.isNotEmpty) {
          _log('Endpoint details: $endpointDetails');
        }

        // Don't auto-connect, let user manually connect via UI
        _log('Device detected but not auto-connecting. Use Connect button to manually connect.');
      } catch (e) {
        _log('Error handling device attached event: $e');
      }
    }
  }

  void _handleDeviceDetached(dynamic payload) {
    _currentDevice = null;
    _isConnected = false;

    _sendEvent(VendorAndroidEvent.fromData(
      type: VendorAndroidEventType.status,
      payload: false,
    ));

    _log('Vendor USB device detached');
  }

  void _handleDataReceived(dynamic payload) {
    if (payload is String) {
      _sendEvent(VendorAndroidEvent.fromData(
        type: VendorAndroidEventType.data,
        payload: payload,
      ));
      _log('Received data: $payload');
    } else if (payload is List) {
      // Convert byte array to string
      final bytes = Uint8List.fromList(payload.cast<int>());
      final dataString = String.fromCharCodes(bytes);

      _sendEvent(VendorAndroidEvent.fromData(
        type: VendorAndroidEventType.data,
        payload: dataString,
      ));
      _log('Received raw data: ${bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }
  }

  void _handleConnectionStatus(dynamic payload) {
    if (payload is bool) {
      _isConnected = payload;
      _sendEvent(VendorAndroidEvent.fromData(
        type: VendorAndroidEventType.status,
        payload: payload,
      ));
      _log('Connection status changed: ${payload ? 'Connected' : 'Disconnected'}');
    }
  }

  Future<void> autoConnectDevice(Map<String, dynamic> deviceInfo) async {
    try {
      _log('Auto-connecting to device: ${deviceInfo['productName']}');

      // First request permission
      final permissionGranted = await requestPermission(deviceInfo);
      if (permissionGranted) {
        // Small delay to ensure permission is processed
        await Future.delayed(const Duration(milliseconds: 500));

        // Then connect
        final connected = await connectToDevice(deviceInfo);
        if (connected) {
          _log('Auto-connection successful');
        } else {
          _log('Auto-connection failed');
        }
      } else {
        _log('Auto-connection failed: Permission denied');
      }
    } catch (e) {
      _log('Error during auto-connection: $e');
    }
  }

  void _handleBulkTransferResult(dynamic payload) {
    _sendEvent(VendorAndroidEvent.fromData(
      type: VendorAndroidEventType.bulkTransfer,
      payload: payload,
    ));
    _log('Bulk transfer result: $payload');
  }

  void _handleInterruptTransferResult(dynamic payload) {
    _sendEvent(VendorAndroidEvent.fromData(
      type: VendorAndroidEventType.interruptTransfer,
      payload: payload,
    ));
    _log('Interrupt transfer result: $payload');
  }

  Future<void> _initializeNativeUsb() async {
    try {
      await _methodChannel.invokeMethod('initialize');
      _isInitialized = true;
      _log('Native USB initialized');

      // Start scanning for both devices and accessories
      await scanAllDevicesAndAccessories();

      // Also scan just accessories to see if any AOA devices are present
      final accessories = await scanAccessories();
      if (accessories.isNotEmpty) {
        _log('Found ${accessories.length} USB accessories that may be AOA devices');
      }
    } catch (e) {
      _log('Error initializing native USB: $e');
    }
  }

  // Public API methods
  Future<bool> sendData(Uint8List data) async {
    if (!_isConnected) {
      _log('Cannot send data: Not connected');
      return false;
    }

    try {
      _log('Sending raw data: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

      final result = await _methodChannel.invokeMethod('sendBulkData', {
        'data': data,
      });

      _log('Data sent successfully: $result');
      return true;
    } catch (e) {
      _log('Error sending data: $e');
      return false;
    }
  }

  Future<bool> sendString(String text) async {
    try {
      _log('Sending string: $text');
      // Add CR+LF for line termination to maintain compatibility
      final data = Uint8List.fromList([...text.codeUnits, 13, 10]);
      return await sendData(data);
    } catch (e) {
      _log('Error in sendString: $e');
      return false;
    }
  }

  Future<bool> sendBulkTransfer(Uint8List data, {int endpoint = 0x02}) async {
    if (!_isConnected) {
      _log('Cannot send bulk transfer: Not connected');
      return false;
    }

    try {
      final result = await _methodChannel.invokeMethod('bulkTransfer', {
        'endpoint': endpoint,
        'data': data,
        'timeout': 5000,
      });

      _log('Bulk transfer sent: $result');
      return result == true;
    } catch (e) {
      _log('Error sending bulk transfer: $e');
      return false;
    }
  }

  Future<bool> sendInterruptTransfer(Uint8List data, {int endpoint = 0x81}) async {
    if (!_isConnected) {
      _log('Cannot send interrupt transfer: Not connected');
      return false;
    }

    try {
      final result = await _methodChannel.invokeMethod('interruptTransfer', {
        'endpoint': endpoint,
        'data': data,
        'timeout': 1000,
      });

      _log('Interrupt transfer sent: $result');
      return result == true;
    } catch (e) {
      _log('Error sending interrupt transfer: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> scanDevices() async {
    try {
      final result = await _methodChannel.invokeMethod('scanDevices');
      if (result is List) {
        final devices = <Map<String, dynamic>>[];
        for (final item in result) {
          try {
            if (item is Map) {
              devices.add(Map<String, dynamic>.from(item));
            } else {
              _log('Unexpected device type: ${item.runtimeType}');
            }
          } catch (e) {
            _log('Error processing device item: $e');
          }
        }
        _log('Found ${devices.length} vendor USB devices');
        return devices;
      }
      return [];
    } catch (e) {
      _log('Error scanning devices: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> scanAllDevicesAndAccessories() async {
    try {
      _log('Scanning for both USB devices and accessories...');
      final result = await _methodChannel.invokeMethod('scanAll');
      if (result is List) {
        final items = <Map<String, dynamic>>[];
        for (final item in result) {
          try {
            if (item is Map) {
              items.add(Map<String, dynamic>.from(item));
            } else {
              _log('Unexpected item type: ${item.runtimeType}');
            }
          } catch (e) {
            _log('Error processing item: $e');
          }
        }
        _log('Found ${items.length} total USB devices and accessories');
        return items;
      }
      return [];
    } catch (e) {
      _log('Error scanning all devices and accessories: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> scanAccessories() async {
    try {
      final result = await _methodChannel.invokeMethod('checkAccessories');
      if (result is List) {
        final accessories = <Map<String, dynamic>>[];
        for (final item in result) {
          try {
            if (item is Map) {
              accessories.add(Map<String, dynamic>.from(item));
            } else {
              _log('Unexpected accessory type: ${item.runtimeType}');
            }
          } catch (e) {
            _log('Error processing accessory item: $e');
          }
        }
        _log('Found ${accessories.length} USB accessories');
        return accessories;
      }
      return [];
    } catch (e) {
      _log('Error scanning accessories: $e');
      return [];
    }
  }

  bool isMfiDevice(Map<String, dynamic> deviceInfo) {
    final vendorId = deviceInfo['vendorId'] as int?;
    final hasEndpoints = deviceInfo['hasEndpoints'] as bool? ?? false;
    final deviceClass = deviceInfo['deviceClass'] as int? ?? 0;
    final productName = deviceInfo['productName'] as String? ?? '';
    final totalEndpoints = deviceInfo['totalEndpoints'] as int? ?? 0;

    // For Apple vendor ID devices (0xac1/2753), prioritize accessory mode
    // These devices are typically designed to work as AOA hosts
    if (vendorId == 2753 || vendorId == 0xac1) {
      _log('Detected Apple vendor device (VID=$vendorId) - will prioritize AOA accessory mode');
      return true;
    }

    // Check for explicit MFi/accessory indicators
    if (productName.toLowerCase().contains('mfi')) {
      _log('Detected MFi device by name - will use accessory mode');
      return true;
    }

    if (productName.toLowerCase().contains('accessory')) {
      _log('Detected accessory device by name - will use accessory mode');
      return true;
    }

    return false;
  }

  Future<bool> connectToDevice(Map<String, dynamic> deviceInfo) async {
    try {
      final result = await _methodChannel.invokeMethod('connectToDevice', deviceInfo);
      if (result == true) {
        _currentDevice = deviceInfo;
        _log('Connected to device: ${deviceInfo['productName']}');
        return true;
      }
      return false;
    } catch (e) {
      _log('Error connecting to device: $e');

      // Provide specific guidance for different error types
      if (e.toString().contains('AOA_SETUP_REQUIRED')) {
        _log('');
        _log('=== AOA (Android Open Accessory) Setup Required ===');
        _log('This Apple vendor device (VID=0xac1) needs to work in AOA mode where:');
        _log('1. External device acts as USB HOST (provides power)');
        _log('2. Android device acts as USB ACCESSORY (receives power)');
        _log('3. External device must initiate AOA protocol negotiation');
        _log('');
        _log('Next steps:');
        _log('1. Ensure external device is providing USB power to Android');
        _log('2. External device should send AOA identification strings');
        _log('3. Try scanning for accessories instead of devices');
        _log('==============================================');
      } else if (isMfiDevice(deviceInfo)) {
        _log('This appears to be an AOA/MFi device. Connection may require:');
        _log('- External device to initiate AOA protocol');
        _log('- Android device to be in USB accessory mode');
        _log('- Proper AOA identification by external device');
      }
      return false;
    }
  }

  Future<bool> connectToAccessory(Map<String, dynamic> accessoryInfo) async {
    try {
      final result = await _methodChannel.invokeMethod('connectToAccessory', accessoryInfo);
      if (result == true) {
        _log('Connected to accessory: ${accessoryInfo['model']}');
        return true;
      }
      return false;
    } catch (e) {
      _log('Error connecting to accessory: $e');
      return false;
    }
  }

  Future<bool> requestAccessoryPermission(Map<String, dynamic> accessoryInfo) async {
    try {
      final result = await _methodChannel.invokeMethod('requestAccessoryPermission', accessoryInfo);
      return result == true;
    } catch (e) {
      _log('Error requesting accessory permission: $e');
      return false;
    }
  }

  Future<bool> disconnect() async {
    try {
      await _methodChannel.invokeMethod('disconnect');
      _currentDevice = null;
      _isConnected = false;
      _log('Disconnected from device');
      return true;
    } catch (e) {
      _log('Error disconnecting: $e');
      return false;
    }
  }

  Future<bool> requestPermission(Map<String, dynamic> deviceInfo) async {
    try {
      final result = await _methodChannel.invokeMethod('requestPermission', deviceInfo);
      return result == true;
    } catch (e) {
      _log('Error requesting permission: $e');
      return false;
    }
  }

  void _sendEvent(VendorAndroidEvent event) {
    try {
      _eventController.add(event);
    } catch (e) {
      debugPrint('Error sending event: $e');
    }
  }

  void _log(String message) {
    debugPrint('VendorAndroidUSB: $message');
    try {
      _logController.add(message);
    } catch (e) {
      debugPrint('Error logging message: $e');
    }
  }

  // Public streams
  Stream<VendorAndroidEvent> get eventStream => _eventController.stream;

  Stream<String> get logStream => _logController.stream;

  Stream<String> get dataStream =>
      eventStream.where((event) => event.type == VendorAndroidEventType.data).map((event) => event.payload as String);

  Stream<bool> get connectionStream =>
      eventStream.where((event) => event.type == VendorAndroidEventType.status).map((event) => event.payload as bool);

  Stream<Map<String, String>> get deviceInfoStream => eventStream
      .where((event) => event.type == VendorAndroidEventType.deviceInfo)
      .map((event) => event.payload as Map<String, String>);

  Stream<dynamic> get bulkTransferStream =>
      eventStream.where((event) => event.type == VendorAndroidEventType.bulkTransfer).map((event) => event.payload);

  Stream<dynamic> get interruptTransferStream => eventStream
      .where((event) => event.type == VendorAndroidEventType.interruptTransfer)
      .map((event) => event.payload);

  // Properties
  bool get isInitialized => _isInitialized;
  bool get isConnected => _isConnected;
  Map<String, dynamic>? get currentDevice => _currentDevice;

  void dispose() {
    _eventSubscription?.cancel();
    disconnect();
    _eventController.close();
    _logController.close();
  }
}
