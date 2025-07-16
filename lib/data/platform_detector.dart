import 'dart:io';
import 'package:injectable/injectable.dart';

enum PlatformType {
  android,
  ios,
  unsupported,
}

@singleton
class PlatformDetector {
  PlatformType get currentPlatform {
    if (Platform.isAndroid) {
      return PlatformType.android;
    } else if (Platform.isIOS) {
      return PlatformType.ios;
    } else {
      return PlatformType.unsupported;
    }
  }

  bool get isAndroid => currentPlatform == PlatformType.android;
  bool get isIOS => currentPlatform == PlatformType.ios;
  bool get isSupported => currentPlatform != PlatformType.unsupported;
}
