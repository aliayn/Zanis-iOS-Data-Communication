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

  func startMonitoring() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(accessoryConnected(_:)),
      name: .EAAccessoryDidConnect,
      object: nil
    )
    accessoryManager.registerForLocalNotifications()
  }

  @objc func accessoryConnected(_ notification: Notification) {
    guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory else { return }
    let (vid, pid) = extractVIDPID(from: accessory)
    // Send to Flutter
    DataService.shared.sendDeviceInfo(vid: vid, pid: pid)
  }

  private func extractVIDPID(from accessory: EAAccessory) -> (vid: String?, pid: String?) {
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
}
