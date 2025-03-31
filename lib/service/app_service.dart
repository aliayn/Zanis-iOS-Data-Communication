import 'package:zanis_ios_data_communication/di/injection.dart';
import 'package:zanis_ios_data_communication/peer_talk_logger.dart';
class AppService {
  static Future<void> init()async {
    configureDependencies();
    await PeerTalkLogger.initialize();
  }
}
