# Zanis iOS Data Communication

A Flutter project demonstrating bidirectional communication between Flutter and iOS native code. This project was built as a technical assessment for recruitment at Zenis company.

## Project Overview

This application showcases a platform-channel based communication mechanism between Flutter and iOS:

- Uses `EventChannel` to receive data streams from iOS native code
- Implements a data adapter pattern to transform platform-specific data
- Follows clean architecture principles with dependency injection
- Includes comprehensive unit tests

## Architecture

The application is built with the following components:

- **IOSDataSource**: Singleton class that establishes the EventChannel connection with iOS and provides a stream of data
- **IOSDataAdapter**: Transforms raw platform data into application models
- **Dependency Injection**: Uses `injectable` and `get_it` for proper dependency management
- **BLoC Pattern**: Implements state management using the BLoC/Cubit pattern

## Design Patterns

This project demonstrates the implementation of several key design patterns:

### Singleton Pattern
The `IOSDataSource` class is implemented as a singleton using the `@singleton` annotation from the injectable package, ensuring that only one instance is created and shared throughout the application:

```dart
@singleton
class IOSDataSource {
  static const EventChannel _streamChannel =
      EventChannel('zanis_ios_data_communication');
  
  // Singleton instance is managed by the dependency injection framework
}
```

### Adapter Pattern
The `IOSDataAdapter` serves as an adapter between the raw platform data and the application's domain model:

```dart
class IOSDataAdapter {
  // Adapts raw platform data to the app's data model
  static int adaptData(Map<dynamic, dynamic> rawData) {
    try {
      // Check if 'value' key exists and validate type
      if (!rawData.containsKey('value')) {
        throw FormatException('Missing required key: value');
      }
      
      final value = rawData['value'];
      if (value is! int) {
        throw FormatException('Value is not an integer: $value');
      }
      
      return value;
    } catch (e) {
      // Error handling logic
      // ...
    }
  }
}
```

### Facade Pattern
The application's architecture implements a facade pattern through the Cubit/BLoC layer, which provides a simplified interface to the complex subsystem of platform communication:

```dart
@injectable
class HomeCubit extends Cubit<HomeState> {
  final IOSDataSource _iosDataSource;
  
  HomeCubit(this._iosDataSource) : super(HomeState.initial()) {
    init();
  }
  
  // Provides a simplified facade for accessing iOS data
  void init() {
    _iosDataSource.stream.listen((data) {
      final value = IOSDataAdapter.adaptData(data);
      emit(HomeState.data(value));
    });
  }
}
```

## Technical Implementation

### Platform Channels

This project demonstrates how to properly set up platform channels for communication:

```dart
// EventChannel to receive stream data from iOS
static const EventChannel _streamChannel = 
    EventChannel('zanis_ios_data_communication');
```

### Data Transformation

The adapter pattern is used to safely transform platform data:

```dart
// Transforms platform-specific data into application models
static int adaptData(Map<dynamic, dynamic> rawData) {
  // Implementation details...
}
```

## Getting Started

### Prerequisites
- Flutter SDK (version ^3.6.1)
- Xcode (for iOS development)
- iOS device or simulator

### Installation

1. Clone the repository
```bash
git clone https://github.com/yourusername/zanis_ios_data_communication.git
```

2. Install dependencies
```bash
flutter pub get
```

3. Run the application
```bash
flutter run
```

## Testing

The project includes comprehensive unit tests for all components, with specific focus on testing the iOS data communication layer:

### iOS Data Source Tests

The `IOSDataSource` and `IOSDataAdapter` classes are thoroughly tested to ensure reliable platform communication:

```dart
group('IOSDataSource Tests', () {
  late IOSDataSource dataSource;
  
  setUp(() {
    dataSource = IOSDataSource();
    // Mock setup for EventChannel
    // ...
  });
  
  test('dataStream should receive and transform events from EventChannel', () async {
    // Tests that verify proper data reception from iOS
    // ...
  });
  
  // Additional tests
});

group('IOSDataAdapter Tests', () {
  test('adaptData should extract value from raw data', () {
    // Tests for data transformation
    // ...
  });
  
  test('adaptData should throw FormatException for invalid data', () {
    // Tests for error handling
    // ...
  });
});
```

Run all tests with:

```bash
flutter test
```

## Project Structure

```
lib/
├── data/
│   └── ios_data_source.dart  # Platform communication
├── di/
│   └── injection.dart        # Dependency injection
├── home/
│   └── cubit/               # State management
└── main.dart                # Application entry point
test/
├── data/
│   └── data_source_test.dart # Tests for iOS data communication
```

## License

This project is intended for Zenis company recruitment assessment purposes only.
