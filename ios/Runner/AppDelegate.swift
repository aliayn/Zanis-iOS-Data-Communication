import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // register the stream handler
    let register = self.registrar(forPlugin: "zanis_ios_data_communication")
      StreamHandlerImpl.register(registrar: register!)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
