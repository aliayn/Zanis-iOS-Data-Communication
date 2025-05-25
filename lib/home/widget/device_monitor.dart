import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zanis_ios_data_communication/data/device_data_source.dart';
import 'package:zanis_ios_data_communication/data/ios_data_source.dart';
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
  final TextEditingController _sendController = TextEditingController();

  bool _isConnected = false;
  String _deviceInfo = 'No device connected';

  @override
  void initState() {
    super.initState();
    _setupStreams();

    // After a brief delay, check for buffered data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForBufferedData();
    });
  }

  void _setupStreams() {
    // Log stream
    widget.dataSource.logStream.listen((log) {
      setState(() {
        _logs.add(log);
        if (_logs.length > 100) {
          _logs.removeAt(0);
        }
        _scrollToBottom(_logScrollController);
      });
    });

    // Data stream
    widget.dataSource.dataStream.listen((data) {
      setState(() {
        _receivedData.add(data);
        if (_receivedData.length > 100) {
          _receivedData.removeAt(0);
        }
        _scrollToBottom(_dataScrollController);
      });
    });

    // Connection status stream
    widget.dataSource.connectionStream.listen((connected) {
      setState(() {
        _isConnected = connected;
      });
    });

    // Device info stream
    widget.dataSource.deviceInfoStream.listen((info) {
      setState(() {
        _deviceInfo = 'Device: VID=${info['vid']}, PID=${info['pid']}';
      });
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid hex format: $e')),
      );
    }
  }

  Future<void> _scanDevices() async {
    final devices = await widget.dataSource.getAvailableDevices();

    if (!mounted) return;

    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No USB devices found')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found ${devices.length} USB devices')),
      );
    }
  }

  Future<void> _checkForBufferedData() async {
    if (widget.platformDetector.isIOS) {
      // Get the underlying iOS data source through dependency injection
      final iosDataSource = IOSDataSource();

      // Process any buffered data (especially important when app is launched by device)
      await iosDataSource.processBufferedData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final platformName = widget.platformDetector.isAndroid
        ? 'Android'
        : widget.platformDetector.isIOS
            ? 'iOS'
            : 'Unsupported';

    return Column(
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
                  ],
                ),
                const SizedBox(height: 8),
                Text(_deviceInfo),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _scanDevices,
                  child: const Text('Scan for USB Devices'),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _sendHexData,
                      child: const Text('Send as Hex'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _sendData,
                      child: const Text('Send as Text'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    
        // Tabs for logs and received data
        Expanded(
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
                        controller: _dataScrollController,
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _receivedData.length,
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
                        controller: _logScrollController,
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _logs.length,
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
    );
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    _dataScrollController.dispose();
    _sendController.dispose();
    super.dispose();
  }
}
