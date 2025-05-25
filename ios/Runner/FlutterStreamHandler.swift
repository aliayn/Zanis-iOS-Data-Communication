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
    public var isReady: Bool = false // Changed to manually track readiness
    
    // Buffer for data received before Flutter is ready
    private var dataBuffer: [Data] = []
    private var connectionStatusBuffer: Bool? = nil
    private var deviceInfoBuffer: [String: String]? = nil
    
    func startMonitoring() {
        CDCDeviceManager.shared.delegate = self
        CDCDeviceManager.shared.startServer()
        
        // Mark as ready
        isReady = true
        
        // Process any buffered data
        processBufferedData()
    }
    
    func bufferData(_ data: Data) {
        dataBuffer.append(data)
        print("📦 Buffered data packet (size: \(data.count) bytes), buffer now contains \(dataBuffer.count) packets")
    }
    
    func bufferConnectionStatus(_ isConnected: Bool) {
        connectionStatusBuffer = isConnected
        print("📦 Buffered connection status: \(isConnected)")
    }
    
    func bufferDeviceInfo(vid: String?, pid: String?) {
        deviceInfoBuffer = ["vid": vid ?? "unknown", "pid": pid ?? "unknown"]
        print("📦 Buffered device info: VID=\(vid ?? "unknown"), PID=\(pid ?? "unknown")")
    }
    
    func processBufferedData() {
        // First, send connection status if buffered
        if let status = connectionStatusBuffer {
            connectionStatusChanged(status)
            connectionStatusBuffer = nil
        }
        
        // Then, send device info if buffered
        if let info = deviceInfoBuffer {
            sendDeviceInfo(vid: info["vid"], pid: info["pid"])
            deviceInfoBuffer = nil
        }
        
        // Finally, process buffered data packets
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
        
        // If not ready, buffer the device info
        if !isReady {
            bufferDeviceInfo(vid: vid, pid: pid)
            return
        }
        
        sendEvent(deviceInfo)
    }
    
    private func sendEvent(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            if let sink = self?.eventSink, self?.isReady == true {
                sink(data)
            } else {
                print("⚠️ Event sink not available or service not ready, can't send event")
                
                // If this was connection status data, buffer it
                if let type = data["type"] as? String, type == "status",
                   let connected = data["connected"] as? Bool {
                    self?.bufferConnectionStatus(connected)
                }
                // If this was device info data, buffer it
                else if let type = data["type"] as? String, type == "deviceInfo",
                        let vid = data["vid"] as? String,
                        let pid = data["pid"] as? String {
                    self?.bufferDeviceInfo(vid: vid, pid: pid)
                }
                // If this was regular data, buffer it if it can be converted back to Data
                else if let type = data["type"] as? String, type == "data",
                        let base64String = data["data"] as? String,
                        let decodedData = Data(base64Encoded: base64String) {
                    self?.bufferData(decodedData)
                }
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
        
        // If not ready, buffer the data
        if !isReady || eventSink == nil {
            bufferData(data)
            return
        }
        
        print("📤 Forwarding data packet: \(payload["timestamp"]!)")
        sendEvent(payload)
    }
    
    func connectionStatusChanged(_ isConnected: Bool) {
        let status: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "connected": isConnected,
            "type": "status"
        ]
        
        // If not ready, buffer the status
        if !isReady || eventSink == nil {
            bufferConnectionStatus(isConnected)
            return
        }
        
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
