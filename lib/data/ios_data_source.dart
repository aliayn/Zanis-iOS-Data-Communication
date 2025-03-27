import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

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
  static const EventChannel _streamChannel =
      EventChannel('zanis_ios_data_communication');

  Stream<Map<dynamic, dynamic>> get stream => _streamChannel
      .receiveBroadcastStream()
      .map((data) => data as Map<dynamic, dynamic>);
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
