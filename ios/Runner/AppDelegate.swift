import Flutter
import UIKit
import peertalk

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // Set up PeerTalk method channel for logs
    PeerTalkManager.shared.setupFlutterMethodChannel(controller.binaryMessenger)
    
    GeneratedPluginRegistrant.register(with: self)

    // Register the stream handler for device info and data communication
    let register = self.registrar(forPlugin: "zanis_ios_data_communication")
    StreamHandlerImpl.register(registrar: register!)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
