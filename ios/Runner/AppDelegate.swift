import Flutter
import UIKit
import ExternalAccessory

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize MFi device manager
    MFiDeviceManager.shared.startMonitoring()
    
    // Initialize Flutter
    GeneratedPluginRegistrant.register(with: self)
    
    let controller = window?.rootViewController as! FlutterViewController
    
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    // Set up log channel
    let logChannel = FlutterMethodChannel(name: "com.zanis.device/logs", binaryMessenger: controller.binaryMessenger)
    MFiDeviceManager.shared.setLogChannel(logChannel)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
