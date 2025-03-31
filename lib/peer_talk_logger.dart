import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PeerTalkLogger {
  static const MethodChannel _channel = MethodChannel('com.zanis.peertalk/logs');

  static Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'log') {
        final message = call.arguments as String;
        debugPrint('PeerTalk: $message');
      }
    });
  }
}
