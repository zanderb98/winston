//
//  BaseCache.swift
//  winston
//
//  Created by Igor Marcossi on 20/09/23.
//

import Foundation
import Combine
import SwiftUI

struct CacheItem<T>: Identifiable, Equatable {
  static func == (lhs: CacheItem<T>, rhs: CacheItem<T>) -> Bool {
    lhs.id == rhs.id
  }
  
  let id = UUID()
  let data: T
  let createdAt: Date
}


class BaseCache<T: Any>: ObservableObject {
  @Published var cache: [String: CacheItem<T>] = [:]
  let cacheLimit: Int
  
  init(cacheLimit: Int = 50, cache: [String:CacheItem<T>] = [:]) {
    self.cacheLimit = cacheLimit
    self.cache = cache
  }
  
  func addKeyValue(key: String, data: @escaping () -> T) {
    if !cache[key].isNil { return }
    Task(priority: .background) {
      let itemData = data()
      // Create a new CacheItem with the current date
      let item = CacheItem(data: itemData, createdAt: Date())
      let oldestKey = cache.count > cacheLimit ? cache.min { a, b in a.value.createdAt < b.value.createdAt }?.key : nil
      
      // Add the item to the cache
      await MainActor.run {
        withAnimation {
          cache[key] = item
          if let oldestKey = oldestKey { cache.removeValue(forKey: oldestKey) }
        }
      }
    }
  }
  
  func merge(_ dict: [String:T]) async {
      let newDict = dict.mapValues { CacheItem(data: $0, createdAt: Date()) }
      await MainActor.run { [newDict] in
        withAnimation {
          cache.merge(newDict) { (_, new) in new }
        }
      }
  }
  
}

class BaseObservableCache<T: ObservableObject>: ObservableObject {
  @Published var cache: [String: CacheItem<T>] = [:]
  let cacheLimit: Int
  
  init(cacheLimit: Int = 50, cache: [String:CacheItem<T>] = [:]) {
    self.cacheLimit = cacheLimit
    self.cache = cache
  }
  
  func addKeyValue(key: String, data: @escaping () -> T) {
    if !cache[key].isNil { return }
    Task(priority: .background) {
      let itemData = data()
      // Create a new CacheItem with the current date
      let item = CacheItem(data: itemData, createdAt: Date())
      let oldestKey = cache.count > cacheLimit ? cache.min { a, b in a.value.createdAt < b.value.createdAt }?.key : nil
      
      // Add the item to the cache
      await MainActor.run {
        withAnimation {
          cache[key] = item
          if let oldestKey = oldestKey { cache.removeValue(forKey: oldestKey) }
        }
      }
    }
  }
  
}
