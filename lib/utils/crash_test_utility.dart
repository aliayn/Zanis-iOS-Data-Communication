import 'dart:math';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashTestUtility {
  static void testBasicCrash() {
    debugPrint('🔥 Testing basic crash...');
    throw Exception('Test crash for Firebase Crashlytics');
  }

  static void testNullPointerCrash() {
    debugPrint('🔥 Testing null pointer crash...');
    String? nullString;
    // ignore: unnecessary_null_comparison
    if (nullString != null) {
      // This will never execute, but the next line will crash
    }
    nullString!.length; // This will crash with null pointer exception
  }

  static void testListIndexOutOfBounds() {
    debugPrint('🔥 Testing list index out of bounds...');
    List<String> testList = ['item1', 'item2'];
    // Access invalid index
    testList[10]; // This will crash with range error
  }

  static void testDivisionByZero() {
    debugPrint('🔥 Testing division by zero...');
    int result = 100 ~/ 0; // This will crash with division by zero
    debugPrint('Result: $result'); // Never reached
  }

  static void testCustomError() {
    debugPrint('🔥 Testing custom error...');
    throw CustomCrashException(
      'This is a custom crash test',
      errorCode: 'TEST_CRASH_001',
      userAction: 'Testing Firebase Crashlytics integration',
    );
  }

  static void testAsyncCrash() async {
    debugPrint('🔥 Testing async crash...');
    await Future.delayed(const Duration(milliseconds: 100));
    throw Exception('Async crash test for Firebase Crashlytics');
  }

  static void testStackOverflow() {
    debugPrint('🔥 Testing stack overflow...');
    _recursiveFunction(0);
  }

  static void _recursiveFunction(int count) {
    // Infinite recursion to cause stack overflow
    _recursiveFunction(count + 1);
  }

  static void testMemoryLeak() {
    debugPrint('🔥 Testing memory allocation...');
    // Create a large list to potentially cause memory issues
    List<List<int>> bigList = [];
    for (int i = 0; i < 1000000; i++) {
      bigList.add(List.generate(1000, (index) => Random().nextInt(1000)));
    }
    debugPrint('Created big list with ${bigList.length} items');
  }

  static void testNonFatalError() {
    debugPrint('🔥 Testing non-fatal error...');
    FirebaseCrashlytics.instance.recordError(
      Exception('Non-fatal test error'),
      StackTrace.current,
      fatal: false,
      information: [
        DiagnosticsProperty('test_type', 'non_fatal'),
        DiagnosticsProperty('timestamp', DateTime.now().toIso8601String()),
        DiagnosticsProperty('user_action', 'Manual crash test'),
      ],
    );
    debugPrint('Non-fatal error sent to Crashlytics');
  }

  static void testCustomLog() {
    debugPrint('🔥 Testing custom log...');
    FirebaseCrashlytics.instance.log('Custom log message for testing');
    FirebaseCrashlytics.instance.setCustomKey('test_session', 'crash_test_${DateTime.now().millisecondsSinceEpoch}');
    FirebaseCrashlytics.instance.setCustomKey('app_section', 'device_monitor');
    FirebaseCrashlytics.instance.setUserIdentifier('test_user_${Random().nextInt(1000)}');

    debugPrint('Custom logs and keys set');

    // Then trigger a crash to see the custom data
    throw Exception('Crash with custom data attached');
  }

  static void testFlutterError() {
    debugPrint('🔥 Testing Flutter-specific error...');
    // This will trigger Flutter's error handling system
    throw FlutterError('Test Flutter error for Crashlytics');
  }
}

class CustomCrashException implements Exception {
  final String message;
  final String errorCode;
  final String userAction;

  const CustomCrashException(
    this.message, {
    required this.errorCode,
    required this.userAction,
  });

  @override
  String toString() {
    return 'CustomCrashException: $message (Code: $errorCode, Action: $userAction)';
  }
}
