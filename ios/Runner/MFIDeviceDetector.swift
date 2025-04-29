//
//  DeviceDetector.swift
//  Runner
//
//  Created by Ali Aynechian on 1/8/1404 AP.
//

import ExternalAccessory

class MFiDeviceManager: NSObject {
  static let shared = MFiDeviceManager()
  private let accessoryManager = EAAccessoryManager.shared()
  private var connectedAccessory: EAAccessory?
  private var session: EASession?
  private var inputStream: InputStream?
  private var outputStream: OutputStream?
  private var logChannel: FlutterMethodChannel?

  func setLogChannel(_ channel: FlutterMethodChannel) {
    logChannel = channel
  }

  private func log(_ message: String) {
    print("MFi: \(message)")
    logChannel?.invokeMethod("log", arguments: message)
  }

  func startMonitoring() {
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
    log("Started monitoring for MFi devices")
    
    // Check for already connected accessories
    for accessory in accessoryManager.connectedAccessories {
      handleAccessoryConnected(accessory)
    }
  }

  @objc func accessoryConnected(_ notification: Notification) {
    guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory else { return }
    handleAccessoryConnected(accessory)
  }

  @objc func accessoryDisconnected(_ notification: Notification) {
    guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory else { return }
    if accessory == connectedAccessory {
      disconnectFromAccessory()
    }
  }

  private func handleAccessoryConnected(_ accessory: EAAccessory) {
    let (vid, pid) = extractVIDPID(from: accessory)
    let message = "🔌 MFi Device Connected: VID=\(vid ?? "unknown"), PID=\(pid ?? "unknown")"
    log(message)
    DataService.shared.sendDeviceInfo(vid: vid, pid: pid)
    
    // Connect to the accessory if it's not already connected
    if connectedAccessory == nil {
      connectToAccessory(accessory)
    }
  }

  private func connectToAccessory(_ accessory: EAAccessory) {
    // Find a supported protocol
    guard let protocolString = accessory.protocolStrings.first else {
      log("⚠️ No supported protocols found for accessory")
      return
    }
    
    // Create a session for the accessory
    session = EASession(accessory: accessory, forProtocol: protocolString)
    guard let session = session else {
      log("⚠️ Failed to create session for accessory")
      return
    }
    
    // Get the input and output streams
    inputStream = session.inputStream
    outputStream = session.outputStream
    
    // Configure and open the streams
    inputStream?.delegate = self
    outputStream?.delegate = self
    
    inputStream?.schedule(in: .main, forMode: .default)
    outputStream?.schedule(in: .main, forMode: .default)
    
    inputStream?.open()
    outputStream?.open()
    
    connectedAccessory = accessory
    log("✅ Connected to MFi device")
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
    
    log("❌ Disconnected from MFi device")
  }

  public func extractVIDPID(from accessory: EAAccessory) -> (vid: String?, pid: String?) {
    for protocolString in accessory.protocolStrings {
      let components = protocolString.components(separatedBy: ".")
      for component in components {
        if component.hasPrefix("vid"), let vid = component.components(separatedBy: "vid").last {
          return (vid, nil)
        }
        if component.hasPrefix("pid"), let pid = component.components(separatedBy: "pid").last {
          return (nil, pid)
        }
      }
    }
    return (nil, nil)
  }

  func sendData(_ data: Data) {
    guard let outputStream = outputStream else {
      log("⚠️ Cannot send data: No output stream available")
      return
    }
    
    let bytesWritten = data.withUnsafeBytes { buffer in
      outputStream.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
    }
    
    if bytesWritten > 0 {
      log("📤 Sent \(bytesWritten) bytes to MFi device")
    } else {
      log("⚠️ Failed to send data to MFi device")
    }
  }
}

extension MFiDeviceManager: StreamDelegate {
  func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {
    case .openCompleted:
      log("Stream opened")
    case .hasBytesAvailable:
      if aStream == inputStream {
        readData()
      }
    case .hasSpaceAvailable:
      log("Stream has space available")
    case .errorOccurred:
      log("Stream error occurred")
      disconnectFromAccessory()
    case .endEncountered:
      log("Stream ended")
      disconnectFromAccessory()
    default:
      break
    }
  }
  
  private func readData() {
    guard let inputStream = inputStream else { return }
    
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    
    while inputStream.hasBytesAvailable {
      let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
      if bytesRead > 0 {
        let data = Data(bytes: buffer, count: bytesRead)
        log("📥 Received \(bytesRead) bytes from MFi device")
        DataService.shared.didReceiveData(data)
      }
    }
  }
}
