import 'package:flutter/services.dart';

class IosDataSource {
  static const EventChannel _streamChannel =
      EventChannel('zanis_ios_data_communication');

  Stream<Map<String, dynamic>> get stream => _streamChannel
      .receiveBroadcastStream()
      .map((data) => data as Map<String, dynamic>);
}

class IOSDataAdapter {
  // Adapts raw platform data to the app's data model
  static int adaptData(Map<String, dynamic> data) {
    try {
      return data['value'] as int;
    } on Exception catch (e) {
      throw Exception("Invalid data format: $e");
    }
  }
}
