//
//  fetchSubs.swift
//  winston
//
//  Created by Igor Marcossi on 28/06/23.
//

import Foundation
import Alamofire
import Defaults
import SwiftUI
import CoreData

func cleanSubs(_ subs: [ListingChild<SubredditData>]) -> [ListingChild<SubredditData>] {
  return subs.compactMap({ y in
    var x = y
    x.data?.description = ""
    x.data?.description_html = ""
    x.data?.public_description = ""
    x.data?.public_description_html = ""
    x.data?.submit_text_html = ""
    x.data?.submit_text = ""
    return x
  })
}

extension RedditAPI {
    
  // Simple per-credential cache for fetched subreddits
  struct SubsCacheEntry {
    let timestamp: Date
    let subs: [ListingChild<SubredditData>]
  }
  
  // In-memory cache keyed by credential ID
  private static var subsCache: [UUID: SubsCacheEntry] = [:]
  
  /// Fetch all subscribed subreddits for the current credential.
  /// - Parameters:
  ///   - after: Pagination cursor (internal use).
  ///   - accumulatedSubs: Accumulator for recursion (internal use).
  ///   - forceRefresh: If true, bypass cache and refetch from the API.
  /// - Returns: The full list of subreddits or nil on failure.
  func fetchAllSubs(after: String? = nil,
                    accumulatedSubs: [ListingChild<SubredditData>]? = nil,
                    forceRefresh: Bool = false) async -> [ListingChild<SubredditData>]? {
    // Base case: If 'after' is nil and some subs are already accumulated, simply return them.
    if let after = after, after.isEmpty, let accumulatedSubs = accumulatedSubs {
      return accumulatedSubs
    }
    
    guard let credentialID = Defaults[.GeneralDefSettings].redditCredentialSelectedID else { return [] }
    
    // Return cached value if available and not forcing refresh (only at the top-level call)
    if after == nil && !forceRefresh, let cached = RedditAPI.subsCache[credentialID] {
      return cached.subs
    }
    
    let params = FetchSubsPayload(limit: 100, after: after)
    
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/subreddits/mine/subscriber.json", method: .get, params: params, paramsLocation: .queryString, decodable: Listing<SubredditData>.self) {
    case .success(let data):
      var newAccumulatedSubs = accumulatedSubs ?? []
      if let fetchedSubs = data.data?.children {
        newAccumulatedSubs += fetchedSubs.filter { $0.data?.subreddit_type != "user" }
      }
      
      if let dataAfter = data.data?.after, !dataAfter.isEmpty {
        // Recursive call with the new 'after' value and the updated accumulated subs.
        return await fetchAllSubs(after: dataAfter, accumulatedSubs: newAccumulatedSubs, forceRefresh: forceRefresh)
      } else {
        // All subs fetched, cache and return the accumulated result
        RedditAPI.subsCache[credentialID] = SubsCacheEntry(timestamp: Date(), subs: newAccumulatedSubs)
        return newAccumulatedSubs
      }
    case .failure(let error):
      print(error)
      return accumulatedSubs
    }
  }
  
  func updateSubsInCoreData(with subs: [ListingChild<SubredditData>], deleteOthers: Bool = true) async {
    guard let credentialID = Defaults[.GeneralDefSettings].redditCredentialSelectedID else { return }
    let context = PersistenceController.shared.container.newBackgroundContext()
    
    await context.perform(schedule: .enqueued) {
      let fetchRequest = NSFetchRequest<CachedSub>(entityName: "CachedSub")
      fetchRequest.predicate = NSPredicate(format: "winstonCredentialID == %@", credentialID as CVarArg)
      do {
        let results = try context.fetch(fetchRequest)
        
        // Process the fetched results and update CoreData as needed.
        // Insert or update CachedSub entities with the fetched subs data
        
        for sub in subs.compactMap({ $0.data }) {
          if let existingSub = results.first(where: { $0.uuid == sub.name }) {
            // Update existing CachedSub
            existingSub.update(data: sub, credentialID: credentialID)
          } else {
            // Create new CachedSub
            let newSub = CachedSub(context: context)
            newSub.update(data: sub, credentialID: credentialID)
          }
        }
        
        if deleteOthers {
          let localFavorites = Defaults[.localFavorites]
          let recentlySearched = Defaults[.recentSearchedSubs]
          
          // Delete CachedSubs not present in the fetched subs
          let currentSubsSet = Set(subs.compactMap { $0.data?.name })
          results.forEach { cachedSub in
            if !currentSubsSet.contains(cachedSub.name ?? "") && !localFavorites.contains(cachedSub.name ?? "") && !recentlySearched.contains(cachedSub.name ?? "") {
              context.delete(cachedSub)
            }
          }
          
          localFavorites.forEach { subName in
            if !results.contains(where: { $0.name == subName }) {
              Defaults[.localFavorites].remove(at: Defaults[.localFavorites].firstIndex(of: subName) ?? 0)
            }
          }
        }
        
        // Save changes
        try withAnimation {
          try context.save()
        }
      } catch {
        print("Failed to fetch or save CachedSubs: \(error)")
      }
    }
  }
  
  /// Convenience to fetch (using cache unless forced) and sync to Core Data
  func fetchSubsAndSyncCoreData(forceRefresh: Bool = false) async {
    if let fetchedSubs = await fetchAllSubs(forceRefresh: forceRefresh) {
      await updateSubsInCoreData(with: fetchedSubs)
    }
  }
  
  /// Clears the cached subs for the provided credential (or current one if nil)
  func invalidateSubsCache(for credentialID: UUID? = nil) {
    let id = credentialID ?? Defaults[.GeneralDefSettings].redditCredentialSelectedID
    if let id { RedditAPI.subsCache.removeValue(forKey: id) }
  }
  
  /// Example usage in SwiftUI:
  /// .refreshable { await api.fetchSubsAndSyncCoreData(forceRefresh: true) }
  
  
  //  func fetchSubs(after: String? = nil) async -> [ListingChild<SubredditData>]? {
  //    guard let currentCredentialID = Defaults[.GeneralDefSettings].redditCredentialSelectedID else { return [] }
  //
  //    var params = FetchSubsPayload(limit: 100)
  //
  //    if let after = after {
  //      params.after = after
  //    }
  //    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/subreddits/mine/subscriber.json", method: .get, params: params, paramsLocation: .queryString, decodable: Listing<SubredditData>.self)  {
  //    case .success(let data):
  //      var finalSubs: [ListingChild<SubredditData>] = []
  //      if let dataAfter = data.data?.after, !dataAfter.isEmpty, let extraFetchedSubs = await fetchSubs(after: dataAfter) {
  //        finalSubs += extraFetchedSubs
  //      }
  //      if let fetchedSubs = data.data?.children {
  //        finalSubs += fetchedSubs
  //      }
  //      if after != nil {
  //        return finalSubs
  //      }
  //
  //      finalSubs = finalSubs.filter { $0.data?.subreddit_type != "user" }
  ////      print("aosmao", finalSubs.map { ($0.data?.name, $0.data?.display_name) })
  //      let context = PersistenceController.shared.container.viewContext
  //
  //      let fetchRequest = NSFetchRequest<CachedSub>(entityName: "CachedSub")
  //      fetchRequest.predicate = NSPredicate(format: "winstonCredentialID == %@", currentCredentialID as CVarArg)
  //      let results = (context.performAndWait { try? context.fetch(fetchRequest) }) ?? []
  //      results.forEach { cachedSub in
  //        context.performAndWait {
  //          if !finalSubs.contains(where: { listingChild in
  //            cachedSub.uuid == listingChild.data?.name
  //          }) {
  //            context.delete(cachedSub)
  //          }
  //        }
  //      }
  //
  //      await context.perform(schedule: .enqueued) {
  //        cleanSubs(finalSubs).compactMap { $0.data }.forEach { x in
  //          if let found = results.first(where: { $0.uuid == x.name }) {
  //            found.update(data: x, credentialID: currentCredentialID)
  //          } else {
  //            _ = CachedSub(data: x, context: context, credentialID: currentCredentialID)
  //          }
  //        }
  //      }
  //
  //      await context.perform(schedule: .enqueued) {
  //        try? context.save()
  //      }
  //      return nil
  //    case .failure(let error):
  //      print(error)
  //      return nil
  //    }
  //  }
  
  struct FetchSubsPayload: Codable {
    var limit: Int
    var after: String?
    //    var show = "all"
    var count = 0
    var raw_json = 1
  }
}

