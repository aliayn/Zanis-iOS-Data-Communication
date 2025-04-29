import 'package:flutter/material.dart';
import 'package:get/route_manager.dart';
import 'package:zanis_ios_data_communication/home/widget/home_screen.dart';
import 'package:zanis_ios_data_communication/utils/error_handler.dart';
import 'mfi_monitor.dart';

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
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MFi Device Monitor'),
      ),
      body: const MFIMonitor(),
    );
  }
}
