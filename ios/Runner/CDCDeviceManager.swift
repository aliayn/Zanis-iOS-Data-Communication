//
//  PeerTalkManager.swift
//  Runner
//
//  Created by Ali Aynechian on 1/10/1404 AP.
//

import Foundation
import Flutter
import Network
import SystemConfiguration

protocol PeerTalkManagerDelegate: AnyObject {
    func didReceiveData(_ data: Data)
    func connectionStatusChanged(_ isConnected: Bool)
    func networkInterfaceChanged(_ interface: String)
}

final class PeerTalkManager: NSObject {
    static let shared = PeerTalkManager()
    weak var delegate: PeerTalkManagerDelegate?
    
    private var flutterMethodChannel: FlutterMethodChannel?
    private var listener: NWListener?
    private var connection: NWConnection?
    private let basePort: UInt16 = 2347
    private var currentPort: UInt16 = 2347
    private var isConnected = false
    private var isServerRunning = false
    private var retryCount = 0
    private let maxRetries = 3
    private var ethernetInterface: String?
    private var pathMonitor: NWPathMonitor?
    private var ethernetPath: NWPath?
    private var monitorTimer: Timer?
    
    // Track interface states
    private struct InterfaceState: Equatable {
        let name: String
        let displayName: String
        let isUp: Bool
        let isRunning: Bool
        let ipAddress: String?
    }
    private var knownInterfaces: [InterfaceState] = []
    
    private func getInterfaceDisplayName(_ interfaceName: String) -> String {
        var displayName = interfaceName
        
        // Check if this is an Ethernet interface
        if interfaceName.hasPrefix("en") {
            if interfaceName == "en0" {
                displayName = "Wi-Fi"
            } else {
                // Any other en* interface is likely an external adapter
                displayName = "External Network Adapter"
                
                // Create a path monitor for this specific interface to get its details
                let monitor = NWPathMonitor(requiredInterfaceType: .other)
                monitor.pathUpdateHandler = { [weak self] path in
                    if let interface = path.availableInterfaces.first(where: { $0.name == interfaceName }) {
                        // Update display name based on interface properties
                        var newName = "External Network Adapter"
                        
                        // Check if interface supports various speeds
                        if interface.type == .other {
                            newName = "USB Network Adapter"
                        }
                        
                        self?.logToFlutter("📡 Interface \(interfaceName) type: \(interface.type)")
                        
                        // Update the display name if it's different
                        if displayName != newName {
                            displayName = newName
                            self?.logToFlutter("ℹ️ Updated interface name: \(newName)")
                        }
                    }
                }
                
                // Start monitoring on a background queue
                let queue = DispatchQueue(label: "com.zanis.interfaceMonitor")
                monitor.start(queue: queue)
                
                // Stop monitoring after a brief period
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    monitor.cancel()
                }
            }
        }
        
        return displayName
    }
    
    private func startNetworkMonitoring() {
        logToFlutter("🔄 Starting network monitoring...")
        
        // Cancel existing monitor and timer
        pathMonitor?.cancel()
        monitorTimer?.invalidate()
        
        // Clear known interfaces
        knownInterfaces.removeAll()
        
        // Function to check interfaces
        let checkInterfaces = { [weak self] in
            guard let self = self else { return }
            
            var addresses: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&addresses) == 0 else {
                self.logToFlutter("⚠️ Failed to get interface addresses")
                return
            }
            defer { freeifaddrs(addresses) }
            
            // Collect current interfaces
            var currentInterfaces: [InterfaceState] = []
            
            var currentAddr = addresses
            while currentAddr != nil {
                let interface = currentAddr!.pointee
                let interfaceName = String(cString: interface.ifa_name)
                
                // Check if this is an Ethernet interface (en1, en2, etc. but not en0 which is usually WiFi)
                if interfaceName.hasPrefix("en") && interfaceName != "en0" {
                    // Get interface flags
                    let flags = Int32(interface.ifa_flags)
                    let isUp = (flags & IFF_UP) != 0
                    let isRunning = (flags & IFF_RUNNING) != 0
                    
                    // Get IP address if available
                    var ipAddress: String? = nil
                    if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                        var addr = interface.ifa_addr.pointee
                        ipAddress = self.getIPAddress(from: &addr)
                    }
                    
                    // Get display name
                    let displayName = self.getInterfaceDisplayName(interfaceName)
                    
                    // Create interface state
                    let state = InterfaceState(
                        name: interfaceName,
                        displayName: displayName,
                        isUp: isUp,
                        isRunning: isRunning,
                        ipAddress: ipAddress
                    )
                    currentInterfaces.append(state)
                }
                
                currentAddr = interface.ifa_next
            }
            
            // Check for changes
            let removedInterfaces = self.knownInterfaces.filter { known in
                !currentInterfaces.contains { $0.name == known.name }
            }
            
            let newInterfaces = currentInterfaces.filter { current in
                !self.knownInterfaces.contains { $0.name == current.name }
            }
            
            let changedInterfaces = currentInterfaces.filter { current in
                if let known = self.knownInterfaces.first(where: { $0.name == current.name }) {
                    return known != current
                }
                return false
            }
            
            // Log removed interfaces
            for interface in removedInterfaces {
                self.logToFlutter("❌ USB Ethernet interface disconnected: \(interface.displayName) (\(interface.name))")
                if interface.name == self.ethernetInterface {
                    self.ethernetInterface = nil
                    self.delegate?.networkInterfaceChanged("")
                }
            }
            
            // Log new interfaces
            for interface in newInterfaces {
                self.logToFlutter("🔌 New USB Ethernet interface detected: \(interface.displayName) (\(interface.name))")
                self.logToFlutter("📡 Interface Status: \(interface.isUp ? "Up" : "Down"), \(interface.isRunning ? "Running" : "Not Running")")
                if let ip = interface.ipAddress {
                    self.logToFlutter("🌐 IP Address: \(ip)")
                } else {
                    self.logToFlutter("🌐 IP Address: Not Configured")
                }
                
                self.ethernetInterface = interface.name
                self.delegate?.networkInterfaceChanged(interface.name)
                
                // Start server if not running
                if !self.isServerRunning {
                    self.logToFlutter("🔄 New Ethernet interface available, starting server...")
                    self.startServer()
                }
            }
            
            // Log changed interfaces
            for interface in changedInterfaces {
                self.logToFlutter("📝 USB Ethernet interface changed: \(interface.displayName) (\(interface.name))")
                self.logToFlutter("📡 Interface Status: \(interface.isUp ? "Up" : "Down"), \(interface.isRunning ? "Running" : "Not Running")")
                if let ip = interface.ipAddress {
                    self.logToFlutter("🌐 IP Address: \(ip)")
                } else {
                    self.logToFlutter("🌐 IP Address: Not Configured")
                }
            }
            
            // Update known interfaces
            self.knownInterfaces = currentInterfaces
        }
        
        // Initial check
        checkInterfaces()
        
        // Set up timer to periodically check interfaces
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            checkInterfaces()
        }
        
        logToFlutter("✅ Network monitoring started")
    }
    
    private func getIPAddress(from addr: inout sockaddr) -> String? {
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(&addr, socklen_t(addr.sa_len),
                      &hostname, socklen_t(hostname.count),
                      nil, 0,
                      NI_NUMERICHOST) == 0 {
            return String(cString: hostname)
        }
        return nil
    }
    
    func setupFlutterMethodChannel(_ messenger: FlutterBinaryMessenger) {
        logToFlutter("🔄 Setting up Flutter method channel...")
        flutterMethodChannel = FlutterMethodChannel(name: "com.zanis.peertalk/logs", binaryMessenger: messenger)
        
        // Start monitoring network changes
        startNetworkMonitoring()
        
        // Start server automatically when Flutter channel is set up
        startServer()
    }
    
    private func logToFlutter(_ message: String) {
        DispatchQueue.main.async {
            self.flutterMethodChannel?.invokeMethod("log", arguments: message)
            print("TCP Server: \(message)") // Also print to console for debugging
        }
    }
    
    private func findEthernetInterface() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var current = ifaddr
        while current != nil {
            let interface = current!.pointee
            if interface.ifa_addr.pointee.sa_family == AF_INET {
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("en") {
                    return name
                }
            }
            current = interface.ifa_next
        }
        return nil
    }
    
    private func tryNextPort() -> UInt16 {
        currentPort += 1
        if currentPort > basePort + 10 { // Try up to 10 ports
            currentPort = basePort
            retryCount += 1
            if retryCount >= maxRetries {
                logToFlutter("⚠️ Maximum retry attempts reached. Please restart the app.")
                stopServer()
                return currentPort
            }
            logToFlutter("⚠️ All ports tried, starting over from base port")
        }
        return currentPort
    }
    
    func startServer() {
        // First, ensure any existing server is stopped
        stopServer()
        
        // Reset retry count
        retryCount = 0
        
        // Check if we have an Ethernet interface
        guard let interface = ethernetInterface else {
            logToFlutter("⚠️ Cannot start server: No Ethernet interface available")
            return
        }
        
        // Create TCP listener
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        func tryStartServer() {
            do {
                // Add a small delay before trying the next port
                if retryCount > 0 {
                    Thread.sleep(forTimeInterval: 1.0)
                }
                
                // Create listener with port
                listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: currentPort))
                
                // Set up state handler
                listener?.stateUpdateHandler = { [weak self] state in
                    guard let self = self else { return }
                    
                    switch state {
                    case .ready:
                        self.isServerRunning = true
                        self.retryCount = 0  // Reset retry count on success
                        self.logToFlutter("🟢 TCP Server listening on port \(self.currentPort) via \(self.ethernetInterface ?? "unknown")")
                    case .failed(let error):
                        // Check if the error is due to port being in use
                        if case .posix(let posixError) = error, posixError.rawValue == 48 {
                            // Port is in use, try next port
                            self.currentPort = self.tryNextPort()
                            if self.retryCount < self.maxRetries {
                                self.logToFlutter("Port \(self.currentPort) in use, trying port \(self.currentPort)")
                                tryStartServer()
                            }
                        } else {
                            self.logToFlutter("🔴 TCP Server failed: \(error)")
                            self.isServerRunning = false
                        }
                    case .cancelled:
                        self.logToFlutter("TCP Server cancelled")
                        self.isServerRunning = false
                    default:
                        break
                    }
                }
                
                // Set up new connection handler
                listener?.newConnectionHandler = { [weak self] connection in
                    guard let self = self else { return }
                    
                    // Close existing connection if any
                    self.connection?.cancel()
                    
                    // Store new connection
                    self.connection = connection
                    self.isConnected = true
                    self.delegate?.connectionStatusChanged(true)
                    self.logToFlutter("🔗 New client connected via \(self.ethernetInterface ?? "unknown")")
                    
                    // Set up receive handler
                    self.receiveData()
                    
                    // Start the connection
                    connection.start(queue: .main)
                }
                
                // Start the listener
                listener?.start(queue: .main)
                
            } catch {
                logToFlutter("🔴 Failed to create TCP server: \(error)")
                isServerRunning = false
                
                // Try next port on error
                if retryCount < maxRetries {
                    currentPort = tryNextPort()
                    tryStartServer()
                }
            }
        }
        
        tryStartServer()
    }
    
    func stopServer() {
        if isConnected {
            delegate?.connectionStatusChanged(false)
            isConnected = false
        }
        
        connection?.cancel()
        listener?.cancel()
        connection = nil
        listener = nil
        isServerRunning = false
        retryCount = 0
        logToFlutter("Server stopped")
    }
    
    private func receiveData() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logToFlutter("❌ Receive error: \(error)")
                self.handleConnectionError()
                return
            }
            
            if let data = content {
                self.logToFlutter("📥 Received: \(String(data: data, encoding: .utf8) ?? "binary data")")
                self.delegate?.didReceiveData(data)
                
                // Send acknowledgment
                let response = "Message received: \(String(data: data, encoding: .utf8) ?? "binary data")"
                self.sendData(response.data(using: .utf8)!)
            }
            
            if !isComplete {
                // Continue receiving
                self.receiveData()
            } else {
                self.logToFlutter("Connection closed by client")
                self.handleConnectionError()
            }
        }
    }
    
    private func handleConnectionError() {
        connection?.cancel()
        connection = nil
        if isConnected {
            isConnected = false
            delegate?.connectionStatusChanged(false)
        }
    }
    
    func sendData(_ data: Data) {
        guard let connection = connection else {
            logToFlutter("⚠️ Cannot send data: No client connected")
            return
        }
        
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logToFlutter("❌ Failed to send data: \(error)")
                self?.handleConnectionError()
            } else {
                self?.logToFlutter("📤 Sent data: \(String(data: data, encoding: .utf8) ?? "binary data")")
            }
        })
    }
    
    deinit {
        logToFlutter("🛑 Cleaning up PeerTalkManager...")
        stopServer()
        pathMonitor?.cancel()
        monitorTimer?.invalidate()
    }
}

