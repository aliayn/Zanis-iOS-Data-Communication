//
//  FlutterStreamHandler.swift
//  Runner
//
//  Created by Ali Aynechian on 12/23/1403 AP.
//
import Flutter

final class DataService {
    static let shared = DataService()
    private init() {
        // Check if app was launched by accessory
        let launchedByAccessory = ProcessInfo.processInfo.environment["APP_LAUNCHED_BY_ACCESSORY"] == "true"
        
        if launchedByAccessory {
            print("📱 DataService: App was launched by accessory - setting up aggressive buffering")
            // Start a timer to periodically check if Flutter is ready
            startFlutterReadyCheck()
        }
    }
    
    public var eventSink: FlutterEventSink?
    public var isReady: Bool = false // Changed to manually track readiness
    
    // Buffer for data received before Flutter is ready
    private var dataBuffer: [(data: Data, timestamp: TimeInterval)] = []
    private var connectionStatusBuffer: (connected: Bool, timestamp: TimeInterval)? = nil
    private var deviceInfoBuffer: (info: [String: String], timestamp: TimeInterval)? = nil
    private var flutterReadyTimer: Timer? = nil
    private var isWaitingForFlutterReady: Bool = false
    
    func startMonitoring() {
        CDCDeviceManager.shared.delegate = self
        CDCDeviceManager.shared.startServer()
        
        // Mark as ready
        isReady = true
        
        // Process any buffered data
        processBufferedData()
    }
    
    func bufferData(_ data: Data) {
        dataBuffer.append((data: data, timestamp: Date().timeIntervalSince1970))
        print("📦 Buffered data packet (size: \(data.count) bytes), buffer now contains \(dataBuffer.count) packets")
        
        // If this is the first data received and we're not already checking for Flutter readiness, start checking
        if dataBuffer.count == 1 && !isWaitingForFlutterReady {
            startFlutterReadyCheck()
        }
    }
    
    func bufferConnectionStatus(_ isConnected: Bool) {
        connectionStatusBuffer = (connected: isConnected, timestamp: Date().timeIntervalSince1970)
        print("📦 Buffered connection status: \(isConnected)")
    }
    
    func bufferDeviceInfo(vid: String?, pid: String?) {
        deviceInfoBuffer = (info: ["vid": vid ?? "unknown", "pid": pid ?? "unknown"], 
                           timestamp: Date().timeIntervalSince1970)
        print("📦 Buffered device info: VID=\(vid ?? "unknown"), PID=\(pid ?? "unknown")")
    }
    
    func processBufferedData() {
        print("🔄 DataService: Processing buffered data...")
        
        // First, send connection status if buffered
        if let status = connectionStatusBuffer {
            print("🔄 Processing buffered connection status: \(status.connected) (from \(Date(timeIntervalSince1970: status.timestamp)))")
            connectionStatusChanged(status.connected)
            connectionStatusBuffer = nil
        }
        
        // Then, send device info if buffered
        if let info = deviceInfoBuffer {
            print("🔄 Processing buffered device info: VID=\(info.info["vid"] ?? "unknown"), PID=\(info.info["pid"] ?? "unknown") (from \(Date(timeIntervalSince1970: info.timestamp)))")
            sendDeviceInfo(vid: info.info["vid"], pid: info.info["pid"])
            deviceInfoBuffer = nil
        }
        
        // Finally, process buffered data packets
        guard !dataBuffer.isEmpty else { 
            print("📦 No buffered data packets to process")
            return 
        }
        
        print("🔄 Processing \(dataBuffer.count) buffered data packets")
        
        // Sort buffered data by timestamp to ensure proper order
        let sortedBuffer = dataBuffer.sorted { $0.timestamp < $1.timestamp }
        dataBuffer = []
        
        // Process each buffered data packet
        for bufferedData in sortedBuffer {
            print("🔄 Processing buffered data packet from \(Date(timeIntervalSince1970: bufferedData.timestamp))")
            didReceiveData(bufferedData.data)
        }
        
        print("✅ Finished processing all buffered data")
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
    
    // Add a new method to start checking for Flutter readiness
    private func startFlutterReadyCheck() {
        guard !isWaitingForFlutterReady else { return }
        
        isWaitingForFlutterReady = true
        flutterReadyTimer?.invalidate()
        
        print("🕒 DataService: Starting timer to check for Flutter readiness")
        
        flutterReadyTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            if self.isReady && self.eventSink != nil {
                print("✅ DataService: Flutter is now ready, processing buffered data")
                self.processBufferedData()
                
                timer.invalidate()
                self.flutterReadyTimer = nil
                self.isWaitingForFlutterReady = false
            } else {
                print("🕒 DataService: Still waiting for Flutter to be ready...")
            }
        }
        
        // Make sure the timer works in background modes
        RunLoop.main.add(flutterReadyTimer!, forMode: .common)
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
