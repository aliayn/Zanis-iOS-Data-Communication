import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

enum AndroidEventType { data, status, deviceInfo, networkInterface }

class AndroidEvent {
  final DateTime timestamp;
  final AndroidEventType type;
  final dynamic payload;

  AndroidEvent({
    required this.timestamp,
    required this.type,
    required this.payload,
  });

  factory AndroidEvent.fromData({
    required AndroidEventType type,
    required dynamic payload,
  }) {
    return AndroidEvent(
      timestamp: DateTime.now(),
      type: type,
      payload: payload,
    );
  }
}

@singleton
class AndroidDataSource {
  UsbPort? _port;
  UsbDevice? _device;
  Transaction<String>? _transaction;
  StreamSubscription<String>? _dataSubscription;
  StreamSubscription<UsbEvent>? _usbEventSubscription;

  final StreamController<AndroidEvent> _eventController = StreamController<AndroidEvent>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();

  AndroidDataSource() {
    if (Platform.isAndroid) {
      _init();
    }
  }

  void _init() {
    // Listen for USB device connection/disconnection events
    _usbEventSubscription = UsbSerial.usbEventStream?.listen((UsbEvent event) {
      _log('USB event: ${event.event}, device: ${event.device?.productName}');
      _scanDevices();
    });

    // Initial device scan
    _scanDevices();
  }

  Future<void> _scanDevices() async {
    _log('Scanning for USB devices...');
    final devices = await UsbSerial.listDevices();

    if (devices.isEmpty) {
      _log('No USB devices found');
      if (_device != null) {
        _sendEvent(AndroidEvent.fromData(
          type: AndroidEventType.status,
          payload: false,
        ));
        _disconnect();
      }
    } else {
      _log('Found ${devices.length} USB devices');
      for (final device in devices) {
        _log('Device: ${device.productName}, VID: ${device.vid}, PID: ${device.pid}');

        // Send device info event for each device
        _sendEvent(AndroidEvent.fromData(
          type: AndroidEventType.deviceInfo,
          payload: {
            'vid': device.vid.toString(),
            'pid': device.pid.toString(),
          },
        ));
      }

      // Connect to the first device if not already connected
      if (_device == null && devices.isNotEmpty) {
        _connectToDevice(devices.first);
      }
    }
  }

  Future<void> _connectToDevice(UsbDevice device) async {
    _log('Connecting to device: ${device.productName}...');

    // Disconnect first if already connected
    await _disconnect();

    try {
      // Create port
      _port = await device.create();

      if (_port == null) {
        _log('Failed to create port');
        return;
      }

      // Open port
      final openResult = await _port!.open();
      if (!openResult) {
        _log('Failed to open port');
        _port = null;
        return;
      }

      // Configure port
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        115200, // Baud rate
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _device = device;

      // Set up transaction for line-based communication (CR+LF terminated)
      _transaction = Transaction.stringTerminated(
        _port!.inputStream as Stream<Uint8List>,
        Uint8List.fromList([13, 10]), // CR, LF
      );

      // Listen for data
      _dataSubscription = _transaction!.stream.listen((String data) {
        _log('Received data: $data');
        _sendEvent(AndroidEvent.fromData(
          type: AndroidEventType.data,
          payload: data,
        ));
      });

      // Update connection status
      _sendEvent(AndroidEvent.fromData(
        type: AndroidEventType.status,
        payload: true,
      ));

      _log('Connected to device: ${device.productName}');
    } catch (e) {
      _log('Error connecting to device: $e');
      await _disconnect();
    }
  }

  Future<void> _disconnect() async {
    _log('Disconnecting...');

    if (_dataSubscription != null) {
      await _dataSubscription!.cancel();
      _dataSubscription = null;
    }

    if (_transaction != null) {
      _transaction!.dispose();
      _transaction = null;
    }

    if (_port != null) {
      await _port!.close();
      _port = null;
    }

    _device = null;

    // Update connection status
    _sendEvent(AndroidEvent.fromData(
      type: AndroidEventType.status,
      payload: false,
    ));

    _log('Disconnected');
  }

  Future<bool> sendData(Uint8List data) async {
    if (_port == null) {
      _log('Cannot send data: Not connected');
      return false;
    }

    try {
      _log('Sending data: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      final result = await _port!.write(data);
      _log('Data sent successfully');
      return true;
    } catch (e) {
      _log('Error sending data: $e');
      return false;
    }
  }

  Future<bool> sendString(String text) async {
    final data = Uint8List.fromList([...text.codeUnits, 13, 10]); // Add CR+LF
    return sendData(data);
  }

  void _sendEvent(AndroidEvent event) {
    _eventController.add(event);
  }

  void _log(String message) {
    debugPrint('AndroidUSB: $message');
    _logController.add(message);
  }

  // Public API
  Stream<AndroidEvent> get eventStream => _eventController.stream;

  Stream<String> get logStream => _logController.stream;

  Stream<String> get dataStream =>
      eventStream.where((event) => event.type == AndroidEventType.data).map((event) => event.payload as String);

  Stream<bool> get connectionStream =>
      eventStream.where((event) => event.type == AndroidEventType.status).map((event) => event.payload as bool);

  Stream<Map<String, String>> get deviceInfoStream => eventStream
      .where((event) => event.type == AndroidEventType.deviceInfo)
      .map((event) => event.payload as Map<String, String>);

  Future<List<UsbDevice>> getAvailableDevices() async {
    return await UsbSerial.listDevices();
  }

  void dispose() {
    _dataSubscription?.cancel();
    _usbEventSubscription?.cancel();
    _disconnect();
    _eventController.close();
    _logController.close();
  }
}
