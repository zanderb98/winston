//
//  Post.swift
//  winston
//
//  Created by Igor Marcossi on 28/06/23.
//

import SwiftUI
import Defaults
import AVFoundation
import AlertToast
//import FoundationModels

struct PostView: View, Equatable {
  static func == (lhs: PostView, rhs: PostView) -> Bool {
    lhs.post == rhs.post && lhs.subreddit.id == rhs.subreddit.id && lhs.hideElements == rhs.hideElements && lhs.ignoreSpecificComment == rhs.ignoreSpecificComment && lhs.sort == rhs.sort && lhs.update == rhs.update && lhs.comments == rhs.comments && lhs.searchOpen == rhs.searchOpen && lhs.unseenSkipperOpen == rhs.unseenSkipperOpen && lhs.searchFocused == rhs.searchFocused && lhs.searchQuery.value == rhs.searchQuery.value && lhs.searchQuery.debounced == rhs.searchQuery.debounced && lhs.currentMatchIndex == rhs.currentMatchIndex && lhs.totalMatches == rhs.totalMatches
  }
  
  var post: Post
  var subreddit: Subreddit
  var forceCollapse: Bool
  var highlightID: String?
  @Default(.PostPageDefSettings) private var defSettings
  @Default(.CommentsSectionDefSettings) var commentsSectionDefSettings
  
  @State private var themeManager = InMemoryTheme.shared
  private var selectedTheme: WinstonTheme { themeManager.currentTheme }
  
  @Environment(\.globalLoaderStart) private var globalLoaderStart
  @State private var ignoreSpecificComment = false
  @State private var hideElements = true
  @State private var sort: CommentSortOption
  @State private var update = false
  
  @SilentState private var topVisibleCommentId: String? = nil
  @State private var topCommentIdx: Int = 0
  @SilentState private var previousScrollTarget: String? = nil
  @State private var comments: [Comment] = []
  @State private var commentUpdate: Debouncer<Int> = Debouncer(0, delay: 0.25)
  @SilentState private var flattened: [[String:String]] = []
  @SilentState private var lastFlattenedHash: Int = 0
  @SilentState private var matches: [String] = []
  // Map of comment id to target id to scroll to
  @SilentState private var matchMap: [String: String] = [:]
  @SilentState private var commentIndexMap: [String: Int] = [:]
  @State private var seenComments: String? = nil
    
  @State private var searchQuery = Debouncer("", delay: 0.25)
  @State private var searchOpen = false
  @State private var unseenSkipperOpen = false
  @State private var totalMatches = 0
  @State private var currentMatchIndex = 0
  @SilentState private var indexOfFirstMatch = 99999
  @SilentState private var currentMatchId = ""
  @SilentState private var visibleComments = Debouncer("", delay: 0.25)
  @State private var inAutoSkipMode: Bool = false
  @SilentState private var lastAppearedIdx: Int = -1
  @SilentState private var scrollDir: Bool = false  
  @FocusState private var searchFocused: Bool
  @State private var liveRefreshTask: Task<Void, Never>?
  @State private var initialLoading: Bool = true
  @State private var generatedSummary: String? = nil
  @State private var generationErrorMessage: String? = nil
  @State private var summaryStreaming: Bool = false

  init(post: Post, subreddit: Subreddit, forceCollapse: Bool = false, highlightID: String? = nil) {
    self.post = post
    self.subreddit = subreddit
    self.forceCollapse = forceCollapse
    self.highlightID = highlightID
    
    let defSettings = Defaults[.PostPageDefSettings]
    let commentsDefSettings = Defaults[.CommentsSectionDefSettings]
    
    let defaultSort = isGameThread(post.data?.title) ?
      CommentSortOption.live : commentsDefSettings.preferredSort
    _sort = State(initialValue: defSettings.perPostSort ? (defSettings.postSorts[post.id] ?? defaultSort) : defaultSort);
  }
  
  func newCommentsLoaded() {
    commentUpdate.value += 1
  }
  
  func handleLiveRefresh() {
     // Cancel any existing refresh task
     liveRefreshTask?.cancel()
     liveRefreshTask = nil
     
     // Only start live refresh for live sort
     guard sort == .live else { return }
     
     liveRefreshTask = Task { @MainActor in
       print("[LIVE] Starting live refresh task for \(self.post.data?.title ?? self.post.id)")
       
       while !Task.isCancelled && self.sort == .live {
         do {
           // Wait 5 seconds before next refresh
           try await Task.sleep(nanoseconds: 5_000_000_000)
         } catch {
           // Task was cancelled during sleep
           print("[LIVE] Live refresh task cancelled during sleep")
           break
         }
         
         // Double-check we're still in live mode and not cancelled
         guard !Task.isCancelled && self.sort == .live else {
           print("[LIVE] Live refresh task stopping - cancelled or sort changed")
           break
         }
         
         // Check if we should refresh (same logic as before)
         let shouldRefresh = self.comments.isEmpty ||
                            self.visibleComments.value.contains("|\(self.comments.first?.id ?? "")|")
         
         if shouldRefresh {
           print("[LIVE] REFRESH for \(self.post.data?.title ?? self.post.id)")
           self.updatePost()
         }
       }
       
       print("[LIVE] Live refresh task ended for \(self.post.data?.title ?? self.post.id)")
     }
   }
   
   private func stopLiveRefresh() {
     liveRefreshTask?.cancel()
     liveRefreshTask = nil
     print("[LIVE] Live refresh stopped")
   }
  
  func asyncFetch(_ reloadPost: Bool = false) async {
    var seenCommentsSet = false
    
    if initialLoading && post.winstonData != nil {
      seenComments = post.winstonData?.seenComments
      seenCommentsSet = true
    }
    
    if let result = await post.refreshPost(commentID: ignoreSpecificComment ? nil : highlightID, sort: sort, after: nil, subreddit: subreddit.data?.display_name ?? subreddit.id, full: post.data == nil || reloadPost), let newComments = result.0 {
      
      if initialLoading {
        if !seenCommentsSet {
          seenComments = post.winstonData?.seenComments
        }
        
        if let seen = seenComments, !seen.isEmpty, !isGameThread(post.data?.title) {
          unseenSkipperOpen = true
        }
      }
                  
      Task(priority: .background) {
        await RedditAPI.shared.updateCommentsWithAvatar(comments: newComments, avatarSize: selectedTheme.comments.theme.badge.avatar.size)
      }
      
      newComments.forEach { $0.parentWinston = comments }
      await MainActor.run {
        withAnimation {
          comments = newComments
          initialLoading = false
        }
      }
      
      Task(priority: .high) {
        flattenComments(true)
        updateMatches()
      }
      
      Task(priority: .background) {
        if let numComments = post.data?.num_comments {
          await post.saveCommentsCount(numComments: numComments)
        }
      }
    } else {
      await MainActor.run {
        withAnimation {
          initialLoading = false
        }
      }
    }
  }
  
  func updatePost(_ reloadPost: Bool = false, then: (() -> Void)? = nil) {
    Task(priority: .background) {
      await asyncFetch(reloadPost)
      if let then {
        then()
      }
    }
  }
  
  func refresh() {
    updatePost(true)
  }
  
  func openUnseenSkipper(_ reader: ScrollViewProxy) {
    unseenSkipperOpen = true
    currentMatchId = ""
    
    updateMatches(reader)
  }
  
  func updateVisibleComments(_ id: String, _ visible: Bool) {
    Task {
      let key = "|\(id)|"
      
      if visible {
        visibleComments.value += key
        
        if let idx = commentIndexMap[id] {
          if !inAutoSkipMode { scrollDir = idx < lastAppearedIdx }
          lastAppearedIdx = idx
        }
      } else {
        visibleComments.value = visibleComments.value.replacingOccurrences(of: key, with: "")
      }
    }
  }
  
  func updateMatchIndex(_ visible: String, force: Bool = false) {
    if inAutoSkipMode && !force { return }
    
    Task {
      flattenComments()
      
      let matchIdx = scrollDir ?
      matches.lastIndex(where: { id in visible.contains("|\(id)|") }) :
      matches.firstIndex(where: { id in visible.contains("|\(id)|") })
      
      if let matchIdx {
        currentMatchId = matches[matchIdx]

        DispatchQueue.main.async {
          withAnimation {
            currentMatchIndex = matchIdx + 1
          }
        }
      } else if visible.isEmpty || (flattened.lastIndex(where: { comment in visible.contains("|\(comment["id"]!)|") }) ?? -1) < indexOfFirstMatch {
        currentMatchId = ""

        DispatchQueue.main.async {
          withAnimation {
            currentMatchIndex = 0
          }
        }
      }
    }
  }
  
  func flattenComments(_ update: Bool = false) {
    if !update && (!flattened.isEmpty || comments.isEmpty) { return }
    
    // OPTIMIZATION: Cache the result based on comments count to avoid redundant flattening
    let commentsHash = comments.count
    if !update && lastFlattenedHash == commentsHash && !flattened.isEmpty {
      return
    }
    
    flattened = CommentUtils.shared.flattenComments(comments)
    commentIndexMap = flattened.enumerated().reduce(into: [String: Int]()) { partial, eo in
      partial[eo.element["id"]!] = eo.offset
    }
    
    CommentAutoLoadManager.shared.processIndexMapUpdate(commentIndexMap)
    
    lastFlattenedHash = commentsHash
    
    if let topVisibleCommentId {
      updateTopCommentIdx(topVisibleCommentId)
    }
  }
  
  func updateTopCommentIdx(_ id: String) {
    topCommentIdx = commentIndexMap[id] ?? 0
    CommentAutoLoadManager.shared.handleTopCommentIndexChange(topCommentIdx)
  }
  
  func updateMatches(_ reader: ScrollViewProxy? = nil) {
    let query = searchQuery.debounced
    
    if (searchOpen && query.isEmpty) || (unseenSkipperOpen && (seenComments == nil || seenComments!.isEmpty)) {
      DispatchQueue.main.async {
        withAnimation {
          currentMatchIndex = 0
          totalMatches = 0
        }
      }
      return
    }
    
    flattenComments()
    
    // OPTIMIZATION: Move the heavy filtering work to background thread
    Task.detached(priority: .background) {
      let matchingComments = await self.searchOpen ?
        self.getMatchingComments(query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) :
        self.getUnseenComments()
      
      let newMatches = matchingComments.map({ $0["id"]! })
      let newMatchMap = matchingComments.reduce(into: [String: String](), { partial, comment in
        if let id = comment["id"] {
          partial[id] = comment["target"] ?? id
        }
      })
      
      let newIndexOfFirstMatch = await self.commentIndexMap[newMatches.first ?? ""] ?? -1
      
      // Update UI on main thread
      await MainActor.run {
        self.matches = newMatches
        self.matchMap = newMatchMap
        self.indexOfFirstMatch = newIndexOfFirstMatch
        
        withAnimation {
          self.totalMatches = newMatches.count
        }
        
        // Keep your existing scroll logic
        self.scrollToNextMatch(true, reader)
      }
    }
  }
  
  func getMatchingComments(_ query: String) -> [[String: String]] {
    // OPTIMIZATION: Early return for empty query
    guard !query.isEmpty else { return [] }
    
    // OPTIMIZATION: Use localizedCaseInsensitiveContains instead of .contains on lowercased strings
    // This is faster and handles international characters better
    return flattened.filter { comment in
      (comment["body"] ?? "").localizedCaseInsensitiveContains(query)
    }
  }
  
  func getUnseenComments() -> [[String: String]] {
    guard let seenComments else { return [] }
    return flattened.filter({ !seenComments.contains($0["id"]?.dropLast(2) ?? "") })
  }
  
  func scrollToNextMatch (_ forward: Bool = true, _ reader: ScrollViewProxy? = nil) {
    if searchOpen && searchQuery.debounced.isEmpty { return }
    
    if matches.isEmpty {
      DispatchQueue.main.async {
        withAnimation {
          currentMatchIndex = 0
        }
      }
      
      return
    }
    
    var currIndex = -1
    var targetIndex = 0

    if !currentMatchId.isEmpty {
      currIndex = matches.firstIndex(where: { $0 == currentMatchId }) ?? 0
    }
    
    if reader == nil {
      DispatchQueue.main.async {
        withAnimation {
          currentMatchIndex = currIndex + 1
        }
      }
      
      return
    }
    
    targetIndex = forward ? (currIndex + 1 > matches.count - 1 ? 0 : currIndex + 1) : (currIndex - 1 < 0 ? matches.count - 1 : currIndex - 1)
    currentMatchId = matches[targetIndex]

    DispatchQueue.main.async {
      withAnimation {
        inAutoSkipMode = true
        currentMatchIndex = targetIndex + 1
        
        let target = matchMap[currentMatchId] ?? currentMatchId
        updateTopCommentIdx(target)
        reader?.scrollTo(target, anchor: .top)
      }
    }
  }
  
  func convertCommentsToLLMPrompt(_ comments: [Comment]) -> String {
    if comments.count == 0 { return "No comments yet" }
      var result = ""
      
      for (index, comment) in comments.enumerated() {
          result += processCommentNumbered(comment, parentNumber: "\(index + 1)") ?? ""
      }
      
      return result
  }

  private func processCommentNumbered(_ comment: Comment, parentNumber: String) -> String? {
    if comment.kind == "more" { return nil }
    guard let data = comment.data else { return nil }
    
    var commentText = "\(parentNumber)|@\(data.author ?? "Unknown")|\(data.body ?? "No Content")|\(data.ups ?? 0)|||"
      
    // Process children with sub-numbering
    let children = comment.childrenWinston
    if !children.isEmpty {
          for (index, child) in children.enumerated() {
              commentText += processCommentNumbered(child, parentNumber: "\(parentNumber).\(index + 1)") ?? ""
          }
      }
    
    return commentText
  }
  
  

  
  func generateSummary() {
//      DispatchQueue.main.async {
//          withAnimation(.easeOut(duration: 0.4)) {
//              generatedSummary = ""
//              generationErrorMessage = nil
//              summaryStreaming = true
//          }
//      }
//      
//      Task {
//          do {
//              let prompt = """
//                Summarize the general sentiments and key takeaways in the comments of this post\(post.data?.title != nil ? " titled \"\(post.data!.title)\"" : ""). Write a few key points about the most important, interesting or controversial points commenters are discussing, with each point on a new line.
//
//                When quoting comments, use _underscores for italics_. For emphasis on key themes, use **bold sparingly**. Every time you mention a commenter's username, you must wrap it in backticks like `@username` - this applies to ALL usernames mentions without exception.
//
//                Examples of correct formatting:
//                - `@john_doe` mentioned that _"this is really helpful"_
//                - Several users like `@sarah123` and `@mike_wilson` agreed that **the main issue is cost**
//                - As `@reddit_user` put it: _"completely changed my perspective"_
//
//                Format your response as separate paragraphs or lines for each main point. Include 1-2 direct quotes as evidence. Write in a friendly, conversational tone and do not shy away from sprinkling in a little humor or sarcasm. 
//                DO NOT use formal section headers.
//
//                Comment data: 
//                """ + convertCommentsToLLMPrompt(comments)
//              
//              let session = LanguageModelSession()
//              let stream = session.streamResponse(to: prompt)
//              
//              // Optimized streaming with smooth updates
//              var buffer = ""
//              var lastUpdateTime = Date()
//              let minUpdateInterval: TimeInterval = 0.15 // Minimum 150ms between updates
//              var wordsSinceLastUpdate = 0
//              let wordsPerForceUpdate = 4 // Force update every 4 words regardless of time
//              
//              for try await response in stream {
//                  buffer = response
//                  let currentWords = buffer.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
//                  let newWordsCount = currentWords.count
//                  
//                  let now = Date()
//                  let timeSinceUpdate = now.timeIntervalSince(lastUpdateTime)
//                  
//                  // Update if enough time has passed OR we have enough new words
//                  if timeSinceUpdate >= minUpdateInterval || newWordsCount - wordsSinceLastUpdate >= wordsPerForceUpdate {
//                      
//                      await MainActor.run {
//                          generatedSummary = buffer
//                      }
//                      
//                      lastUpdateTime = now
//                      wordsSinceLastUpdate = newWordsCount
//                      
//                      // Small breathing room to prevent UI overwhelm
//                      try? await Task.sleep(nanoseconds: 25_000_000) // 25ms
//                  }
//              }
//              
//              // Final update to ensure complete content
//              await MainActor.run {
//                  withAnimation(.easeOut(duration: 0.3)) {
//                      generatedSummary = buffer
//                      summaryStreaming = false
//                  }
//              }
//              
//          } catch {
//              await MainActor.run {
//                  withAnimation(.easeOut(duration: 0.4)) {
//                      if let genErr = error as? FoundationModels.LanguageModelSession.GenerationError {
//                          switch genErr {
//                          case .guardrailViolation(let context):
//                              generationErrorMessage = context.debugDescription
//                          case .exceededContextWindowSize(let context):
//                              generationErrorMessage = context.debugDescription
//                          case .assetsUnavailable(let context):
//                              generationErrorMessage = context.debugDescription
//                          case .decodingFailure(let context):
//                              generationErrorMessage = context.debugDescription
//                          case .unsupportedLanguageOrLocale(let context):
//                              generationErrorMessage = context.debugDescription
//                          default:
//                              generationErrorMessage = "\(error)"
//                          }
//                      } else {
//                          generationErrorMessage = "\(error)"
//                      }
//                      
//                      generatedSummary = nil
//                      summaryStreaming = false
//                  }
//              }
//          }
//      }
  }

  var body: some View {
    let navtitle: String = post.data?.title ?? "no title"
    let subnavtitle: String = "r/\(post.data?.subreddit ?? "no sub") \u{2022} " + String(localized:"\(post.data?.num_comments ?? 0) comments")
    let commentsHPad = selectedTheme.comments.theme.outerHPadding > 0 ? selectedTheme.comments.theme.outerHPadding : selectedTheme.comments.theme.innerPadding.horizontal
    GeometryReader { geometryReader in
      ScrollViewReader { proxy in
        List {
          Group {
            Section {
              if let winstonData = post.winstonData {
                PostContent(post: post, winstonData: winstonData, sub: subreddit, forceCollapse: forceCollapse)
              }
              //              .equatable()
              
              if selectedTheme.posts.inlineFloatingPill {
                PostFloatingPill(post: post, subreddit: subreddit, generateSummary: generateSummary, showUpVoteRatio: defSettings.showUpVoteRatio)
                  .padding(-10)
              }
              
              GeneratedSummaryView(generatedSummary: $generatedSummary, errorMessage: $generationErrorMessage, streaming: $summaryStreaming)
              
              HStack (spacing: 6){
                Text("Comments")
                  .fontSize(20, .bold)
                
                Spacer()
                
                Menu {
                  if !hideElements {
                    ForEach(CommentSortOption.allCases) { opt in
                      Button {
                        sort = opt
                        Defaults[.PostPageDefSettings].postSorts[post.id] = opt
                      } label: {
                        HStack {
                          Text(opt.rawVal.value.capitalized)
                          Spacer()
                          Image(systemName: opt.rawVal.icon)
                            .foregroundColor(Color.accentColor)
                            .fontSize(17, .bold)
                        }
                      }
                    }
                  }
                } label: {
                  if sort == .live {
                    Image(systemName: sort.rawVal.icon)
                      .foregroundColor(Color.accentColor)
                      .fontSize(17, .bold)
                      .blinking()
                  } else {
                    Image(systemName: sort.rawVal.icon)
                      .foregroundColor(Color.accentColor)
                      .fontSize(17, .bold)
                  }
                }
                
              }.frame(maxWidth: .infinity, alignment: .leading)
                .id("comments-header")
                .listRowInsets(EdgeInsets(top: selectedTheme.posts.commentsDistance / 2, leading:commentsHPad, bottom: 8, trailing: commentsHPad))
              
            }
            .listRowBackground(Color.clear)
            
            if !hideElements {
              PostReplies(update: update, post: post, subreddit: subreddit, ignoreSpecificComment: ignoreSpecificComment, highlightID: highlightID, sort: sort, proxy: proxy, geometryReader: geometryReader, comments: $comments, matchMap: $matchMap, seenComments: $seenComments, fadeSeenComments: $unseenSkipperOpen, highlightCurrentMatch: $inAutoSkipMode,initialLoading: $initialLoading, searchQuery: searchQuery.debounced, currentMatchId: currentMatchId, updateVisibleComments: updateVisibleComments, newCommentsLoaded: newCommentsLoaded)
                .environment(\.scrollViewProxy, proxy)
            }
            
            if !ignoreSpecificComment && highlightID != nil {
              Section {
                Button {
                  globalLoaderStart("Loading full post...")
                  withAnimation {
                    ignoreSpecificComment = true
                    if let highlightID {
                      doThisAfter(1) {
                        withAnimation(spring) {
                          proxy.scrollTo("\(highlightID)t1", anchor: .top)
                        }
                      }
                    }
                  }
                } label: {
                  HStack {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                    Text("View full conversation")
                  }
                }
              }
              .listRowBackground(Color.primary.opacity(0.1))
            }
            
            Section {
              Spacer()
                .frame(maxWidth: .infinity, minHeight: 72)
                .listRowBackground(Color.clear)
                .id("end-spacer")
            }
          }
          .listRowSeparator(.hidden)
        }
        .scrollIndicators(.never)
        .themedListBG(selectedTheme.posts.bg)
        .transition(.opacity)
        .environment(\.defaultMinListRowHeight, 1)
        .listStyle(.plain)
        .simultaneousGesture(DragGesture().onChanged({ _ in
          DispatchQueue.main.async {
            withAnimation {
              searchFocused = false
              inAutoSkipMode = false
            }
          }
        }))
        .refreshable {
          updatePost(true)
        }
        .overlay(alignment: .bottomTrailing) {
          if !selectedTheme.posts.inlineFloatingPill {
            PostFloatingPill(post: post, subreddit: subreddit, generateSummary: generateSummary, showUpVoteRatio: defSettings.showUpVoteRatio)
          }
        }
        .overlay(alignment: .bottom) {
          VStack(spacing: 6) {
            
            if searchOpen {
              HStack {
                TextField("Search comments...", text: $searchQuery.value)
                  .fontSize(18)
                  .autocorrectionDisabled(true)
                  .focused($searchFocused)
//                  .foregroundColor(Color.hex("7D7E80"))
                  .onChange(of: searchQuery.debounced) { _, val in
                    currentMatchId = ""
                    updateMatches(proxy)
                  }
                  .padding(.horizontal, 16)
                  .padding(.vertical, 10)
                  .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
                Spacer()
              }
            }
            
            HStack(spacing: 6) {
              HStack(spacing: 4) {
                // Matches bubble
                HStack(spacing: 6)  {
                  Image(systemName: searchOpen ? "text.page.badge.magnifyingglass" : "message.badge")
                    .fontSize(14, .semibold)
                    // .foregroundStyle(Color(UIColor(hex: "7D7E80")))
                  Text("\(currentMatchIndex)/\(totalMatches)")
                    .fontSize(17, .semibold)
                    // .foregroundStyle(Color(UIColor(hex: "7D7E80")))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .frame(height: 38)
                .padding(.horizontal, 14)
                .padding(.vertical, 0)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
                
                // Comment count bubble
                HStack(spacing: 6)  {
                  let numComments = post.data?.num_comments ?? 0
                  let allLoaded = flattened.count >= numComments
                  Image(systemName: allLoaded ? "arrow.down.circle" : "arrow.down.circle.dotted")
                    .fontSize(14, .semibold)
                    // .foregroundStyle(Color(UIColor(hex: "7D7E80")))
                  Text("\(flattened.count)/\(numComments)")
                    .fontSize(17, .semibold)
                    // .foregroundStyle(Color(UIColor(hex: "7D7E80")))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .frame(height: 38)
                .padding(.horizontal, 14)
                .padding(.vertical, 0)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
              }
              
              Spacer()
              
              HStack(spacing: 0) {
                Image(systemName: "chevron.left")
                  .fontSize(18, .semibold)
                  // .foregroundStyle(Color(UIColor(hex: "7D7E80")))
                  .padding(.horizontal, 14)
                  .padding(.vertical,  0)
                  .frame(height: 38)
                  .increaseHitboxOf(24, by: 1.25, shape: Circle())
                  .onTapGesture {
                    Hap.shared.play(intensity: 0.75, sharpness: 0.9)
                    scrollToNextMatch(false, proxy)
                  }
                  .glassEffect(.regular.interactive(), in: Circle())
                
                Image(systemName: "chevron.right")
                  .fontSize(18, .semibold)
                  // .foregroundStyle(Color(UIColor(hex: "7D7E80")))
                  .padding(.horizontal, 14)
                  .padding(.vertical, 0)
                  .frame(height: 38)
                  .increaseHitboxOf(24, by: 1.25, shape: Circle())
                  .onTapGesture {
                    Hap.shared.play(intensity: 0.75, sharpness: 0.9)
                    scrollToNextMatch(true, proxy)
                  }
                  .glassEffect(.regular.interactive(), in: Circle())
                
                // Down chevron (for searchFocused)
                if searchFocused {
                  Image(systemName: "chevron.down")
                    .opacity(searchFocused ? 1 : 0)
                    .fontSize(18, .semibold)
                    // .foregroundStyle(Color(UIColor(hex: "7D7E80")))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 0)
                    .contentShape(Circle())
                    .frame(height: 38)
                    .increaseHitboxOf(24, by: 1.25, shape: Circle())
                    .onTapGesture {
                      Hap.shared.play(intensity: 0.75, sharpness: 0.9)
                      DispatchQueue.main.async {
                        withAnimation {
                          searchFocused = false
                        }
                      }
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                }
                
                // Close/X bubble
                Image(systemName: "xmark")
                  .fontSize(18, .semibold)
                  // .foregroundStyle(Color(UIColor(hex: "7D7E80")))
                  .padding(.horizontal, 14)
                  .padding(.vertical, 0)
                  .contentShape(Circle())
                  .frame(height: 38)
                  .increaseHitboxOf(24, by: 1.25, shape: Circle())
                  .onTapGesture {
                    Hap.shared.play(intensity: 0.75, sharpness: 0.9)
                    if searchFocused {
                      DispatchQueue.main.async {
                        withAnimation {
                          searchFocused = false
                        }
                      }
                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation {
                          searchOpen = false
                          searchQuery.value = ""
                        }
                      }
                    } else {
                      DispatchQueue.main.async {
                        withAnimation {
                          searchQuery.value = ""
                          searchOpen = false
                          unseenSkipperOpen = false
                        }
                      }
                    }
                  }
                  .glassEffect(.regular.interactive(), in: Circle())
              }
            }
          }
          .padding(.horizontal, 12)
          .padding(.bottom, 8)
          .frame(maxWidth: searchOpen || unseenSkipperOpen ? .infinity : 0)
          .animation(.bouncy(duration: 0.5), value: searchOpen || unseenSkipperOpen)
//          .background(Color.hex("212326").clipShape(RoundedRectangle(cornerRadius:20)))
//          .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius:20))
//          .clipShape(RoundedRectangle(cornerRadius:20))
//          .shadow(color: Color.hex("212326"), radius: 10)
          .opacity(searchOpen || unseenSkipperOpen ? 1 : 0)
          .animation(.bouncy(duration: 0.5), value: searchOpen || unseenSkipperOpen)
          .padding(.horizontal, 12)
          .ignoresSafeArea(.keyboard)
          
        }
        .navigationBarTitle("\(navtitle)", displayMode: .inline)
        .toolbar { Toolbar(title: navtitle, subtitle: subnavtitle, hideElements: hideElements, subreddit: subreddit, post: post, searchOpen: $searchOpen, unseenSkipperOpen: $unseenSkipperOpen, currentMatchIndex: $currentMatchIndex, totalMatches: $totalMatches, searchFocused: _searchFocused) }
        .onChange(of: sort) { _, val in
          handleLiveRefresh()
          updatePost()
        }
        .onChange(of: visibleComments.debounced) { _, val in
          if inAutoSkipMode {
            return
          }
          
          updateMatchIndex(val)
        }
        .onAppear {
          doThisAfter(0.5) {
            hideElements = false
            doThisAfter(0.1) {
              if highlightID != nil { withAnimation { proxy.scrollTo("loading-comments") } }
            }
          }
          
          if post.data == nil || comments.isEmpty {
            updatePost() {
              let title = post.data?.title.lowercased() ?? ""
              let defaultSort = title.contains("game thread") && !title.contains("post game thread") ?
                CommentSortOption.live : Defaults[.CommentsSectionDefSettings].preferredSort
              sort = Defaults[.PostPageDefSettings].perPostSort ? (Defaults[.PostPageDefSettings].postSorts[post.id] ?? defaultSort) : defaultSort
              self.handleLiveRefresh()
              
              if let highlightID {
                doThisAfter(0.5) {
                  withAnimation(spring) {
                    proxy.scrollTo("\(highlightID)t1", anchor: .top)
                  }
                }
              }
            }
          } else {
            self.handleLiveRefresh()
          }
          
          Task(priority: .background) {
            if let numComments = post.data?.num_comments {
              await post.saveCommentsCount(numComments: numComments)
            }
          }
          
          Task(priority: .background) {
            if subreddit.data == nil && subreddit.id != "home" {
              await subreddit.refreshSubreddit()
            }
          }
        }
        .onChange(of: commentUpdate.debounced) { _, val in
          Task {
            flattenComments(true)
            updateMatches()
          }
        }
        .onDisappear {
          stopLiveRefresh()
        }
        .onPreferenceChange(CommentUtils.AnchorsKey.self) { anchors in
          Task(priority: .background) {
            topVisibleCommentId = CommentUtils.shared.topCommentRow(of: anchors, in: geometryReader)
          }
        }
        .onChange(of: topVisibleCommentId) { _, val in
          if let val {
            updateTopCommentIdx(val)
          }
        }
        .onChange(of: NetworkMonitor.shared.connectedToWifi) {
          if NetworkMonitor.shared.connectedToWifi && comments.count == 0 {
            refresh()
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
          stopLiveRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
          stopLiveRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
          if sort == .live {
            handleLiveRefresh()
          }
        }
        .commentSkipper(
          showJumpToNextCommentButton: $commentsSectionDefSettings.commentSkipper,
          topVisibleCommentId: $topVisibleCommentId,
          previousScrollTarget: $previousScrollTarget,
          comments: comments,
          reader: proxy,
          refresh: refresh,
          openUnseenSkipper : openUnseenSkipper,
          updateTopCommentIdx : updateTopCommentIdx,
          searchOpen: $searchOpen,
          unseenSkipperOpen: $unseenSkipperOpen
        )
      }
    }
  }
}

private struct Toolbar: ToolbarContent {
  var title: String
  var subtitle: String
  var hideElements: Bool
  var subreddit: Subreddit
  var post: Post
  @Binding var searchOpen: Bool
  @Binding var unseenSkipperOpen: Bool
  @Binding var currentMatchIndex: Int
  @Binding var totalMatches: Int
  @FocusState var searchFocused: Bool
  
  var body: some ToolbarContent {
    if !IPAD {
      ToolbarItem(id: "postview-title", placement: .principal) {
        VStack {
          Text(title)
            .font(.headline)
            .lineLimit(1)
          Text(subtitle)
            .font(.subheadline)
            .lineLimit(1)
        }
      }
    }
    
    ToolbarItem(id: "postview-search-and-sub", placement: .navigationBarTrailing) {
      HStack {
        Image(systemName: "magnifyingglass")
//           .fontSize(16, .semibold)
          .foregroundStyle(Color.white)
          .opacity(0.8)
          .onTapGesture {
            Hap.shared.play(intensity: 0.75, sharpness: 0.9)
            if !searchOpen {
              DispatchQueue.main.async {
                withAnimation {
                  searchOpen = true
                  unseenSkipperOpen = false
                  currentMatchIndex = 0
                  totalMatches = 0
                }
              }
              
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                  searchFocused = true
                }
              }
            }
          }
        
        if let data = subreddit.data, !feedsAndSuch.contains(subreddit.id) {
          SubredditIcon(subredditIconKit: data.subredditIconKit)
//            .padding([.leading], 4)
            .onTapGesture { Nav.to(.reddit(.subInfo(subreddit))) }
        }
      }
    }
  }
}

struct BlinkViewModifier: ViewModifier {
    
    let duration: Double
    let min: Double
    @State private var blinking: Bool = false
    
    func body(content: Content) -> some View {
        content
            .opacity(blinking ? min : 1)
            .animation(.easeOut(duration: duration).repeatForever(), value: blinking)
            .onAppear {
                withAnimation {
                    blinking = true
                }
            }
    }
}

extension View {
  func blinking(duration: Double = 1, min: Double = 0.5) -> some View {
    modifier(BlinkViewModifier(duration: duration, min: min))
    }
}


func isGameThread(_ str: String?) -> Bool {
  guard let str else { return false }
  
  let lowercase = str.lowercased()
  return lowercase.contains("game thread") && !lowercase.contains("post game thread")
}

