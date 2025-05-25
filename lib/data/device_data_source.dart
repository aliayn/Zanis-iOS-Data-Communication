import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:zanis_ios_data_communication/data/android_data_source.dart';
import 'package:zanis_ios_data_communication/data/ios_data_source.dart';
import 'package:zanis_ios_data_communication/data/platform_detector.dart';

enum DeviceEventType { data, status, deviceInfo, networkInterface }

class DeviceEvent {
  final DateTime timestamp;
  final DeviceEventType type;
  final dynamic payload;

  DeviceEvent({
    required this.timestamp,
    required this.type,
    required this.payload,
  });
}

@singleton
class DeviceDataSource {
  final PlatformDetector _platformDetector;
  final IOSDataSource _iosDataSource;
  final AndroidDataSource _androidDataSource;
  final StreamController<DeviceEvent> _eventController = StreamController<DeviceEvent>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();

  List<StreamSubscription> _subscriptions = [];

  DeviceDataSource(
    this._platformDetector,
    this._iosDataSource,
    this._androidDataSource,
  ) {
    _setupStreams();
  }

  void _setupStreams() {
    if (_platformDetector.isIOS) {
      _setupIOSStreams();
    } else if (_platformDetector.isAndroid) {
      _setupAndroidStreams();
    } else {
      _log('Unsupported platform');
    }
  }

  void _setupIOSStreams() {
    _subscriptions.add(_iosDataSource.logStream.listen((log) {
      _log('iOS: $log');
    }));

    _subscriptions.add(_iosDataSource.eventStream.listen((event) {
      switch (event.type) {
        case IOSEventType.data:
          _eventController.add(DeviceEvent(
            timestamp: event.timestamp,
            type: DeviceEventType.data,
            payload: event.payload,
          ));
          break;
        case IOSEventType.status:
          _eventController.add(DeviceEvent(
            timestamp: event.timestamp,
            type: DeviceEventType.status,
            payload: event.payload,
          ));
          break;
        case IOSEventType.deviceInfo:
          _eventController.add(DeviceEvent(
            timestamp: event.timestamp,
            type: DeviceEventType.deviceInfo,
            payload: event.payload,
          ));
          break;
        case IOSEventType.networkInterface:
          _eventController.add(DeviceEvent(
            timestamp: event.timestamp,
            type: DeviceEventType.networkInterface,
            payload: event.payload,
          ));
          break;
      }
    }));
  }

  void _setupAndroidStreams() {
    _subscriptions.add(_androidDataSource.logStream.listen((log) {
      _log('Android: $log');
    }));

    _subscriptions.add(_androidDataSource.eventStream.listen((event) {
      switch (event.type) {
        case AndroidEventType.data:
          _eventController.add(DeviceEvent(
            timestamp: event.timestamp,
            type: DeviceEventType.data,
            payload: event.payload,
          ));
          break;
        case AndroidEventType.status:
          _eventController.add(DeviceEvent(
            timestamp: event.timestamp,
            type: DeviceEventType.status,
            payload: event.payload,
          ));
          break;
        case AndroidEventType.deviceInfo:
          _eventController.add(DeviceEvent(
            timestamp: event.timestamp,
            type: DeviceEventType.deviceInfo,
            payload: event.payload,
          ));
          break;
        case AndroidEventType.networkInterface:
          _eventController.add(DeviceEvent(
            timestamp: event.timestamp,
            type: DeviceEventType.networkInterface,
            payload: event.payload,
          ));
          break;
      }
    }));
  }

  void _log(String message) {
    debugPrint('DeviceDataSource: $message');
    _logController.add(message);
  }

  Future<bool> sendData(Uint8List data) async {
    if (_platformDetector.isIOS) {
      // Convert to Flutter standard typed data for iOS channel
      return await _iosDataSource.sendData(data);
    } else if (_platformDetector.isAndroid) {
      return await _androidDataSource.sendData(data);
    } else {
      _log('Unsupported platform');
      return false;
    }
  }

  Future<bool> sendString(String text) async {
    if (_platformDetector.isIOS) {
      return await _iosDataSource.sendString(text);
    } else if (_platformDetector.isAndroid) {
      return await _androidDataSource.sendString(text);
    } else {
      _log('Unsupported platform');
      return false;
    }
  }

  Future<List<dynamic>> getAvailableDevices() async {
    if (_platformDetector.isIOS) {
      // iOS doesn't support explicit device listing
      // We can use refreshConnection to force a connection check
      await _iosDataSource.refreshConnection();
      return [];
    } else if (_platformDetector.isAndroid) {
      return await _androidDataSource.getAvailableDevices();
    } else {
      _log('Unsupported platform');
      return [];
    }
  }

  // Public streams
  Stream<DeviceEvent> get eventStream => _eventController.stream;

  Stream<String> get logStream => _logController.stream;

  Stream<String> get dataStream =>
      eventStream.where((event) => event.type == DeviceEventType.data).map((event) => event.payload as String);

  Stream<bool> get connectionStream =>
      eventStream.where((event) => event.type == DeviceEventType.status).map((event) => event.payload as bool);

  Stream<Map<String, String>> get deviceInfoStream => eventStream
      .where((event) => event.type == DeviceEventType.deviceInfo)
      .map((event) => event.payload as Map<String, String>);

  void dispose() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _eventController.close();
    _logController.close();
  }
}
