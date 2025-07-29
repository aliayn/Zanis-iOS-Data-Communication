import 'package:firebase_core/firebase_core.dart';
import 'package:zanis_ios_data_communication/di/injection.dart';
import 'package:zanis_ios_data_communication/firebase_options.dart';

class AppService {
  static Future<void> init() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    configureDependencies();
  }
}
