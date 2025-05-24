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
    if externalAccessoryLaunch {
      print("App was launched specifically by an External Accessory")
      setenv("APP_LAUNCHED_BY_ACCESSORY", "true", 1)
    } else if launchedByAccessory {
      print("App was launched by an accessory or external source")
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
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    // Start monitoring after channels are set up
    MFiDeviceManager.shared.startMonitoring()
    
    // For app launch by accessory, start services immediately and more aggressively
    if getenv("APP_LAUNCHED_BY_ACCESSORY") != nil {
      // Trigger a read cycle after a short delay to ensure we catch any data
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        MFiDeviceManager.shared.refreshConnection()
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
