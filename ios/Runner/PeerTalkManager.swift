//
//  PeerTalkManager.swift
//  Runner
//
//  Created by Ali Aynechian on 1/10/1404 AP.
//

import Foundation
import peertalk
import Flutter

protocol PeerTalkManagerDelegate: AnyObject {
    func didReceiveData(_ data: Data)
    func connectionStatusChanged(_ isConnected: Bool)
}

final class PeerTalkManager: NSObject, PTChannelDelegate {
    private var flutterMethodChannel: FlutterMethodChannel?
    
    func ioFrameChannel(_ channel: PTChannel!, didReceiveFrameOfType type: UInt32, tag: UInt32, payload: PTData!) {
        // Handle different frame types
        switch type {
        case 101:  // Match the type we use for data transmission
            let data = Data(bytes: payload.data, count: Int(payload.length))
            delegate?.didReceiveData(data)
            logToFlutter("Received data frame of size: \(data.count) bytes")
        default:
            logToFlutter("Received unexpected frame type: \(type)")
            break
        }
    }
    
    static let shared = PeerTalkManager()
    weak var delegate: PeerTalkManagerDelegate?
    
    private var serverChannel: PTChannel?
    private var peerChannel: PTChannel?
    private let basePort: in_port_t = 2345
    private var currentPort: in_port_t = 2345
    
    func setupFlutterMethodChannel(_ messenger: FlutterBinaryMessenger) {
        flutterMethodChannel = FlutterMethodChannel(name: "com.zanis.peertalk/logs", binaryMessenger: messenger)
    }
    
    private func logToFlutter(_ message: String) {
        DispatchQueue.main.async {
            self.flutterMethodChannel?.invokeMethod("log", arguments: message)
        }
    }
    
    private func tryNextPort() -> in_port_t {
        currentPort += 1
        if currentPort > basePort + 10 { // Try up to 10 ports
            currentPort = basePort
        }
        return currentPort
    }
    
    func startServer() {
        // First, ensure any existing server is stopped
        stopServer()
        
        serverChannel = PTChannel(delegate: self)
        logToFlutter("Server channel initialized")
        
        func tryStartServer() {
            serverChannel?.listen(onPort: currentPort, iPv4Address: INADDR_LOOPBACK) { [weak self] error in
                if let error = error {
                    if (error as NSError).domain == NSPOSIXErrorDomain && (error as NSError).code == 48 {
                        // Port is in use, try next port
                        self?.currentPort = self?.tryNextPort() ?? self?.basePort ?? 2345
                        self?.logToFlutter("Port \(self?.currentPort ?? 0) in use, trying port \(self?.currentPort ?? 0)")
                        tryStartServer()
                    } else {
                        self?.logToFlutter("🔴 Server start failed: \(error)")
                    }
                } else {
                    let ipAddress = "127.0.0.1" // INADDR_LOOPBACK
                    self?.logToFlutter("🟢 Server listening on IP: \(ipAddress), Port: \(self?.currentPort ?? 0)")
                }
            }
        }
        
        tryStartServer()
    }
    
    func stopServer() {
        serverChannel?.close()
        peerChannel?.close()
        serverChannel = nil
        peerChannel = nil
        logToFlutter("Server stopped")
    }
    
    func sendData(_ data: Data) {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let dispatchData = DispatchData(
                bytes: buffer
            )
            peerChannel?.sendFrame(
                ofType: 101,
                tag: PTFrameNoTag,
                withPayload: dispatchData as __DispatchData,
                callback: nil
            )
            logToFlutter("Sent data frame of size: \(data.count) bytes")
        }
    }
    
    // MARK: - PTChannelDelegate
    func channel(_ channel: PTChannel, didAcceptConnection otherChannel: PTChannel, from address: PTAddress) {
        peerChannel?.close()
        peerChannel = otherChannel
        peerChannel?.delegate = self
        delegate?.connectionStatusChanged(true)
        
        // Log connection details
        let ipAddress = address.addressString ?? "unknown"
        let port = address.port
        logToFlutter("🔗 Device connected from IP: \(ipAddress), Port: \(port)")
    }
    
    func channelDidEnd(_ channel: PTChannel, error: Error?) {
        delegate?.connectionStatusChanged(false)
        peerChannel = nil
        logToFlutter("🔌 Device disconnected")
    }
}
