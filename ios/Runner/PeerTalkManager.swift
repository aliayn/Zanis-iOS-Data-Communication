//
//  PeerTalkManager.swift
//  Runner
//
//  Created by Ali Aynechian on 1/10/1404 AP.
//

import Foundation
import Flutter
import Network

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
    
    func setupFlutterMethodChannel(_ messenger: FlutterBinaryMessenger) {
        flutterMethodChannel = FlutterMethodChannel(name: "com.zanis.peertalk/logs", binaryMessenger: messenger)
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
        
        // Find Ethernet interface
        ethernetInterface = findEthernetInterface()
        if let interface = ethernetInterface {
            delegate?.networkInterfaceChanged(interface)
            logToFlutter("🔌 Found Ethernet interface: \(interface)")
        } else {
            logToFlutter("⚠️ No Ethernet interface found")
            return
        }
        
        // Create TCP listener with Ethernet interface
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        // Set interface
        if let interface = ethernetInterface {
            parameters.requiredInterface = NWInterface(interface)
        }
        
        func tryStartServer() {
            do {
                // Add a small delay before trying the next port
                if retryCount > 0 {
                    Thread.sleep(forTimeInterval: 1.0)
                }
                
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
}
