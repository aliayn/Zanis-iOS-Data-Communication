import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:zanis_ios_data_communication/data/android_data_source.dart';
import 'package:zanis_ios_data_communication/data/ios_data_source.dart';

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
