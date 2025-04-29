import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:typed_data';

class MFIMonitor extends StatefulWidget {
  const MFIMonitor({super.key});

  @override
  State<MFIMonitor> createState() => _MFIMonitorState();
}

class _MFIMonitorState extends State<MFIMonitor> {
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  final MethodChannel _logChannel = const MethodChannel('com.zanis.device/logs');
  final MethodChannel _deviceChannel = const MethodChannel('com.zanis.device');
  bool _isConnected = false;
  String _deviceInfo = 'No device connected';

  @override
  void initState() {
    super.initState();
    _setupChannels();
  }

  void _setupChannels() {
    _logChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'log') {
        final String message = call.arguments;
        setState(() {
          _logs.add(message);
          if (_logs.length > 100) {
            _logs.removeAt(0);
          }
          _updateDeviceStatus(message);
        });
        // Scroll to bottom when new log arrives
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  void _updateDeviceStatus(String message) {
    if (message.contains('Connected to MFi device')) {
      _isConnected = true;
    } else if (message.contains('Disconnected from MFi device')) {
      _isConnected = false;
      _deviceInfo = 'No device connected';
    } else if (message.contains('MFi Device Connected')) {
      _deviceInfo = message;
    }
  }

  Future<void> _sendTestData() async {
    if (!_isConnected) return;

    try {
      final Uint8List data = Uint8List.fromList([0x01, 0x02, 0x03]);
      await _deviceChannel.invokeMethod('sendData', data);
    } catch (e) {
      setState(() {
        _logs.add('Error sending data: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Device Status Card
        Card(
          margin: const EdgeInsets.all(8.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isConnected ? Icons.check_circle : Icons.error,
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
              ],
            ),
          ),
        ),

        // Logs Section
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'MFi Device Logs',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _logs.clear();
                          });
                        },
                        child: const Text('Clear Logs'),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 4.0,
                        ),
                        child: Text(
                          log,
                          style: TextStyle(
                            color: log.contains('⚠️')
                                ? Colors.orange
                                : log.contains('❌')
                                    ? Colors.red
                                    : log.contains('✅')
                                        ? Colors.green
                                        : Colors.black,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Test Button
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton(
            onPressed: _isConnected ? _sendTestData : null,
            child: const Text('Send Test Data'),
          ),
        ),
      ],
    );
  }
}
