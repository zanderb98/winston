//
//  NetworkMonitor.swift
//  winston
//
//  Created by Zander Bobronnikov on 5/30/25.
//

import Foundation
import Network
import Defaults

@Observable
final class NetworkMonitor {
  static let shared = NetworkMonitor(start: true)
  
  private let networkMonitor = NWPathMonitor()
  private let workerQueue = DispatchQueue(label: "Monitor")
  var connectedToWifi = false
  
  init(start: Bool = true) {
      networkMonitor.pathUpdateHandler = { path in
        self.connectedToWifi = path.usesInterfaceType(.wifi)
      }
      
      if start {
        networkMonitor.start(queue: workerQueue)
      }
    }
  
  func connectedToWifiIfDataSaver() -> Bool {
    return connectedToWifi || !Defaults[.BehaviorDefSettings].dataSaver
  }
  
  static func isConnectedToWiFi() -> Bool {
      let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
      var isWiFi = false
      
      let semaphore = DispatchSemaphore(value: 0)
      
      monitor.pathUpdateHandler = { path in
          isWiFi = path.status == .satisfied
          semaphore.signal()
      }
      
      let queue = DispatchQueue(label: "WiFiCheck")
      monitor.start(queue: queue)
      
      semaphore.wait()
      monitor.cancel()
      
      return isWiFi
  }
}

