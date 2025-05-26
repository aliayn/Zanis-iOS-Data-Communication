import Flutter
import UIKit
import ExternalAccessory

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Check if app was launched by an accessory (using correct key names)
    let launchedByAccessory = launchOptions?[UIApplication.LaunchOptionsKey.sourceApplication] != nil ||
                             launchOptions?[UIApplication.LaunchOptionsKey.url] != nil
    
    // Check for external accessory launch using EAAccessoryKey
    let externalAccessoryLaunch = launchOptions?.keys.contains(where: { $0.rawValue == "UIApplicationLaunchOptionsAccessoryKey" }) ?? false
    
    // Additional check for EAAccessoryKey specifically
    let eaAccessoryKey: UIApplication.LaunchOptionsKey? = UIApplication.LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsAccessoryKey")
    let accessoryLaunch = launchOptions?[eaAccessoryKey!] != nil
    
    // Log the launch options for debugging
    if let options = launchOptions {
      print("App launched with options: \(options.keys.map { $0.rawValue })")
    } else {
      print("App launched without options")
    }
    
    if externalAccessoryLaunch || accessoryLaunch {
      print("🚀 App was launched specifically by an External Accessory")
      setenv("APP_LAUNCHED_BY_ACCESSORY", "true", 1)
    } else if launchedByAccessory {
      print("🚀 App was launched by an accessory or external source")
      setenv("APP_LAUNCHED_BY_ACCESSORY", "true", 1)
    }
    
    // Initialize Flutter first
    GeneratedPluginRegistrant.register(with: self)
    
    let controller = window?.rootViewController as! FlutterViewController
    
    // Register the event channel handler
    StreamHandlerImpl.register(registrar: self.registrar(forPlugin: "StreamHandlerImpl")!)
    
    // Set up log channel first
    let logChannel = FlutterMethodChannel(name: "com.zanis.device/logs", binaryMessenger: controller.binaryMessenger)
    MFiDeviceManager.shared.setLogChannel(logChannel)
    
    // Set up device communication channel
    let deviceChannel = FlutterMethodChannel(name: "com.zanis.device", binaryMessenger: controller.binaryMessenger)
    deviceChannel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "sendData":
        if let data = call.arguments as? FlutterStandardTypedData {
          MFiDeviceManager.shared.sendData(data.data)
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT",
                            message: "Expected FlutterStandardTypedData",
                            details: nil))
        }
      case "processBufferedData":
        // Process any data that was received before Flutter was ready
        DataService.shared.processBufferedData()
        result(true)
      case "refreshConnection":
        // Manually refresh the connection
        MFiDeviceManager.shared.refreshConnection()
        result(true)
      case "isReady":
        // Mark the DataService as ready to receive data
        DataService.shared.isReady = true
        // Mark Flutter as ready in the device manager
        MFiDeviceManager.shared.markFlutterReady()
        // Process any buffered data immediately
        DataService.shared.processBufferedData()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    // Start monitoring after channels are set up
    MFiDeviceManager.shared.startMonitoring()
    
    // For app launch by accessory, start services immediately and more aggressively
    if getenv("APP_LAUNCHED_BY_ACCESSORY") != nil {
      print("🚀 App launched by accessory - setting up aggressive device checking")
      
      // Make multiple attempts to refresh connection at different intervals
      for i in 1...5 {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
          print("🔄 Refresh attempt #\(i) for device connection")
          MFiDeviceManager.shared.refreshConnection()
        }
      }
      
      // Create a persistent timer to keep checking for buffered data until Flutter reports ready
      let checkBufferTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
        print("🔄 Checking buffered data during launch")
        DataService.shared.processBufferedData()
        
        // Stop after 10 seconds maximum if Flutter never becomes ready
        if timer.fireDate.timeIntervalSinceNow > 10 {
          print("⚠️ Stopping buffer check timer after timeout")
          timer.invalidate()
        }
        
        // Also stop if DataService becomes ready
        if DataService.shared.isReady {
          print("✅ DataService ready - stopping buffer check timer")
          timer.invalidate()
        }
      }
      
      // Make sure timer works in background modes
      RunLoop.main.add(checkBufferTimer, forMode: .common)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
