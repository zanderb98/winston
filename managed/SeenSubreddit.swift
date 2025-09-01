import CoreData
import Foundation

@objc(SeenSubreddit)
public class SeenSubreddit: NSManagedObject {
    @NSManaged public var subId: String
    @NSManaged public var postIdsWithDates: [String: Date]?
    
    var safePostIdsWithDates: [String: Date] {
        get { return postIdsWithDates ?? [:] }
        set { postIdsWithDates = newValue }
    }
    
    // Backward compatibility - get just the post IDs
    var postIds: [String] {
        return Array(safePostIdsWithDates.keys)
    }
    
    func addPostId(_ postId: String) {
        var currentDict = safePostIdsWithDates
        currentDict[postId] = Date()
        postIdsWithDates = currentDict
    }
    
    func removePostId(_ postId: String) {
        var currentDict = safePostIdsWithDates
        currentDict.removeValue(forKey: postId)
        postIdsWithDates = currentDict
    }
    
    func hasPostId(_ postId: String) -> Bool {
        return safePostIdsWithDates.keys.contains(postId)
    }
    
    /// Remove posts older than specified number of days
    func removeOldPosts(olderThanDays days: Int = 7) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var currentDict = safePostIdsWithDates
        
        // Filter out old posts
        currentDict = currentDict.filter { _, date in
            date >= cutoffDate
        }
        
        postIdsWithDates = currentDict
    }
    
    /// Get count of posts that will be cleaned up
    func getOldPostsCount(olderThanDays days: Int = 7) -> Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return safePostIdsWithDates.filter { _, date in date < cutoffDate }.count
    }
}

class SeenSubredditManager {
    static let shared = SeenSubredditManager()
    
    private init() {}
    
    var context: NSManagedObjectContext {
        return PersistenceController.shared.container.viewContext
    }
    
    func saveContext() {
        context.performAndWait {
            if context.hasChanges {
                do {
                    try context.save()
                } catch {
                    let nsError = error as NSError
                    print("Failed to save context: \(nsError), \(nsError.userInfo)")
                }
            }
        }
    }
    
    // MARK: - Post Seen Function
    func postSeen(subId: String, postId: String) {
        let seenSubreddit = fetchOrCreateSeenSubreddit(subId: subId)
        
        // Only add if not already present
        if !seenSubreddit.hasPostId(postId) {
            seenSubreddit.addPostId(postId)
            saveContext()
        }
    }
  
    func postsSeen(subId: String, newPostIds: [String]) {
      let seenSubreddit = fetchOrCreateSeenSubreddit(subId: subId)
      
      // Only add if not already present
      var postAdded = false
      for postId in newPostIds {
        if !seenSubreddit.hasPostId(postId) {
          seenSubreddit.addPostId(postId)
          postAdded = true
        }
      }
      
      if postAdded {
        saveContext()
      }
    }
    
    // MARK: - Get Seen Posts Function
    func getSeenPosts(for subId: String) -> [String] {
        var result: [String] = []
        
        context.performAndWait {
            guard let entity = NSEntityDescription.entity(forEntityName: "SeenSubreddit", in: context) else {
                print("SeenSubreddit entity not found")
                return
            }
            
            let request = NSFetchRequest<SeenSubreddit>()
            request.entity = entity
            request.predicate = NSPredicate(format: "subId == %@", subId)
            request.fetchLimit = 1
            
            do {
                let results = try context.fetch(request)
                if let seenSubreddit = results.first {
                    result = seenSubreddit.postIds
                }
            } catch {
                print("Error fetching SeenSubreddit: \(error)")
            }
        }
        
        return result
    }
    
    // MARK: - Get Seen Posts with Dates
    func getSeenPostsWithDates(for subId: String) -> [String: Date] {
        var result: [String: Date] = [:]
        
        context.performAndWait {
            guard let entity = NSEntityDescription.entity(forEntityName: "SeenSubreddit", in: context) else {
                print("SeenSubreddit entity not found")
                return
            }
            
            let request = NSFetchRequest<SeenSubreddit>()
            request.entity = entity
            request.predicate = NSPredicate(format: "subId == %@", subId)
            request.fetchLimit = 1
            
            do {
                let results = try context.fetch(request)
                if let seenSubreddit = results.first {
                    result = seenSubreddit.safePostIdsWithDates
                }
            } catch {
                print("Error fetching SeenSubreddit: \(error)")
            }
        }
        
        return result
    }
    
    // MARK: - Private Helper Methods
    private func fetchOrCreateSeenSubreddit(subId: String) -> SeenSubreddit {
        var result: SeenSubreddit!
        
        context.performAndWait {
            guard let entity = NSEntityDescription.entity(forEntityName: "SeenSubreddit", in: context) else {
                fatalError("SeenSubreddit entity not found in Core Data model. Check your winston.xcdatamodeld file.")
            }
            
            let request = NSFetchRequest<SeenSubreddit>()
            request.entity = entity
            request.predicate = NSPredicate(format: "subId == %@", subId)
            request.fetchLimit = 1
            
            do {
                let results = try context.fetch(request)
                if let existingSubreddit = results.first {
                    result = existingSubreddit
                    return
                }
            } catch {
                print("Error fetching SeenSubreddit: \(error)")
                print("Error details: \(error.localizedDescription)")
            }
            
            // Create new SeenSubreddit if not found
            let newSeenSubreddit = SeenSubreddit(entity: entity, insertInto: context)
            newSeenSubreddit.subId = subId
            newSeenSubreddit.postIdsWithDates = [:]
            result = newSeenSubreddit
        }
        
        return result
    }
    
    // MARK: - Cleanup Functions
    
    /// Clean up posts older than specified number of days for all subreddits
    func cleanupOldPosts(olderThanDays days: Int = 7) {
        var totalCleaned = 0
        
        context.performAndWait {
            let allSubreddits = getAllSeenSubreddits()
            
            for subreddit in allSubreddits {
                let oldCount = subreddit.getOldPostsCount(olderThanDays: days)
                if oldCount > 0 {
                    subreddit.removeOldPosts(olderThanDays: days)
                    totalCleaned += oldCount
                }
            }
            
            print("Cleaned up \(totalCleaned) old seen posts across all subreddits")
            if totalCleaned > 0 {
                saveContext()
            }
        }
    }
    
    
    /// Check if a specific post has been seen
    func isPostSeen(subId: String, postId: String) -> Bool {
        let seenPosts = getSeenPosts(for: subId)
        return seenPosts.contains(postId)
    }
    
    /// Get when a post was seen (returns nil if not seen)
    func getPostSeenDate(subId: String, postId: String) -> Date? {
        let seenPostsWithDates = getSeenPostsWithDates(for: subId)
        return seenPostsWithDates[postId]
    }
    
    /// Remove a post from seen list
    func removeSeenPost(subId: String, postId: String) {
        let seenSubreddit = fetchOrCreateSeenSubreddit(subId: subId)
        seenSubreddit.removePostId(postId)
        saveContext()
    }
    
    /// Clear all seen posts for a subreddit
    func clearSeenPosts(for subId: String) {
        let seenSubreddit = fetchOrCreateSeenSubreddit(subId: subId)
        seenSubreddit.postIdsWithDates = [:]
        saveContext()
    }
    
    /// Get all seen subreddits
    func getAllSeenSubreddits() -> [SeenSubreddit] {
        guard let entity = NSEntityDescription.entity(forEntityName: "SeenSubreddit", in: context) else {
            print("SeenSubreddit entity not found")
            return []
        }
        
        let request = NSFetchRequest<SeenSubreddit>()
        request.entity = entity
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching all SeenSubreddits: \(error)")
            return []
        }
    }
    
    /// Delete a seen subreddit entirely
    func deleteSeenSubreddit(subId: String) {
        guard let entity = NSEntityDescription.entity(forEntityName: "SeenSubreddit", in: context) else {
            print("SeenSubreddit entity not found")
            return
        }
        
        let request = NSFetchRequest<SeenSubreddit>()
        request.entity = entity
        request.predicate = NSPredicate(format: "subId == %@", subId)
        
        do {
            let results = try context.fetch(request)
            for subreddit in results {
                context.delete(subreddit)
            }
            if !results.isEmpty {
                saveContext()
            }
        } catch {
            print("Error deleting SeenSubreddit: \(error)")
        }
    }
    
    /// Get statistics about seen posts
    func getSeenPostsStatistics() -> (totalSubreddits: Int, totalPosts: Int, oldPosts: Int) {
        let allSubreddits = getAllSeenSubreddits()
        let totalSubreddits = allSubreddits.count
        let totalPosts = allSubreddits.reduce(0) { $0 + $1.postIds.count }
        let oldPosts = allSubreddits.reduce(0) { $0 + $1.getOldPostsCount() }
        
        return (totalSubreddits, totalPosts, oldPosts)
    }
}
