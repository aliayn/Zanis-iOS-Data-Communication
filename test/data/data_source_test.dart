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
        'zanis_ios_data_communication',
        (ByteData? message) async {
          final MethodCall methodCall = const StandardMethodCodec().decodeMethodCall(message!);
          log.add(methodCall);

          // If it's a listen call, return a mock stream
          if (methodCall.method == 'listen') {
            // Send a mock event
            await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
              'zanis_ios_data_communication',
              const StandardMethodCodec().encodeSuccessEnvelope(<String, dynamic>{
                'timestamp': 1630000000.0,
                'value': 42,
                'type': 'random',
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
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'zanis_ios_data_communication', 
        null
      );
    });

    test('dataStream should receive and transform events from EventChannel', () async {
      // Listen to the data stream
      final receivedData = await dataSource.stream.first;

      // Verify the expected data was received
      expect(receivedData, isA<Map>());
      expect(receivedData['timestamp'], 1630000000.0);
      expect(receivedData['value'], 42);
      expect(receivedData['type'], 'random');
    });

    test('dataStream should handle errors', () async {
      // Setup error case
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'zanis_ios_data_communication',
        (ByteData? message) async {
          final MethodCall methodCall = const StandardMethodCodec().decodeMethodCall(message!);
          if (methodCall.method == 'listen') {
            await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
              'zanis_ios_data_communication',
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

      // Expect an error when listening to the stream
      expectLater(dataSource.stream, emitsError(isA<PlatformException>()));
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