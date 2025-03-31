import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanis_ios_data_communication/data/ios_data_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IOSDataSource Tests', () {
    late IOSDataSource dataSource;
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      dataSource = IOSDataSource();

      // Set up channel mocking
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'device_channel',
        (ByteData? message) async {
          final MethodCall methodCall = const StandardMethodCodec().decodeMethodCall(message!);
          log.add(methodCall);

          // If it's a listen call, return a mock stream
          if (methodCall.method == 'listen') {
            // Send mock events for each type
            await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
              'device_channel',
              const StandardMethodCodec().encodeSuccessEnvelope(<String, dynamic>{
                'timestamp': 1630000000.0,
                'data': 'base64EncodedData',
                'type': 'data',
              }),
              (_) {},
            );

            await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
              'device_channel',
              const StandardMethodCodec().encodeSuccessEnvelope(<String, dynamic>{
                'timestamp': 1630000000.0,
                'connected': true,
                'type': 'status',
              }),
              (_) {},
            );

            await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
              'device_channel',
              const StandardMethodCodec().encodeSuccessEnvelope(<String, dynamic>{
                'timestamp': 1630000000.0,
                'vid': '1234',
                'pid': '5678',
                'type': 'deviceInfo',
              }),
              (_) {},
            );
          }

          return const StandardMethodCodec().encodeSuccessEnvelope(null);
        },
      );
    });

    tearDown(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('device_channel', null);
    });

    test('dataStream should receive and transform data events', () async {
      final receivedData = await dataSource.dataStream.first;
      expect(receivedData, 'base64EncodedData');
    });

    test('connectionStream should receive and transform status events', () async {
      final isConnected = await dataSource.connectionStream.first;
      expect(isConnected, true);
    });

    test('deviceInfoStream should receive and transform device info events', () async {
      final deviceInfo = await dataSource.deviceInfoStream.first;
      expect(deviceInfo, {
        'vid': '1234',
        'pid': '5678',
      });
    });

    test('eventStream should receive all event types', () async {
      final events = await dataSource.eventStream.take(3).toList();

      expect(events.length, 3);
      expect(events[0].type, IOSEventType.data);
      expect(events[1].type, IOSEventType.status);
      expect(events[2].type, IOSEventType.deviceInfo);

      expect(events[0].payload, 'base64EncodedData');
      expect(events[1].payload, true);
      expect(events[2].payload, {
        'vid': '1234',
        'pid': '5678',
      });
    });

    test('should handle errors', () async {
      // Setup error case
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'device_channel',
        (ByteData? message) async {
          final MethodCall methodCall = const StandardMethodCodec().decodeMethodCall(message!);
          if (methodCall.method == 'listen') {
            await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
              'device_channel',
              const StandardMethodCodec().encodeErrorEnvelope(
                code: 'ERROR',
                message: 'Test error',
                details: null,
              ),
              (_) {},
            );
          }
          return const StandardMethodCodec().encodeSuccessEnvelope(null);
        },
      );

      // Expect an error when listening to any stream
      expectLater(dataSource.eventStream, emitsError(isA<PlatformException>()));
      expectLater(dataSource.dataStream, emitsError(isA<PlatformException>()));
      expectLater(dataSource.connectionStream, emitsError(isA<PlatformException>()));
      expectLater(dataSource.deviceInfoStream, emitsError(isA<PlatformException>()));
    });
  });

  group('IOSDataAdapter Tests', () {
    test('adaptData should extract value from raw data', () {
      final rawData = {
        'timestamp': 1630000000.0,
        'value': 42,
        'type': 'random',
      };

      final result = IOSDataAdapter.adaptData(rawData);
      expect(result, 42);
    });

    test('adaptData should throw FormatException for invalid data', () {
      final invalidData = {
        'timestamp': 1630000000.0,
        'type': 'random',
        // Missing 'value' key
      };

      expect(
        () => IOSDataAdapter.adaptData(invalidData),
        throwsA(isA<FormatException>()),
      );
    });

    test('adaptData should throw FormatException for non-int value', () {
      final invalidData = {
        'timestamp': 1630000000.0,
        'value': 'not an int',
        'type': 'random',
      };

      expect(
        () => IOSDataAdapter.adaptData(invalidData),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
