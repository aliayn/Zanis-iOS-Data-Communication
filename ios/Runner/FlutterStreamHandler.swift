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
    
    public var eventSink: FlutterEventSink?
    private let peerTalkManager = PeerTalkManager.shared
    
    func startMonitoring() {
        peerTalkManager.delegate = self
        peerTalkManager.startServer()
    }
    
    func sendDeviceInfo(vid: String?, pid: String?) {
        let deviceInfo: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "vid": vid ?? "unknown",
            "pid": pid ?? "unknown",
            "type": "deviceInfo"
        ]
        sendEvent(deviceInfo)
    }
    
    private func sendEvent(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(data)
        }
    }
}

extension DataService: PeerTalkManagerDelegate {
    func didReceiveData(_ data: Data) {
        // Validate data conversion
        guard data.count > 0 else {
            print("⚠️ Received empty data packet")
            return
        }
        
        let payload: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "data": data.base64EncodedString(),
            "type": "data"
        ]
        print("📤 Forwarding data packet: \(payload["timestamp"]!)")
        sendEvent(payload)
    }
    
    func connectionStatusChanged(_ isConnected: Bool) {
        let status: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "connected": isConnected,
            "type": "status"
        ]
        print("🌐 Connection status changed: \(isConnected ? "Connected" : "Disconnected")")
        sendEvent(status)
    }
    
    func networkInterfaceChanged(_ interface: String) {
        let interfaceInfo: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "interface": interface,
            "type": "networkInterface"
        ]
        print("🔌 Network interface changed: \(interface)")
        sendEvent(interfaceInfo)
    }
}

class StreamHandlerImpl: NSObject, FlutterStreamHandler {
    
    static func register(registrar: FlutterPluginRegistrar) {
        let eventChannel = FlutterEventChannel(
            name: "com.zanis.peertalk/device_info",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(StreamHandlerImpl())
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        DataService.shared.eventSink = events
        DataService.shared.startMonitoring()
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        DataService.shared.eventSink = nil
        PeerTalkManager.shared.stopServer()
        return nil
    }
}
