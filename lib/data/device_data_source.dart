import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:zanis_ios_data_communication/data/android_data_source.dart';
import 'package:zanis_ios_data_communication/data/ios_data_source.dart';
import 'package:zanis_ios_data_communication/data/platform_detector.dart';
import 'package:zanis_ios_data_communication/data/vendor_android_data_source.dart';

enum DeviceEventType { data, status, deviceInfo, networkInterface }

enum CommunicationType { usbSerial, vendorUsb }

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
  final VendorAndroidDataSource _vendorAndroidDataSource;
  final StreamController<DeviceEvent> _eventController = StreamController<DeviceEvent>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();

  List<StreamSubscription> _subscriptions = [];
  CommunicationType _currentCommunicationType = CommunicationType.usbSerial;

  DeviceDataSource(
    this._platformDetector,
    this._iosDataSource,
    this._androidDataSource,
    this._vendorAndroidDataSource,
  ) {
    _setupStreams();
  }

  void _setupStreams() {
    if (_platformDetector.isIOS) {
      _setupIOSStreams();
    } else if (_platformDetector.isAndroid) {
      _setupAndroidStreams();
      _setupVendorAndroidStreams();
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
      _log('Android USB Serial: $log');
    }));

    _subscriptions.add(_androidDataSource.eventStream.listen((event) {
      // Only process events if we're using USB serial communication
      if (_currentCommunicationType == CommunicationType.usbSerial) {
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
      }
    }));
  }

  void _setupVendorAndroidStreams() {
    _subscriptions.add(_vendorAndroidDataSource.logStream.listen((log) {
      _log('Android Vendor USB: $log');
    }));

    _subscriptions.add(_vendorAndroidDataSource.eventStream.listen((event) {
      // Only process events if we're using vendor USB communication
      if (_currentCommunicationType == CommunicationType.vendorUsb) {
        switch (event.type) {
          case VendorAndroidEventType.data:
            _eventController.add(DeviceEvent(
              timestamp: event.timestamp,
              type: DeviceEventType.data,
              payload: event.payload,
            ));
            break;
          case VendorAndroidEventType.status:
            _eventController.add(DeviceEvent(
              timestamp: event.timestamp,
              type: DeviceEventType.status,
              payload: event.payload,
            ));
            break;
          case VendorAndroidEventType.deviceInfo:
            _eventController.add(DeviceEvent(
              timestamp: event.timestamp,
              type: DeviceEventType.deviceInfo,
              payload: event.payload,
            ));
            break;
          case VendorAndroidEventType.networkInterface:
            _eventController.add(DeviceEvent(
              timestamp: event.timestamp,
              type: DeviceEventType.networkInterface,
              payload: event.payload,
            ));
            break;
          case VendorAndroidEventType.bulkTransfer:
          case VendorAndroidEventType.interruptTransfer:
            // Log specialized transfer results
            _log('Transfer result: ${event.payload}');
            break;
        }
      }
    }));
  }

  void _log(String message) {
    debugPrint('DeviceDataSource: $message');
    _logController.add(message);
  }

  // Communication type management
  void setCommunicationType(CommunicationType type) {
    if (_currentCommunicationType != type) {
      _log('Switching communication type from $_currentCommunicationType to $type');
      _currentCommunicationType = type;
    }
  }

  CommunicationType get currentCommunicationType => _currentCommunicationType;

  Future<bool> sendData(Uint8List data) async {
    if (_platformDetector.isIOS) {
      return await _iosDataSource.sendData(data);
    } else if (_platformDetector.isAndroid) {
      switch (_currentCommunicationType) {
        case CommunicationType.usbSerial:
          return await _androidDataSource.sendData(data);
        case CommunicationType.vendorUsb:
          return await _vendorAndroidDataSource.sendData(data);
      }
    } else {
      _log('Unsupported platform');
      return false;
    }
  }

  Future<bool> sendString(String text) async {
    if (_platformDetector.isIOS) {
      return await _iosDataSource.sendString(text);
    } else if (_platformDetector.isAndroid) {
      switch (_currentCommunicationType) {
        case CommunicationType.usbSerial:
          return await _androidDataSource.sendString(text);
        case CommunicationType.vendorUsb:
          return await _vendorAndroidDataSource.sendString(text);
      }
    } else {
      _log('Unsupported platform');
      return false;
    }
  }

  // Vendor-specific USB methods (only available on Android)
  Future<bool> sendBulkTransfer(Uint8List data, {int endpoint = 0x02}) async {
    if (_platformDetector.isAndroid && _currentCommunicationType == CommunicationType.vendorUsb) {
      return await _vendorAndroidDataSource.sendBulkTransfer(data, endpoint: endpoint);
    } else {
      _log('Bulk transfer not supported on current platform/communication type');
      return false;
    }
  }

  Future<bool> sendInterruptTransfer(Uint8List data, {int endpoint = 0x81}) async {
    if (_platformDetector.isAndroid && _currentCommunicationType == CommunicationType.vendorUsb) {
      return await _vendorAndroidDataSource.sendInterruptTransfer(data, endpoint: endpoint);
    } else {
      _log('Interrupt transfer not supported on current platform/communication type');
      return false;
    }
  }

  Future<List<dynamic>> getAvailableDevices() async {
    try {
    if (_platformDetector.isIOS) {
      await _iosDataSource.refreshConnection();
      return [];
    } else if (_platformDetector.isAndroid) {
      switch (_currentCommunicationType) {
        case CommunicationType.usbSerial:
          return await _androidDataSource.getAvailableDevices();
        case CommunicationType.vendorUsb:
          return await _vendorAndroidDataSource.scanDevices();
      }
    } else {
      _log('Unsupported platform');
        return [];
      }
    } catch (e) {
      _log('Error getting available devices: $e');
      return [];
    }
  }

  Future<bool> connectToDevice(Map<String, dynamic> deviceInfo) async {
    if (_platformDetector.isAndroid && _currentCommunicationType == CommunicationType.vendorUsb) {
      return await _vendorAndroidDataSource.connectToDevice(deviceInfo);
    } else {
      _log('Direct device connection only supported for vendor USB on Android');
      return false;
    }
  }

  Future<bool> disconnectDevice() async {
    if (_platformDetector.isAndroid && _currentCommunicationType == CommunicationType.vendorUsb) {
      return await _vendorAndroidDataSource.disconnect();
    } else {
      _log('Direct device disconnection only supported for vendor USB on Android');
      return false;
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

  // Vendor USB specific streams (only available when using vendor USB)
  Stream<dynamic> get bulkTransferStream => _vendorAndroidDataSource.bulkTransferStream;

  Stream<dynamic> get interruptTransferStream => _vendorAndroidDataSource.interruptTransferStream;

  void dispose() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _eventController.close();
    _logController.close();
  }
}
