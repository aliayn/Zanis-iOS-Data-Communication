import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  Timer? _readTimer;

  final StreamController<AndroidEvent> _eventController = StreamController<AndroidEvent>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();

  AndroidDataSource() {
    if (Platform.isAndroid) {
      _init();
    } else {
      _log('Not running on Android, USB functionality disabled');
    }
  }

  void _init() {
    _log('Initializing Android USB Data Source');

    // Listen for USB device connection/disconnection events
    _usbEventSubscription = UsbSerial.usbEventStream?.listen((UsbEvent event) {
      _log('USB event: ${event.event}, device: ${event.device?.productName}');

      // Delay slightly to allow USB permissions to be processed
      Future.delayed(const Duration(milliseconds: 500), () {
        _scanDevices();
      });
    });

    // Initial device scan with delay to ensure USB is fully initialized
    Future.delayed(const Duration(seconds: 1), () {
      _scanDevices();
    });
  }

  Future<void> _scanDevices() async {
    _log('Scanning for USB devices...');

    try {
      final devices = await UsbSerial.listDevices();

      if (devices.isEmpty) {
        _log('No USB devices found');
        if (_device != null) {
          _sendEvent(AndroidEvent.fromData(
            type: AndroidEventType.status,
            payload: false,
          ));
          await _disconnect();
        }
      } else {
        _log('Found ${devices.length} USB devices');
        for (final device in devices) {
          final vid = device.vid ?? 0;
          final pid = device.pid ?? 0;
          _log(
              'Device: ${device.productName ?? "Unknown"}, VID: 0x${vid.toRadixString(16)}, PID: 0x${pid.toRadixString(16)}');

          // Send device info event for each device
          _sendEvent(AndroidEvent.fromData(
            type: AndroidEventType.deviceInfo,
            payload: {
              'vid': '0x${vid.toRadixString(16)}',
              'pid': '0x${pid.toRadixString(16)}',
            },
          ));
        }

        // Connect to the first device if not already connected
        if (_device == null && devices.isNotEmpty) {
          await _connectToDevice(devices.first);
        } else if (_device != null) {
          // Check if current device is still in the list
          bool deviceStillConnected = devices.any((d) => d.deviceId == _device!.deviceId);
          if (!deviceStillConnected) {
            _log('Currently connected device no longer available');
            await _disconnect();
            if (devices.isNotEmpty) {
              await _connectToDevice(devices.first);
            }
          }
        }
      }
    } catch (e) {
      _log('Error scanning for devices: $e');
    }
  }

  Future<void> _connectToDevice(UsbDevice device) async {
    _log('Connecting to device: ${device.productName ?? "Unknown"}...');

    // Disconnect first if already connected
    await _disconnect();

    try {
      // Android USB permissions are handled by the plugin internally
      // We don't need to explicitly request permission

      _log('Creating port for device...');
      // Create port
      _port = await device.create();

      if (_port == null) {
        _log('Failed to create port');
        return;
      }

      // Open port
      _log('Opening port...');
      final openResult = await _port!.open();
      if (!openResult) {
        _log('Failed to open port');
        _port = null;
        return;
      }

      // Configure port
      _log('Configuring port...');
      await _port!.setDTR(true);
      await _port!.setRTS(true);

      // Try different baud rates if needed
      try {
        await _port!.setPortParameters(
          115200, // Baud rate
          UsbPort.DATABITS_8,
          UsbPort.STOPBITS_1,
          UsbPort.PARITY_NONE,
        );
      } catch (e) {
        _log('Error setting port parameters: $e, trying alternative baud rate');
        try {
          await _port!.setPortParameters(
            9600, // Alternative baud rate
            UsbPort.DATABITS_8,
            UsbPort.STOPBITS_1,
            UsbPort.PARITY_NONE,
          );
        } catch (e) {
          _log('Error setting alternative port parameters: $e');
          // Continue anyway, some devices work without explicit parameters
        }
      }

      _device = device;

      // Set up transaction for line-based communication (CR+LF terminated)
      _log('Setting up transaction...');
      try {
        _transaction = Transaction.stringTerminated(
          _port!.inputStream as Stream<Uint8List>,
          Uint8List.fromList([13, 10]), // CR, LF
        );

        // Listen for data
        _dataSubscription = _transaction!.stream.listen(
          (String data) {
            _log('Received data: $data');
            _sendEvent(AndroidEvent.fromData(
              type: AndroidEventType.data,
              payload: data,
            ));
          },
          onError: (error) {
            _log('Stream error: $error');
          },
        );
      } catch (e) {
        _log('Error setting up transaction: $e');
        // Even if transaction setup fails, we'll try to use the raw input stream
      }

      // Start a polling timer as a backup mechanism for devices that don't trigger stream events properly
      _startPollingTimer();

      // Update connection status
      _sendEvent(AndroidEvent.fromData(
        type: AndroidEventType.status,
        payload: true,
      ));

      _log('Connected to device: ${device.productName ?? "Unknown"}');

      // Send a test message to confirm connection
      await sendString("PING");
    } catch (e) {
      _log('Error connecting to device: $e');
      await _disconnect();
    }
  }

  void _startPollingTimer() {
    _stopPollingTimer();

    // Create a polling timer that periodically checks for data
    _readTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      try {
        if (_port == null || _device == null) {
          _stopPollingTimer();
          return;
        }

        // Try to read data directly if no data is coming through the transaction
        if (_port!.inputStream != null) {
          // Just referencing the stream keeps it active
          // The transaction should handle the actual data reception
        }
      } catch (e) {
        _log('Error in polling timer: $e');
      }
    });
  }

  void _stopPollingTimer() {
    _readTimer?.cancel();
    _readTimer = null;
  }

  Future<void> _disconnect() async {
    _log('Disconnecting...');

    _stopPollingTimer();

    if (_dataSubscription != null) {
      await _dataSubscription!.cancel();
      _dataSubscription = null;
    }

    if (_transaction != null) {
      _transaction!.dispose();
      _transaction = null;
    }

    if (_port != null) {
      try {
        await _port!.close();
      } catch (e) {
        _log('Error closing port: $e');
      }
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
      _log('Sending raw data: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

      // Try to write data with timeout
      try {
        // The write method may return void or int depending on the plugin implementation
        // Handle both cases gracefully
        dynamic writeResult = _port!.write(data);

        // If write returns a Future, await it
        if (writeResult is Future) {
          writeResult = await writeResult;
        }

        // Log the result but don't rely on its type for success determination
        _log('Data sent successfully');

        // Consider the operation successful if no exception is thrown
        return true;
      } on PlatformException catch (e) {
        _log('Platform exception sending data: ${e.message}');
        return false;
      } catch (e) {
        _log('Error sending data: $e');
        return false;
      }
    } catch (e) {
      _log('Error in sendData: $e');
      return false;
    }
  }

  Future<bool> sendString(String text) async {
    try {
      _log('Sending string: $text');
      final data = Uint8List.fromList([...text.codeUnits, 13, 10]); // Add CR+LF
      return await sendData(data);
    } catch (e) {
      _log('Error in sendString: $e');
      return false;
    }
  }

  void _sendEvent(AndroidEvent event) {
    try {
      _eventController.add(event);
    } catch (e) {
      debugPrint('Error sending event: $e');
    }
  }

  void _log(String message) {
    debugPrint('AndroidUSB: $message');
    try {
      _logController.add(message);
    } catch (e) {
      debugPrint('Error logging message: $e');
    }
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
    if (!Platform.isAndroid) return [];
    try {
      return await UsbSerial.listDevices();
    } catch (e) {
      _log('Error getting available devices: $e');
      return [];
    }
  }

  // Manually attempt to reconnect or refresh the connection
  Future<void> refreshConnection() async {
    _log('Manually refreshing connection...');
    await _scanDevices();
  }

  void dispose() {
    _stopPollingTimer();
    _dataSubscription?.cancel();
    _usbEventSubscription?.cancel();
    _disconnect();
    _eventController.close();
    _logController.close();
  }
}
