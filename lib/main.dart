import 'package:flutter/material.dart';
import 'package:get/route_manager.dart';
import 'package:zanis_ios_data_communication/home/widget/home_screen.dart';
import 'package:zanis_ios_data_communication/utils/error_handler.dart';

void main() {
  ErrorHandler(app: MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
