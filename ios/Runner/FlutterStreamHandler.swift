//
//  FlutterStreamHandler.swift
//  Runner
//
//  Created by Ali Aynechian on 12/23/1403 AP.
//

import Flutter
final class DataService {
    /// Singleton instance with proper thread safety
    static let shared = DataService()

    private init() {}

    public var eventSink : FlutterEventSink?

    func startStreaming() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        let data :[String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "value": Int.random(in: 0...100),
            "type": "random"
        ]
            self.eventSink?(data)
        }
    }

}

class StreamHandlerImpl: NSObject, FlutterStreamHandler {

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "zanis_ios_data_communication", binaryMessenger: registrar.messenger())
        let instance = StreamHandlerImpl()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }


    @objc func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        DataService.shared.eventSink = events
        DataService.shared.startStreaming()
        return nil
    }

    @objc func onCancel(withArguments arguments: Any?) -> FlutterError? {
        DataService.shared.eventSink = nil
        return nil
    }
    
}