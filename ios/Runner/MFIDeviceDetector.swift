//
//  DeviceDetector.swift
//  Runner
//
//  Created by Ali Aynechian on 1/8/1404 AP.
//

import ExternalAccessory
import UIKit
import Flutter

class MFiDeviceManager: NSObject {
  static let shared = MFiDeviceManager()
  private let accessoryManager = EAAccessoryManager.shared()
  private var connectedAccessory: EAAccessory?
  private var session: EASession?
  private var inputStream: InputStream?
  private var outputStream: OutputStream?
  private var logChannel: FlutterMethodChannel?
  private let supportedProtocols = ["io.zanis.usb"]
  private var isReconnecting = false
  private var reconnectTimer: Timer?
  private let maxReconnectAttempts = 3
  private var reconnectAttempts = 0
  private var isInitialized = false

  override init() {
    super.init()
    setupNotifications()
  }

  private func setupNotifications() {
    // Register for app state changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
  }

  @objc private func applicationDidBecomeActive() {
    log("App became active - checking for connected accessories")
    checkConnectedAccessories()
  }

  @objc private func applicationWillResignActive() {
    log("App will resign active - cleaning up")
    stopReconnectionTimer()
  }

  func setLogChannel(_ channel: FlutterMethodChannel) {
    logChannel = channel
    if !isInitialized {
      initializeDeviceDetection()
    }
    
    // Check for already connected accessories even if already initialized
    DispatchQueue.main.async { [weak self] in
      self?.checkConnectedAccessories()
    }
  }

  private func initializeDeviceDetection() {
    guard !isInitialized else { return }
    
    // Initialize connection status to disconnected
    DataService.shared.connectionStatusChanged(false)
    
    // Register for accessory notifications
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(accessoryConnected(_:)),
      name: .EAAccessoryDidConnect,
      object: nil
    )
    
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(accessoryDisconnected(_:)),
      name: .EAAccessoryDidDisconnect,
      object: nil
    )
    
    accessoryManager.registerForLocalNotifications()
    isInitialized = true
    log("MFi device detection initialized")
    
    // Check for already connected accessories
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in 
      self?.checkConnectedAccessories()
    }
  }

  func startMonitoring() {
    if !isInitialized {
      initializeDeviceDetection()
    }
    log("Started monitoring for MFi devices")
  }

  private func checkConnectedAccessories() {
    let accessories = accessoryManager.connectedAccessories
    if accessories.isEmpty {
      log("No MFi accessories currently connected")
      return
    }
    
    log("Found \(accessories.count) connected accessories")
    for accessory in accessories {
      log("Checking accessory: \(accessory.name)")
      if let protocolString = findSupportedProtocol(for: accessory) {
        log("Found supported accessory: \(accessory.name) (Protocol: \(protocolString))")
        handleAccessoryConnected(accessory)
      } else {
        log("Accessory \(accessory.name) does not support required protocol")
        log("Available protocols: \(accessory.protocolStrings.joined(separator: ", "))")
      }
    }
  }

  private func log(_ message: String) {
    print("MFi: \(message)")
    DispatchQueue.main.async {
      self.logChannel?.invokeMethod("log", arguments: message)
    }
  }

  private func findSupportedProtocol(for accessory: EAAccessory) -> String? {
    return accessory.protocolStrings.first { protocolString in
      supportedProtocols.contains(protocolString)
    }
  }

  @objc func accessoryConnected(_ notification: Notification) {
    guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory else {
      log("⚠️ Failed to get accessory from notification")
      return
    }
    handleAccessoryConnected(accessory)
  }

  @objc func accessoryDisconnected(_ notification: Notification) {
    guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory else {
      log("⚠️ Failed to get accessory from notification")
      return
    }
    
    if accessory == connectedAccessory {
      log("🔌 Accessory disconnected: \(accessory.name)")
      disconnectFromAccessory()
      
      // Start reconnection attempts if not already trying
      if !isReconnecting {
        startReconnectionTimer()
      }
    }
  }

  private func startReconnectionTimer() {
    isReconnecting = true
    reconnectAttempts = 0
    reconnectTimer?.invalidate()
    
    reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      
      self.reconnectAttempts += 1
      self.log("Attempting to reconnect (Attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts))")
      
      if let accessory = self.accessoryManager.connectedAccessories.first(where: { self.findSupportedProtocol(for: $0) != nil }) {
        self.handleAccessoryConnected(accessory)
        self.stopReconnectionTimer()
      } else if self.reconnectAttempts >= self.maxReconnectAttempts {
        self.log("❌ Max reconnection attempts reached")
        self.stopReconnectionTimer()
      }
    }
  }

  private func stopReconnectionTimer() {
    reconnectTimer?.invalidate()
    reconnectTimer = nil
    isReconnecting = false
    reconnectAttempts = 0
  }

  private func handleAccessoryConnected(_ accessory: EAAccessory) {
    // Log detailed accessory information
    log("📱 Accessory Details:")
    log("   Name: \(accessory.name)")
    log("   Manufacturer: \(accessory.manufacturer)")
    log("   Model Number: \(accessory.modelNumber)")
    log("   Serial Number: \(accessory.serialNumber)")
    log("   Firmware Version: \(accessory.firmwareRevision)")
    log("   Hardware Version: \(accessory.hardwareRevision)")
    
    let (vid, pid) = extractVIDPID(from: accessory)
    let message = "🔌 MFi Device Connected: VID=\(vid ?? "unknown"), PID=\(pid ?? "unknown")"
    log(message)
    
    // Send device info to Flutter
    DataService.shared.sendDeviceInfo(vid: vid, pid: pid)
    
    // Always try to connect to the accessory
    if let currentAccessory = connectedAccessory {
      // Check if this is the same device we're already connected to
      if currentAccessory.connectionID == accessory.connectionID {
        log("Already connected to this accessory, refreshing connection")
        disconnectFromAccessory()
      } else {
        log("New accessory detected, switching connection")
        disconnectFromAccessory()
      }
    }
    
    // Connect to the accessory
    connectToAccessory(accessory)
  }

  private func connectToAccessory(_ accessory: EAAccessory) {
    // Find a supported protocol
    guard let protocolString = findSupportedProtocol(for: accessory) else {
      log("⚠️ No supported protocols found for accessory")
      log("   Available protocols: \(accessory.protocolStrings.joined(separator: ", "))")
      DataService.shared.connectionStatusChanged(false)
      return
    }
    
    // Create a session for the accessory
    session = EASession(accessory: accessory, forProtocol: protocolString)
    guard let session = session else {
      log("⚠️ Failed to create session for accessory")
      DataService.shared.connectionStatusChanged(false)
      return
    }
    
    // Get the input and output streams
    inputStream = session.inputStream
    outputStream = session.outputStream
    
    guard let input = inputStream, let output = outputStream else {
      log("⚠️ Failed to get streams from session")
      DataService.shared.connectionStatusChanged(false)
      return
    }
    
    // Configure and open the streams
    input.delegate = self
    output.delegate = self
    
    // Important: Schedule streams before opening them
    input.schedule(in: .main, forMode: .default)
    output.schedule(in: .main, forMode: .default)
    
    // Open streams with a slight delay between them to prevent timing issues
    input.open()
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      output.open()
    }
    
    connectedAccessory = accessory
    log("✅ Connected to MFi device using protocol: \(protocolString)")
    
    // Update connection status to connected after successful connection
    DataService.shared.connectionStatusChanged(true)
    
    // Stop any ongoing reconnection attempts
    stopReconnectionTimer()
    
    // Initiate a read after a short delay to ensure stream is ready
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      self?.readData()
    }
  }

  private func disconnectFromAccessory() {
    inputStream?.close()
    outputStream?.close()
    inputStream?.remove(from: .main, forMode: .default)
    outputStream?.remove(from: .main, forMode: .default)
    
    inputStream = nil
    outputStream = nil
    session = nil
    connectedAccessory = nil
    
    // Update connection status to disconnected
    DataService.shared.connectionStatusChanged(false)
    
    log("❌ Disconnected from MFi device")
  }

  public func extractVIDPID(from accessory: EAAccessory) -> (vid: String?, pid: String?) {
    var vid: String?
    var pid: String?
    
    for protocolString in accessory.protocolStrings {
      let components = protocolString.components(separatedBy: ".")
      for component in components {
        if component.hasPrefix("vid"), let value = component.components(separatedBy: "vid").last {
          vid = value
        }
        if component.hasPrefix("pid"), let value = component.components(separatedBy: "pid").last {
          pid = value
        }
      }
    }
    
    return (vid, pid)
  }

  func sendData(_ data: Data) {
    guard let outputStream = outputStream else {
      log("⚠️ Cannot send data: No output stream available")
      return
    }
    
    // Log data being sent
    log("📤 Sending data: \(data.map { String(format: "%02x", $0) }.joined())")
    
    var bytesRemaining = data.count
    var bytesSent = 0
    
    while bytesRemaining > 0 {
      let bytesWritten = data.withUnsafeBytes { buffer in
        outputStream.write(
          buffer.bindMemory(to: UInt8.self).baseAddress!.advanced(by: bytesSent),
          maxLength: bytesRemaining
        )
      }
      
      if bytesWritten < 0 {
        if let error = outputStream.streamError {
          log("⚠️ Error sending data: \(error.localizedDescription)")
          if let nsError = error as? NSError {
            log("⚠️ Error domain: \(nsError.domain)")
            log("⚠️ Error code: \(nsError.code)")
          }
        } else {
          log("⚠️ Error sending data (no error details available)")
        }
        return
      } else if bytesWritten == 0 {
        log("⚠️ No bytes written to stream")
        return
      }
      
      bytesRemaining -= bytesWritten
      bytesSent += bytesWritten
      
      // Log progress
      log("📤 Sent \(bytesSent) of \(data.count) bytes")
    }
    
    log("📤 Successfully sent \(bytesSent) bytes to MFi device")
  }
}

extension MFiDeviceManager: StreamDelegate {
  func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {
    case .openCompleted:
      log("Stream opened successfully")
      // Start reading immediately after stream opens
      if aStream == inputStream {
        // Allow a short delay for the stream to fully initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          self?.readData()
        }
      }
    case .hasBytesAvailable:
      if aStream == inputStream {
        readData()
      }
    case .hasSpaceAvailable:
      if aStream == outputStream {
        log("Output stream ready for writing")
      }
    case .errorOccurred:
      if let error = aStream.streamError {
        log("⚠️ Stream error: \(error.localizedDescription)")
        if let nsError = error as? NSError {
          log("⚠️ Error domain: \(nsError.domain)")
          log("⚠️ Error code: \(nsError.code)")
        }
      } else {
        log("⚠️ Stream error occurred (no error details available)")
      }
      handleStreamError(aStream)
    case .endEncountered:
      log("Stream ended")
      handleStreamError(aStream)
    default:
      break
    }
  }
  
  private func handleStreamError(_ stream: Stream) {
    log("Handling stream error and attempting recovery")
    // Try to recover the stream if possible
    if stream == inputStream {
      // Attempt to reopen input stream
      inputStream?.open()
    } else if stream == outputStream {
      // Attempt to reopen output stream
      outputStream?.open()
    }
    
    // If stream is completely broken, disconnect and try to reconnect
    if stream.streamStatus == .error || stream.streamStatus == .closed {
      disconnectFromAccessory()
      if !isReconnecting {
        startReconnectionTimer()
      }
    }
  }
  
  private func readData() {
    guard let inputStream = inputStream, inputStream.streamStatus == .open else {
      log("⚠️ Cannot read data: Input stream not ready (status: \(inputStream?.streamStatus.rawValue.description ?? "nil"))")
      return
    }
    
    let bufferSize = 4096 // Increased buffer size
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    
    // Continue reading as long as there are bytes available
    while inputStream.hasBytesAvailable {
      let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
      
      if bytesRead > 0 {
        let data = Data(bytes: buffer, count: bytesRead)
        processReceivedData(data)
        
        // Log successful read
        log("📥 Successfully read \(bytesRead) bytes from stream")
      } else if bytesRead < 0 {
        if let error = inputStream.streamError {
          log("⚠️ Error reading from stream: \(error.localizedDescription)")
          if let nsError = error as? NSError {
            log("⚠️ Error domain: \(nsError.domain)")
            log("⚠️ Error code: \(nsError.code)")
          }
        } else {
          log("⚠️ Error reading from stream (no error details available)")
        }
        handleStreamError(inputStream)
        break
      } else {
        // bytesRead == 0, which means end of stream
        log("End of stream reached")
        break
      }
    }
    
    // Schedule another read after a short delay to ensure continuous reading
    if inputStream.streamStatus == .open {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        self?.readData()
      }
    }
  }
  
  private func processReceivedData(_ data: Data) {
    // Log raw data for debugging
    log("📥 Received raw data: \(data.map { String(format: "%02x", $0) }.joined())")
    
    // Try to convert to string if possible
    if let stringData = String(data: data, encoding: .utf8) {
      log("📥 Received string data: \(stringData)")
    }
    
    // Forward data to Flutter immediately on the main thread
    DispatchQueue.main.async {
      DataService.shared.didReceiveData(data)
    }
  }
}

