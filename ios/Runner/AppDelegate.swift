import Flutter
import UIKit
import ExternalAccessory

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // Set up PeerTalk method channel for logs
    PeerTalkManager.shared.setupFlutterMethodChannel(controller.binaryMessenger)
    
    // Set up MFi Device Detector
    setupMFiDeviceDetector(controller.binaryMessenger)
    
    GeneratedPluginRegistrant.register(with: self)

    // Register the stream handler for device info and data communication
    let register = self.registrar(forPlugin: "zanis_ios_data_communication")
    StreamHandlerImpl.register(registrar: register!)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func setupMFiDeviceDetector(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.zanis.mfi/logs", binaryMessenger: messenger)
    
    // Set up MFi device monitoring
    MFiDeviceManager.shared.startMonitoring()
    
    // Log currently connected devices
    let connectedAccessories = EAAccessoryManager.shared().connectedAccessories
    for accessory in connectedAccessories {
      let (vid, pid) = MFiDeviceManager.shared.extractVIDPID(from: accessory)
      let message = "🔌 MFi Device Connected: VID=\(vid ?? "unknown"), PID=\(pid ?? "unknown")"
      channel.invokeMethod("log", arguments: message)
      print("MFi Device: \(message)")
    }
    
    // Set up notification observer for new devices
    NotificationCenter.default.addObserver(
      forName: .EAAccessoryDidConnect,
      object: nil,
      queue: .main
    ) { notification in
      if let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory {
        let (vid, pid) = MFiDeviceManager.shared.extractVIDPID(from: accessory)
        let message = "🔌 New MFi Device Connected: VID=\(vid ?? "unknown"), PID=\(pid ?? "unknown")"
        channel.invokeMethod("log", arguments: message)
        print("MFi Device: \(message)")
      }
    }
  }
}
