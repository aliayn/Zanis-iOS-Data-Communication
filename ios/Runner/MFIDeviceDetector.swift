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
  private var dataQueue = [Data]()
  private var waitingForFlutterReady = false
  private var flutterReadyTimer: Timer?

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
    
    // If app was launched by device, check immediately and more aggressively
    if ProcessInfo.processInfo.environment["APP_LAUNCHED_BY_ACCESSORY"] == "true" {
      log("🚀 App was launched by accessory - initializing immediately")
      checkConnectedAccessoriesAggressively()
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
    // Use a shorter delay to check for already connected accessories when app starts
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in 
      self?.checkConnectedAccessories()
    }
  }

  func startMonitoring() {
    if !isInitialized {
      initializeDeviceDetection()
    } else {
      // If already initialized, check for connected accessories again
      checkConnectedAccessories()
    }
    log("Started monitoring for MFi devices")
  }

  func refreshConnection() {
    log("Manually refreshing connection...")
    checkConnectedAccessoriesAggressively()
    
    // Also try to restart stream reading if needed
    if let input = inputStream, input.streamStatus == .open {
      log("Refreshing input stream reading")
      readData()
    }
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
    input.schedule(in: .main, forMode: .common)
    output.schedule(in: .main, forMode: .common)
    
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
    
    // Start a continuous reading cycle - this is crucial for reliable data reception
    startContinuousReading()
  }

  // Add a continuous reading function to ensure we never miss data
  private var isReadingContinuously = false
  private var readingTimer: Timer?
  
  private func startContinuousReading() {
    stopContinuousReading()
    
    isReadingContinuously = true
    readingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      self?.readData()
    }
    
    // Make sure the timer is scheduled in the common run loop mode
    RunLoop.main.add(readingTimer!, forMode: .common)
    
    // Also try to read immediately
    readData()
    
    log("Started continuous reading cycle")
  }
  
  private func stopContinuousReading() {
    readingTimer?.invalidate()
    readingTimer = nil
    isReadingContinuously = false
  }

  private func disconnectFromAccessory() {
    // Stop continuous reading before disconnecting
    stopContinuousReading()
    
    inputStream?.close()
    outputStream?.close()
    inputStream?.remove(from: .main, forMode: .common)
    outputStream?.remove(from: .main, forMode: .common)
    
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

  // More aggressive checking for accessories when app is launched by device
  private func checkConnectedAccessoriesAggressively() {
    // Perform multiple checks with short delays to ensure we catch the device
    checkConnectedAccessories()
    
    // Follow up with additional checks
    for i in 1...10 {  // Increased from 5 to 10 checks
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) { [weak self] in
        self?.log("Aggressive check #\(i) for connected accessories")
        self?.checkConnectedAccessories()
        
        // Try to read data proactively from any connected device
        if let inputStream = self?.inputStream {
          if inputStream.streamStatus == .open {
            self?.log("Proactively reading data from input stream during aggressive check #\(i)")
            self?.readData()
          }
        }
      }
    }
  }

  private func processReceivedData(_ data: Data) {
    // Create a more human-readable representation of the data
    let hexString = data.map { String(format: "%02x", $0) }.joined(separator: " ")
    
    // Improved logging with better formatting
    log("📥 Received data (\(data.count) bytes)")
    
    // Try to convert to string and log it in a readable format
    if let stringData = String(data: data, encoding: .utf8) {
      // Clean up the string - remove control characters for display
      let cleanedString = stringData
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\t", with: "\\t")
      
      // If it contains mostly printable characters, show it as text
      let printableCharCount = stringData.unicodeScalars.filter { $0.isPrintable }.count
      // Convert data.count to Double before multiplication to avoid type conversion error
      let threshold = Double(data.count) * 0.8
      let isPrintable = Double(printableCharCount) > threshold // 80% printable = human readable
      
      if isPrintable {
        log("📥 Decoded as text: \"\(cleanedString)\"")
      } else {
        log("📥 Partially decoded (mixed binary/text): \"\(cleanedString)\"")
        log("📥 Hex representation: \(hexString)")
      }
    } else {
      // If not valid UTF-8, show as hex only
      log("📥 Binary data (hex): \(hexString)")
    }
    
    // Forward data to Flutter immediately on the main thread
    DispatchQueue.main.async {
      // Always buffer the data
      self.log("📥 Buffering received data for delivery")
      DataService.shared.bufferData(data)
      
      // If DataService is ready, process the data immediately
      if DataService.shared.isReady {
        self.log("📥 DataService is ready, processing data immediately")
        DataService.shared.processBufferedData()
      } else {
        self.log("⚠️ DataService not ready yet, data buffered for later processing")
        
        // Start a timer to check periodically if Flutter is ready
        if !self.waitingForFlutterReady {
          self.waitingForFlutterReady = true
          self.log("🕒 Starting timer to check for Flutter readiness")
          
          // Cancel any existing timer
          self.flutterReadyTimer?.invalidate()
          
          // Create a new timer that checks periodically if Flutter is ready
          self.flutterReadyTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            // Check if Flutter is ready now
            if DataService.shared.isReady {
              self.log("✅ Flutter is now ready, processing buffered data")
              DataService.shared.processBufferedData()
              
              // Stop the timer
              timer.invalidate()
              self.flutterReadyTimer = nil
              self.waitingForFlutterReady = false
            } else {
              self.log("🕒 Still waiting for Flutter to be ready...")
            }
          }
          
          // Make sure the timer works in background modes
          RunLoop.main.add(self.flutterReadyTimer!, forMode: .common)
        }
      }
    }
  }

  func markFlutterReady() {
    log("📱 Flutter engine marked as ready")
    DataService.shared.isReady = true
    
    // Process any buffered data immediately
    DispatchQueue.main.async {
      self.log("Processing buffered data after Flutter ready signal")
      DataService.shared.processBufferedData()
    }
    
    // If app was launched by device, check again for connected devices
    if ProcessInfo.processInfo.environment["APP_LAUNCHED_BY_ACCESSORY"] == "true" {
      log("🔄 App was launched by accessory - rechecking connections after Flutter ready")
      refreshConnection()
    }
  }
}

extension MFiDeviceManager: StreamDelegate {
  func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {
    case .openCompleted:
      log("Stream opened successfully: \(aStream == inputStream ? "Input Stream" : "Output Stream")")
      // Start reading immediately after stream opens
      if aStream == inputStream {
        readData()
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
      log("Stream ended: \(aStream == inputStream ? "Input Stream" : "Output Stream")")
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
    guard let inputStream = inputStream else {
      log("⚠️ Cannot read data: No input stream available")
      return
    }
    
    // Check stream status and attempt to recover if needed
    if inputStream.streamStatus != .open {
      log("⚠️ Input stream not open, current status: \(inputStream.streamStatus.rawValue)")
      
      // Try to reopen if not open
      if inputStream.streamStatus != .opening {
        log("Attempting to reopen input stream...")
        inputStream.open()
      }
      
      return
    }
    
    let bufferSize = 4096 // Increased buffer size
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    
    // Always attempt to read data, regardless of hasBytesAvailable
      let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
    
      if bytesRead > 0 {
        let data = Data(bytes: buffer, count: bytesRead)
      processReceivedData(data)
      
      // Log successful read
      log("📥 Successfully read \(bytesRead) bytes from stream")
      
      // If more data is available, continue reading
      if inputStream.hasBytesAvailable {
        // Schedule immediate follow-up read for remaining data
        DispatchQueue.main.async { [weak self] in
          self?.readData()
        }
      }
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
    } else {
      // bytesRead == 0, which means end of stream or no data
      log("No data available from stream at this moment")
    }
  }
}

// Add extension to help with character validation
extension Unicode.Scalar {
    var isPrintable: Bool {
        // Check for printable ASCII or common Unicode ranges
        return (self.value >= 32 && self.value < 127) || // Printable ASCII
               (self.value >= 0x1F600 && self.value <= 0x1F64F) || // Emoticons
               (self.value >= 0x0080 && self.value <= 0x00FF) // Latin-1 Supplement
    }
}

