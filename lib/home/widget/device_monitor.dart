import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zanis_ios_data_communication/data/device_data_source.dart';
import 'package:zanis_ios_data_communication/data/platform_detector.dart';

class DeviceMonitor extends StatefulWidget {
  final DeviceDataSource dataSource;
  final PlatformDetector platformDetector;

  const DeviceMonitor({
    super.key,
    required this.dataSource,
    required this.platformDetector,
  });

  @override
  State<DeviceMonitor> createState() => _DeviceMonitorState();
}

class _DeviceMonitorState extends State<DeviceMonitor> {
  final List<String> _logs = [];
  final List<String> _receivedData = [];
  final ScrollController _logScrollController = ScrollController();
  final ScrollController _dataScrollController = ScrollController();
  final ScrollController _mainScrollController = ScrollController();
  final TextEditingController _sendController = TextEditingController();

  bool _isConnected = false;
  bool _isConnecting = false;
  String _deviceInfo = 'No device connected';
  CommunicationType _communicationType = CommunicationType.usbSerial;
  List<Map<String, dynamic>> _availableDevices = [];
  Map<String, dynamic>? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _setupStreams();

    // After a brief delay, check for buffered data (iOS only) and scan devices
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForBufferedData();
      _scanDevices(); // Automatically scan for devices on startup
    });
  }

  void _setupStreams() {
    // Log stream
    widget.dataSource.logStream.listen(
      (log) {
        if (mounted) {
          setState(() {
            _logs.add('${DateTime.now().toString().substring(11, 19)}: $log');
            if (_logs.length > 100) {
              _logs.removeAt(0);
            }
            _scrollToBottom(_logScrollController);
          });
        }
      },
      onError: (error) {
        _log('Log stream error: $error');
      },
    );

    // Data stream
    widget.dataSource.dataStream.listen(
      (data) {
        if (mounted) {
          setState(() {
            _receivedData.add('${DateTime.now().toString().substring(11, 19)}: $data');
            if (_receivedData.length > 100) {
              _receivedData.removeAt(0);
            }
            _scrollToBottom(_dataScrollController);
          });
        }
      },
      onError: (error) {
        _log('Data stream error: $error');
      },
    );

    // Connection status stream
    widget.dataSource.connectionStream.listen(
      (connected) {
        if (mounted) {
          setState(() {
            _isConnected = connected;
          });

          // Show connection status change
          if (connected) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('USB Device Connected'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('USB Device Disconnected'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      },
      onError: (error) {
        _log('Connection stream error: $error');
      },
    );

    // Device info stream
    widget.dataSource.deviceInfoStream.listen(
      (info) {
        if (mounted) {
          setState(() {
            _deviceInfo =
                'Device: VID=${info['vid']}, PID=${info['pid']}${(info['hasEndpoints'] as bool?) == true ? ' (Endpoints: Yes)' : ' (Endpoints: No)'}';
          });
        }
      },
      onError: (error) {
        _log('Device info stream error: $error');
      },
    );

    // Vendor USB specific streams (only for Android)
    if (widget.platformDetector.isAndroid) {
      widget.dataSource.bulkTransferStream.listen(
        (result) {
          if (mounted) {
            setState(() {
              _logs.add('${DateTime.now().toString().substring(11, 19)}: Bulk Transfer Result: $result');
              _scrollToBottom(_logScrollController);
            });
          }
        },
        onError: (error) {
          _log('Bulk transfer stream error: $error');
        },
      );

      widget.dataSource.interruptTransferStream.listen(
        (result) {
          if (mounted) {
            setState(() {
              _logs.add('${DateTime.now().toString().substring(11, 19)}: Interrupt Transfer Result: $result');
              _scrollToBottom(_logScrollController);
            });
          }
        },
        onError: (error) {
          _log('Interrupt transfer stream error: $error');
        },
      );
    }
  }

  void _scrollToBottom(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.animateTo(
          controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _switchCommunicationType(CommunicationType? type) {
    if (type != null && type != _communicationType) {
      setState(() {
        _communicationType = type;
      });
      widget.dataSource.setCommunicationType(type);
    }
  }

  Future<void> _sendData() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No device connected')),
      );
      return;
    }

    final text = _sendController.text.trim();
    if (text.isEmpty) return;

    // Send as string
    await widget.dataSource.sendString(text);
    _sendController.clear();
  }

  Future<void> _sendHexData() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No device connected')),
      );
      return;
    }

    final text = _sendController.text.trim();
    if (text.isEmpty) return;

    try {
      // Parse hex string and send as binary
      final hexValues = text.split(' ').map((e) => int.parse(e.replaceAll('0x', ''), radix: 16)).toList();

      await widget.dataSource.sendData(Uint8List.fromList(hexValues));
      _sendController.clear();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid hex format: $e')),
        );
      }
    }
  }

  Future<void> _sendBulkTransfer() async {
    if (_communicationType != CommunicationType.vendorUsb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bulk transfer only available in Vendor USB mode')),
        );
      }
      return;
    }

    if (!_isConnected) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No device connected')),
        );
      }
      return;
    }

    final text = _sendController.text.trim();
    if (text.isEmpty) return;

    try {
      final hexValues = text.split(' ').map((e) => int.parse(e.replaceAll('0x', ''), radix: 16)).toList();
      await widget.dataSource.sendBulkTransfer(Uint8List.fromList(hexValues));
      _sendController.clear();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bulk transfer failed: $e')),
        );
      }
    }
  }

  Future<void> _sendInterruptTransfer() async {
    if (_communicationType != CommunicationType.vendorUsb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Interrupt transfer only available in Vendor USB mode')),
        );
      }
      return;
    }

    if (!_isConnected) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No device connected')),
        );
      }
      return;
    }

    final text = _sendController.text.trim();
    if (text.isEmpty) return;

    try {
      final hexValues = text.split(' ').map((e) => int.parse(e.replaceAll('0x', ''), radix: 16)).toList();
      await widget.dataSource.sendInterruptTransfer(Uint8List.fromList(hexValues));
      _sendController.clear();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Interrupt transfer failed: $e')),
        );
      }
    }
  }

  Future<void> _scanDevices() async {
    try {
      _log('Scanning for USB devices...');
      final devices = await widget.dataSource.getAvailableDevices();

      if (!mounted) return;

      setState(() {
        _availableDevices = devices.map((device) => Map<String, dynamic>.from(device)).toList();
      });

      if (devices.isEmpty) {
        if (mounted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No USB devices found'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
        _log('No USB devices found');
      } else {
        if (mounted) {
          if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Found ${devices.length} USB devices'),
                backgroundColor: Colors.blue,
              ),
            );
          }
        }
        _log('Found ${devices.length} USB devices');

        // Log device details and auto-select first device if none selected
        for (final device in devices) {
          _log('Device: ${device['productName']} (VID: ${device['vendorId']}, PID: ${device['productId']})');
        }

        // Auto-select first device if none selected
        if (_selectedDevice == null && devices.isNotEmpty) {
          setState(() {
            _selectedDevice = Map<String, dynamic>.from(devices.first);
          });
        }
      }
    } catch (e) {
      _log('Error scanning devices: $e');
      if (mounted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
            content: Text('Error scanning devices: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _connectToDevice() async {
    if (_selectedDevice == null) {
      if (mounted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
            content: Text('Please select a device first'),
            backgroundColor: Colors.orange,
          ),
          );
        }
      }
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      _log('Connecting to device: ${_selectedDevice!['productName']}');

      final success = await widget.dataSource.connectToDevice(_selectedDevice!);

      if (mounted) {
        if (success) {
          _log('Successfully connected to device');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connected to device'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          _log('Failed to connect to device');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect to device'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      _log('Error connecting to device: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _disconnectDevice() async {
    try {
      _log('Disconnecting from device...');

      final success = await widget.dataSource.disconnectDevice();

      if (mounted) {
        if (success) {
          _log('Successfully disconnected from device');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Disconnected from device'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          _log('Disconnect command sent (connection status will update via stream)');
        }
      }
    } catch (e) {
      _log('Error disconnecting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnect error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _checkForBufferedData() async {
    // Buffered data processing is handled automatically by the data source layers
    // No manual intervention needed for Android or iOS
    _log('Data source initialization complete');
  }

  void _log(String message) {
    debugPrint('DeviceMonitor: $message');
  }

  @override
  Widget build(BuildContext context) {
    final platformName = widget.platformDetector.isAndroid
        ? 'Android'
        : widget.platformDetector.isIOS
            ? 'iOS'
            : 'Unsupported';

    return SingleChildScrollView(
      controller: _mainScrollController,
      child: Column(
        children: [
          // Platform and connection info
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Platform: $platformName', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),

                  // Communication type selector (Android only)
                  if (widget.platformDetector.isAndroid) ...[
                    Text('Communication Type:', style: Theme.of(context).textTheme.titleSmall),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<CommunicationType>(
                            title: const Text('USB Serial'),
                            value: CommunicationType.usbSerial,
                            groupValue: _communicationType,
                            onChanged: _switchCommunicationType,
                            dense: true,
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<CommunicationType>(
                            title: const Text('Vendor USB'),
                            value: CommunicationType.vendorUsb,
                            groupValue: _communicationType,
                            onChanged: _switchCommunicationType,
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  Row(
                    children: [
                      Icon(
                        _isConnected ? Icons.usb : Icons.usb_off,
                        color: _isConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isConnected ? 'Connected' : 'Disconnected',
                        style: TextStyle(
                          color: _isConnected ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Mode: ${_communicationType == CommunicationType.usbSerial ? 'Serial' : 'Vendor'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_deviceInfo),
                  const SizedBox(height: 8),

                  // Device selection dropdown
                  if (_availableDevices.isNotEmpty) ...[
                    Text('Available Devices:', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    DropdownButton<Map<String, dynamic>>(
                      isExpanded: true,
                      value: _selectedDevice,
                      hint: const Text('Select a device'),
                      items: _availableDevices.map((device) {
                        return DropdownMenuItem<Map<String, dynamic>>(
                          value: device,
                          child: Text(
                            '${device['productName'] ?? 'Unknown'} (VID: 0x${device['vendorId']?.toRadixString(16).padLeft(4, '0').toUpperCase()}, PID: 0x${device['productId']?.toRadixString(16).padLeft(4, '0').toUpperCase()})',
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: (device) {
                        setState(() {
                          _selectedDevice = device;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Action buttons
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _scanDevices,
                        child: const Text('Scan Devices'),
                      ),
                      if (!_isConnected && !_isConnecting && _selectedDevice != null)
                        ElevatedButton(
                          onPressed: _connectToDevice,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Connect'),
                        ),
                      if (_isConnecting)
                        ElevatedButton(
                          onPressed: null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Connecting...'),
                            ],
                          ),
                        ),
                      if (_isConnected)
                        ElevatedButton(
                          onPressed: _disconnectDevice,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Disconnect'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Send data
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Send Data', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sendController,
                    decoration: const InputDecoration(
                      hintText: 'Enter text or hex (e.g., "0x01 0x02 0x03")',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendData(),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _sendData,
                        child: const Text('Send as Text'),
                      ),
                      TextButton(
                        onPressed: _sendHexData,
                        child: const Text('Send as Hex'),
                      ),
                      // Vendor USB specific buttons
                      if (widget.platformDetector.isAndroid && _communicationType == CommunicationType.vendorUsb) ...[
                        TextButton(
                          onPressed: _sendBulkTransfer,
                          child: const Text('Bulk Transfer'),
                        ),
                        TextButton(
                          onPressed: _sendInterruptTransfer,
                          child: const Text('Interrupt Transfer'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Tabs for logs and received data
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5, // Fixed height for the tab content
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Received Data'),
                      Tab(text: 'Logs'),
                    ],
                    labelColor: Colors.blue,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Received data tab
                        ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(8.0),
                          itemCount: _receivedData.length,
                          shrinkWrap: true,
                          itemBuilder: (context, index) {
                            return ListTile(
                              dense: true,
                              title: Text(
                                _receivedData[index],
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            );
                          },
                        ),

                        // Logs tab
                        ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(8.0),
                          itemCount: _logs.length,
                          shrinkWrap: true,
                          itemBuilder: (context, index) {
                            return ListTile(
                              dense: true,
                              title: Text(
                                _logs[index],
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    _dataScrollController.dispose();
    _mainScrollController.dispose();
    _sendController.dispose();
    super.dispose();
  }
}
