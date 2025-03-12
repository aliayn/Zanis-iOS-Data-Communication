import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_logger.dart';

class ErrorHandler with AppLogger {
  ErrorHandler({required Widget app}) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      // In release mode, show a minimal error widget
      // In debug mode, show more detailed error information
      if (kReleaseMode) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          color: Colors.grey[900],
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 48),
                SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'The app has encountered an unexpected error.',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      } else {
        // More detailed error widget for development
        return Container(
          padding: const EdgeInsets.all(16.0),
          color: Colors.red.shade800,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'ERROR',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(color: Colors.white30),
              const SizedBox(height: 8),
              Text(
                '${details.exception}',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    details.stack.toString(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      }
    };

    FlutterError.onError = _handleFlutterError;

    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(app);
    }, ((error, stack) {
      //add firebase crashlytics
      //FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      log.e(error);
    }));

    PlatformDispatcher.instance.onError = (error, stack) {
      //add firebase crashlytics
      //FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    if (kReleaseMode) {
      //add firebase crashlytics
      //FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      log.e(details.exception);
      Zone.current.handleUncaughtError(details.exception, details.stack!);
    } else {
      FlutterError.dumpErrorToConsole(details);
    }
  }
}
