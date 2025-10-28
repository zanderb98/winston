//
//  fetchSubPosts.swift
//  winston
//
//  Created by Igor Marcossi on 28/06/23.
//

import Foundation
import Alamofire
import Defaults

extension RedditAPI {
  func fetchSubPosts(_ id: String, limit: Int = Defaults[.SubredditFeedDefSettings].chunkLoadSize, sort: SubListingSortOption = .best, after: String? = nil) async -> ([ListingChild<Either<PostData, CommentData>>]?, String?)? {
      let subID = buildSubID(id, sort, after)
      let params = FetchSubPostsPayload(limit: limit, after: after)
          
      let urlString = "\(RedditAPI.redditApiURLBase)\(subID)".replacingOccurrences(of: " ", with: "%20")
      print("[API] fetchSubPosts - GET \(subID.replacingOccurrences(of: " ", with: "%20")), params: \(params)")

      switch await self.doRequest(urlString, method: .get, params: params, paramsLocation: .queryString, decodable: Listing<Either<PostData, CommentData>>.self)  {
      case .success(let data):
        return (data.data?.children, data.data?.after)
      case .failure(let error):
        print(error)
        return nil
      }
  }
  
  func fetchSavedPosts(_ id: String, after: String? = nil, searchText: String? = nil) async -> [Either<PostData, CommentData>]? {
    let subID = buildSubID(id, nil, after, searchText)
    let limit = Defaults[.SubredditFeedDefSettings].chunkLoadSize
    let params = FetchSubsPayload(limit: limit, after: after)
    
    let urlString = "\(RedditAPI.redditApiURLBase)\(subID)".replacingOccurrences(of: " ", with: "%20")
    
    switch await self.doRequest(urlString, method: .get, params: params, paramsLocation: .queryString, decodable: Listing<Either<PostData, CommentData>>.self)  {
    case .success(let data):
      return data.data?.children?.map { $0.data }.compactMap { $0 }
    case .failure(let error):
      print(error)
      return nil
    }
  }
  
  private func buildSubID(_ id: String, _ sort: SubListingSortOption?, _ after: String?, _ searchText: String? = nil) -> String {
    var subID = ""
  
    if id != savedKeyword {
      subID = id == "" ? "/" : id.hasPrefix("/r/") ? id : "/r/\(id)"
    } else if let username = RedditAPI.shared.me?.data?.name {
      subID = "/user/\(username)/saved"
    } else {
      print("Sub ID failed to build. Invalid logic... content will fail to loa d.")
    }
    
    subID = !subID.hasSuffix("/") ? "\(subID)/" : subID
    
    subID += getSortAndSearchSuffix(sort, searchText)
    
    if let after = after {
      subID += subID.contains("?") ? "&after=\(after)" : "?after=\(after)"
    }
    
    return subID
  }
    
    func getSortAndSearchSuffix(_ sort: SubListingSortOption? = nil, _ searchText: String? = nil) -> String {
      var suffix = ""
      
      if searchText != nil {
        suffix += "search.json"
      } else {
        if let sort = sort {
          switch sort {
          case .best:
              suffix += "best.json"
          case .hot:
              suffix += "hot.json"
          case .new:
              suffix += "new.json"
          case .top(let topSortOption):
              suffix += "top.json"
              suffix += buildTopSortQuery(topSortOption)
          case .controversial:
              suffix += "controversial.json"
          }
        }
      }
      
      if let searchText = searchText {
          suffix += suffix.contains("?") ? "&q=\(searchText)" : "?q=\(searchText)"
          suffix += "&restrict_sr=on"
        
        // Add preferred sort to search url
          suffix += "&sort=\(Defaults[.SubredditFeedDefSettings].preferredSearchSort)"
      }
      
      return suffix
  }
    
  private func buildTopSortQuery(_ topSortOption: SubListingSortOption.TopListingSortOption) -> String {
    switch topSortOption {
    case .hour:
      return "?t=hour"
    case .day:
      return "?t=day"
    case .week:
      return "?t=week"
    case .month:
      return "?t=month"
    case .year:
      return "?t=year"
    case .all:
      return "?t=all"
    }
  }
  
  struct FetchSubPostsPayload: Codable {
    var limit: Int
    var after: String?
    var count: Int
    var f: String?
    var raw_json: Int
    
    init(limit: Int, after: String? = nil, count: Int = 0, flair: String? = nil, raw_json: Int = 1) {
      self.limit = limit
      self.after = after
      self.count = count
      if let flair {
        self.f = "flair_name:\"\(flair)\""
      }
      self.raw_json = raw_json
    }
  }
}

