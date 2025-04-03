import 'package:zanis_ios_data_communication/di/injection.dart';

class AppService {
  static Future<void> init() async {
    configureDependencies();
  }
}
