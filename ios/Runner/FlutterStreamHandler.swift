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
    public var isReady: Bool {
        return eventSink != nil
    }
    
    // Buffer for data received before Flutter is ready
    private var dataBuffer: [Data] = []
    
    func startMonitoring() {
        CDCDeviceManager.shared.delegate = self
        CDCDeviceManager.shared.startServer()
        processBufferedData()
    }
    
    func bufferData(_ data: Data) {
        dataBuffer.append(data)
        print("📦 Buffered data packet (size: \(data.count) bytes), buffer now contains \(dataBuffer.count) packets")
    }
    
    func processBufferedData() {
        guard !dataBuffer.isEmpty else { return }
        
        print("🔄 Processing \(dataBuffer.count) buffered data packets")
        let bufferedData = dataBuffer
        dataBuffer = []
        
        // Process each buffered data packet
        for data in bufferedData {
            didReceiveData(data)
        }
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
            if let sink = self?.eventSink {
                sink(data)
            } else {
                print("⚠️ Event sink not available, can't send event")
            }
        }
    }
}

extension DataService: CDCDeviceManagerDelegate {
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
        CDCDeviceManager.shared.stopServer()
        return nil
    }
}
