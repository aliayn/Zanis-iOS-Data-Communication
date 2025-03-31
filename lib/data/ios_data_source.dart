import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

/// Event types that can be received from iOS
enum IOSEventType { data, status, deviceInfo }

/// Data model for iOS events
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
          payload: rawData['data'], // base64 encoded string
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

      default:
        throw FormatException('Unknown event type: ${rawData['type']}');
    }
  }
}

/// Data source for iOS data communication
///
/// This class is responsible for receiving data from the iOS app
/// and sending data to the iOS app
///
/// It uses the EventChannel to receive data from the iOS app
/// and the MethodChannel to send data to the iOS app
/// Singleton class
@singleton
class IOSDataSource {
  static const EventChannel _streamChannel = EventChannel('device_channel'); // Updated to match iOS channel name

  /// Stream of parsed iOS events
  Stream<IOSEvent> get eventStream =>
      _streamChannel.receiveBroadcastStream().map((data) => data as Map<dynamic, dynamic>).map(IOSEvent.fromPlatform);

  /// Convenience streams for specific event types
  Stream<String> get dataStream =>
      eventStream.where((event) => event.type == IOSEventType.data).map((event) => event.payload as String);

  Stream<bool> get connectionStream =>
      eventStream.where((event) => event.type == IOSEventType.status).map((event) => event.payload as bool);

  Stream<Map<String, String>> get deviceInfoStream => eventStream
      .where((event) => event.type == IOSEventType.deviceInfo)
      .map((event) => event.payload as Map<String, String>);
}

/// Adapter for iOS data communication
///
/// This class is responsible for adapting the raw platform data to the app's data model
///
/// It uses the EventChannel to receive data from the iOS app
/// and the MethodChannel to send data to the iOS app
///
class IOSDataAdapter {
  // Adapts raw platform data to the app's data model
  static String adaptData(Map<dynamic, dynamic> rawData) {
    try {
      // Check if 'value' key exists
      if (!rawData.containsKey('value')) {
        throw FormatException('Missing required key: value');
      }

      // Check if the value is an integer
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
