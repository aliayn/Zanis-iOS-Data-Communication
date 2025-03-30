//
//  PeerTalkManager.swift
//  Runner
//
//  Created by Ali Aynechian on 1/10/1404 AP.
//

import Foundation
import peertalk

protocol PeerTalkManagerDelegate: AnyObject {
    func didReceiveData(_ data: Data)
    func connectionStatusChanged(_ isConnected: Bool)
}

final class PeerTalkManager: NSObject, PTChannelDelegate {
    func ioFrameChannel(_ channel: PTChannel!, didReceiveFrameOfType type: UInt32, tag: UInt32, payload: PTData!) {
        // Handle different frame types
        switch type {
        case 101:  // Match the type we use for data transmission
            let data = Data(bytes: payload.data, count: Int(payload.length))
            delegate?.didReceiveData(data)
        default:
            print("Received unexpected frame type: \(type)")
            break
        }
    }
    
    static let shared = PeerTalkManager()
    weak var delegate: PeerTalkManagerDelegate?
    
    private var serverChannel: PTChannel?
    private var peerChannel: PTChannel?
    private let port: in_port_t = 2345
    
    func startServer() {
        serverChannel = PTChannel(delegate: self)
        serverChannel?.listen(onPort: port, iPv4Address: INADDR_LOOPBACK) { [weak self] error in
            if let error = error {
                print("🔴 Server start failed: \(error)")
            } else {
                print("🟢 Server listening on port \(self?.port ?? 0)")
            }
        }
    }
    
    func stopServer() {
        serverChannel?.close()
        peerChannel?.close()
        serverChannel = nil
        peerChannel = nil
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
        }
    }
    
    // MARK: - PTChannelDelegate
    func channel(_ channel: PTChannel, didAcceptConnection otherChannel: PTChannel, from address: PTAddress) {
        peerChannel?.close()
        peerChannel = otherChannel
        peerChannel?.delegate = self
        delegate?.connectionStatusChanged(true)
        print("🔗 Device connected")
    }
    
    func channelDidEnd(_ channel: PTChannel, error: Error?) {
        delegate?.connectionStatusChanged(false)
        peerChannel = nil
        print("🔌 Device disconnected")
    }
}
