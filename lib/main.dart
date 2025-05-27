import 'package:flutter/material.dart';
import 'package:get/route_manager.dart';
import 'package:zanis_ios_data_communication/data/device_data_source.dart';
import 'package:zanis_ios_data_communication/data/platform_detector.dart';
import 'package:zanis_ios_data_communication/di/injection.dart';
import 'package:zanis_ios_data_communication/home/widget/device_monitor.dart';
import 'package:zanis_ios_data_communication/utils/error_handler.dart';

void main() {
  ErrorHandler(app: MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'MFi Device Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MFi Device Monitor'),
      ),
      body: SafeArea(
        child: DeviceMonitor(
          dataSource: inject<DeviceDataSource>(),
          platformDetector: inject<PlatformDetector>(),
        ),
      ),
    );
  }
}
