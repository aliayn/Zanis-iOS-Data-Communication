import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

enum IOSEventType { data, status, deviceInfo, networkInterface }

class IOSEvent {
  final DateTime timestamp;
  final IOSEventType type;
  final dynamic payload;

  IOSEvent({
    required this.timestamp,
    required this.type,
    required this.payload,
  });

  factory IOSEvent.fromPlatform(Map<dynamic, dynamic> rawData) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch((rawData['timestamp'] * 1000).toInt());

    switch (rawData['type']) {
      case 'data':
        return IOSEvent(
          timestamp: timestamp,
          type: IOSEventType.data,
          payload: rawData['data'],
        );

      case 'status':
        return IOSEvent(
          timestamp: timestamp,
          type: IOSEventType.status,
          payload: rawData['connected'] as bool,
        );

      case 'deviceInfo':
        return IOSEvent(
          timestamp: timestamp,
          type: IOSEventType.deviceInfo,
          payload: {
            'vid': rawData['vid'] as String,
            'pid': rawData['pid'] as String,
          },
        );

      case 'networkInterface':
        return IOSEvent(
          timestamp: timestamp,
          type: IOSEventType.networkInterface,
          payload: rawData['interface'] as String,
        );

      default:
        throw FormatException('Unknown event type: ${rawData['type']}');
    }
  }
}

@singleton
class IOSDataSource {
  static const EventChannel _streamChannel = EventChannel('com.zanis.peertalk/device_info');
  static const MethodChannel _streamLogChannel = MethodChannel('com.zanis.peertalk/logs');
  static const MethodChannel _deviceChannel = MethodChannel('com.zanis.device');
  final StreamController<String> _logController = StreamController<String>.broadcast();

  IOSDataSource() {
    _setupLogStream();
    _initializeDataService();
  }

  // Initialize data service and mark it as ready
  Future<void> _initializeDataService() async {
    try {
      // Wait a moment for Flutter to initialize
      await Future.delayed(const Duration(milliseconds: 500));

      // Tell native code that Flutter is ready to receive data
      await _deviceChannel.invokeMethod('isReady');

      // Process any buffered data
      await _deviceChannel.invokeMethod('processBufferedData');

      debugPrint('iOS DataService initialized and marked as ready');
    } catch (e) {
      debugPrint('Error initializing iOS DataService: $e');
    }
  }

  void _setupLogStream() {
    _streamLogChannel.setMethodCallHandler((call) async {
      if (call.method == 'log') {
        final logData = call.arguments as String;
        debugPrint('Received iOS log: $logData');
        _logController.add(logData);
      }
    });
  }

  // Send data to the device
  Future<bool> sendData(Uint8List data) async {
    try {
      await _deviceChannel.invokeMethod('sendData', data);
      return true;
    } catch (e) {
      debugPrint('Error sending data to iOS device: $e');
      return false;
    }
  }

  // Send string data to the device
  Future<bool> sendString(String text) async {
    try {
      final data = Uint8List.fromList(utf8.encode(text));
      await _deviceChannel.invokeMethod('sendData', data);
      return true;
    } catch (e) {
      debugPrint('Error sending string to iOS device: $e');
      return false;
    }
  }

  // Force refresh the connection
  Future<bool> refreshConnection() async {
    try {
      await _deviceChannel.invokeMethod('refreshConnection');
      return true;
    } catch (e) {
      debugPrint('Error refreshing iOS device connection: $e');
      return false;
    }
  }

  // Check if any buffered data needs to be processed
  Future<bool> processBufferedData() async {
    try {
      await _deviceChannel.invokeMethod('processBufferedData');
      return true;
    } catch (e) {
      debugPrint('Error processing buffered data: $e');
      return false;
    }
  }

  Stream<String> get logStream => _logController.stream;

  Stream<IOSEvent> get eventStream => _streamChannel.receiveBroadcastStream().map((data) {
        final eventData = data as Map<dynamic, dynamic>;
        debugPrint('Received iOS event: $eventData');
        return eventData;
      }).map(IOSEvent.fromPlatform);

  Stream<String> get dataStream => eventStream.where((event) => event.type == IOSEventType.data).map((event) {
        final data = event.payload as String;
        debugPrint('Received iOS data: $data');
        return data;
      });

  Stream<bool> get connectionStream => eventStream.where((event) => event.type == IOSEventType.status).map((event) {
        final status = event.payload as bool;
        debugPrint('Connection status changed: $status');
        return status;
      });

  Stream<Map<String, String>> get deviceInfoStream =>
      eventStream.where((event) => event.type == IOSEventType.deviceInfo).map((event) {
        final deviceInfo = event.payload as Map<String, String>;
        debugPrint('Received device info: $deviceInfo');
        return deviceInfo;
      });

  Stream<String> get networkInterfaceStream =>
      eventStream.where((event) => event.type == IOSEventType.networkInterface).map((event) {
        final interface = event.payload as String;
        debugPrint('Network interface changed: $interface');
        return interface;
      });
}

class IOSDataAdapter {
  static String adaptData(Map<dynamic, dynamic> rawData) {
    try {
      if (!rawData.containsKey('value')) {
        throw FormatException('Missing required key: value');
      }

      final value = rawData['value'];
      if (value is! String) {
        throw FormatException('Value is not an integer: $value');
      }

      return value;
    } catch (e) {
      if (e is FormatException) {
        rethrow;
      }
      throw FormatException("Invalid data format: $e");
    }
  }
}
