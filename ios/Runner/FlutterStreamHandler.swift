//
//  FlutterStreamHandler.swift
//  Runner
//
//  Created by Ali Aynechian on 12/23/1403 AP.
//

import Flutter

final class DataService {
    static let shared = DataService()

    private init() {}

    public var eventSink : FlutterEventSink?

    func sendDeviceInfo(vid: String?, pid: String?) {
        let data :[String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "vid": vid ?? "Unknown",
            "pid": pid ?? "Unknown"
        ]
        self.eventSink?(data)
    }

}

class StreamHandlerImpl: NSObject, FlutterStreamHandler {

    /// Registers the stream handler for the event channel
    static func register(registrar: FlutterPluginRegistrar) {
        let eventChannel = FlutterEventChannel(name: "zanis_ios_data_communication", binaryMessenger: registrar.messenger())
        let streamHandler = StreamHandlerImpl()
        eventChannel.setStreamHandler(streamHandler)
    }

    @objc func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        DataService.shared.eventSink = events
        MFiDeviceManager.shared.startMonitoring()
        return nil
    }

    @objc func onCancel(withArguments arguments: Any?) -> FlutterError? {
        DataService.shared.eventSink = nil
        return nil
    }
    
}
