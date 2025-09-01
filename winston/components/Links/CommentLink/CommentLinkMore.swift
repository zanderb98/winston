//
//  CommentLinkMore.swift
//  winston
//
//  Created by Igor Marcossi on 17/07/23.
//

import SwiftUI
import Defaults

// Shared state manager for auto-load queue
class CommentAutoLoadManager: ObservableObject {
  static let shared = CommentAutoLoadManager()
  
  @Published var currentAutoLoadingCommentId: String? = nil
  private var currentAutoLoadingIndex: Int? = nil // Track the index of currently loading comment
  private var requestedComments: Set<String> = [] // Just track which comments have requested auto-load
  private var currentTopCommentIdx: Int = 0
  private var currentCommentIndexMap: [String: Int] = [:]
  
  private init() {}
  
  func canStartAutoLoad(for commentId: String, at index: Int) -> Bool {
    return currentAutoLoadingCommentId == nil
  }
  
  func requestAutoLoadSlot(for commentId: String) {
    // Simply add to requested comments
    requestedComments.insert(commentId)
    
    // Check if we should interrupt the current loading comment with a higher priority one
    if let currentLoadingId = currentAutoLoadingCommentId,
       let currentLoadingIdx = currentAutoLoadingIndex,
       let requestedIndex = currentCommentIndexMap[commentId],
       requestedIndex >= currentTopCommentIdx,
       requestedIndex < currentLoadingIdx {
      // New comment has higher priority, stop current and start new one immediately
//      print("[AUTO-LOAD \(Date().timeIntervalSinceReferenceDate)] Interrupting comment \(currentLoadingId) at index \(currentLoadingIdx) for higher priority comment \(commentId) at index \(requestedIndex)")
      stopAutoLoad(for: currentLoadingId)
      startAutoLoad(for: commentId, at: requestedIndex)
    } else {
      // Try to start the next comment if nothing is currently loading
      processQueue()
    }
  }
  
  func processIndexMapUpdate(_ commentIndexMap: [String: Int]) {
    if currentCommentIndexMap == commentIndexMap { return }
    currentCommentIndexMap = commentIndexMap
    
    // Check if the currently loading comment is still the best one to load
    if let currentLoadingId = currentAutoLoadingCommentId,
       let currentLoadingIdx = currentAutoLoadingIndex {
      
      // Find if there's a better comment to load (lower index)
      var betterCommentId: String? = nil
      var betterIndex: Int = currentLoadingIdx
      
      for commentId in requestedComments {
        if commentId != currentLoadingId,
           let index = commentIndexMap[commentId],
           index >= currentTopCommentIdx,
           index < betterIndex {
          betterCommentId = commentId
          betterIndex = index
        }
      }
      
      // If we found a better comment, interrupt current and start the better one
      if let betterComment = betterCommentId {
//        print("[AUTO-LOAD \(Date().timeIntervalSinceReferenceDate)] Index map update: Interrupting comment \(currentLoadingId) at index \(currentLoadingIdx) for higher priority comment \(betterComment) at index \(betterIndex)")
        stopAutoLoad(for: currentLoadingId)
        startAutoLoad(for: betterComment, at: betterIndex)
      }
    } else {
      // Only process queue if nothing is currently loading
      processQueue()
    }
  }
  
  private func processQueue() {
    guard currentAutoLoadingCommentId == nil else {
      return
    }
    
    // Find the comment with the lowest index that's >= currentTopCommentIdx
    var bestCommentId: String? = nil
    var bestIndex: Int = Int.max
    
    for commentId in requestedComments {
      if let index = currentCommentIndexMap[commentId],
         index >= currentTopCommentIdx,
         index < bestIndex {
        bestCommentId = commentId
        bestIndex = index
      }
    }
    
    // Start auto-load for the best candidate
    if let commentId = bestCommentId {
      startAutoLoad(for: commentId, at: bestIndex)
    }
  }
  
  func startAutoLoad(for commentId: String, at index: Int) {
    currentAutoLoadingCommentId = commentId
    currentAutoLoadingIndex = index
    // Force UI update
    DispatchQueue.main.async {
      self.objectWillChange.send()
    }
  }
  
  func startAutoLoad(for commentId: String) {
    // Legacy method - try to find index from map
    if let index = currentCommentIndexMap[commentId] {
      startAutoLoad(for: commentId, at: index)
    } else {
      currentAutoLoadingCommentId = commentId
      currentAutoLoadingIndex = nil
      DispatchQueue.main.async {
        self.objectWillChange.send()
      }
    }
  }
  
  func stopAutoLoad(for commentId: String) {
    if currentAutoLoadingCommentId == commentId {
      currentAutoLoadingCommentId = nil
      currentAutoLoadingIndex = nil
      // Process next in queue immediately
      DispatchQueue.main.async {
        self.processQueue()
      }
    }
  }
  
  func isCurrentlyAutoLoading(_ commentId: String) -> Bool {
    return currentAutoLoadingCommentId == commentId
  }
  
  func removeFromQueue(_ commentId: String) {
    requestedComments.remove(commentId)
  }
  
  func isCommentVisible(_ commentId: String) -> Bool {
    return requestedComments.contains(commentId)
  }
  
  // New method to handle topCommentIdx changes
  func handleTopCommentIndexChange(_ topCommentIdx: Int) {
    if topCommentIdx == currentTopCommentIdx { return }
    
    currentTopCommentIdx = topCommentIdx
    
    // If the currently loading comment is now above the visible area, stop it
    if let currentLoadingId = currentAutoLoadingCommentId,
       let currentLoadingIdx = currentAutoLoadingIndex,
       currentLoadingIdx < topCommentIdx {
      stopAutoLoad(for: currentLoadingId)
    }
    
    // Only process queue if nothing is currently loading
    if currentAutoLoadingCommentId == nil {
      processQueue()
    }
  }
}

struct CommentLinkMore: View {
  var arrowKinds: [ArrowKind]
  var comment: Comment
  weak var post: Post?
  var postFullname: String?
  var parentElement: CommentParentElement?
  var indentLines: Int?
  var newCommentsLoaded: (() -> Void)?
  var index: Int = 0
  
  @State var loadMoreLoading = false
  @State var autoLoadProgress: Double = 0.0
  @State var autoLoadTimer: Timer? = nil
  @State var resetProgressTimer: Timer? = nil
  @State var hasRequestedAutoLoad = false
  
  @Environment(\.useTheme) private var selectedTheme
  @Default(.BehaviorDefSettings) private var behaviorDefSettings
  
  @StateObject private var autoLoadManager = CommentAutoLoadManager.shared
  
  private let timerInterval: TimeInterval = 0.1

  
  func handleTap() {
    // Cancel auto-load timer when manually tapped
    cancelAutoLoadTimer()
    
    if let postFullname = postFullname, let parentElement = parentElement {
      withAnimation(spring) {
        loadMoreLoading = true
      }
      Task(priority: .background) {
        await comment.loadChildren(parent: parentElement, postFullname: postFullname, avatarSize: selectedTheme.comments.theme.badge.avatar.size, post: post, index: index)
        
        await MainActor.run {
          doThisAfter(0.5) {
            withAnimation(spring) {
              loadMoreLoading = false
            }
          }
        }
        
        newCommentsLoaded?()
      }
    }
  }
  
  private func requestAutoLoadSlot() {
    guard !hasRequestedAutoLoad else { return }
    
    hasRequestedAutoLoad = true
    autoLoadManager.requestAutoLoadSlot(for: comment.id)
  }
  
  private func startAutoLoadTimer() {
    // Don't start timer if already loading
    if loadMoreLoading { return }
    
    // Only start if we're the current auto-loading comment
    guard autoLoadManager.isCurrentlyAutoLoading(comment.id) else { return }
    
    // Reset progress
    withAnimation(.easeOut(duration: 0.1)) {
      autoLoadProgress = 0.0
    }
    
    // Start the progress timer
    let duration = 1.25
    autoLoadTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { timer in
      DispatchQueue.main.async {
        // Check if we're still allowed to auto-load (not dragging, still our turn)
        guard autoLoadManager.isCurrentlyAutoLoading(comment.id) else {
          timer.invalidate()
          autoLoadTimer = nil
          autoLoadProgress = 0.0
          return
        }
        
        withAnimation {
          autoLoadProgress += timerInterval / duration
        }
        
        resetProgressTimer?.invalidate()
        
        if autoLoadProgress >= 1.0 {
          timer.invalidate()
          autoLoadTimer = nil
          resetProgressTimer = nil
          handleTap()
        } else {
          resetProgressTimer = Timer.scheduledTimer(withTimeInterval: 3 * timerInterval, repeats: false) { _ in
            if autoLoadTimer != nil {
              DispatchQueue.main.async {
                autoLoadProgress = 0
              }
            }
            
            resetProgressTimer = nil
          }
        }
      }
    }
  }
  
  private func cancelAutoLoadTimer() {
    autoLoadTimer?.invalidate()
    autoLoadTimer = nil
    resetProgressTimer?.invalidate()
    resetProgressTimer = nil
    
    autoLoadManager.stopAutoLoad(for: comment.id)
    autoLoadManager.removeFromQueue(comment.id)
    
    hasRequestedAutoLoad = false
    withAnimation(.easeOut(duration: 0.2)) {
      autoLoadProgress = 0.0
    }
  }
  
  var body: some View {
    let theme = selectedTheme.comments
    let horPad = selectedTheme.comments.theme.innerPadding.horizontal
    
    if let data = comment.data, let count = data.count, let parentElement = parentElement, count > 0 {
      HStack(spacing: 0) {
        if data.depth != 0 && indentLines != 0 {
          HStack(alignment: .bottom, spacing: 6) {
            let shapes = Array(1...Int(indentLines ?? data.depth ?? 1))
            ForEach(shapes, id: \.self) { i in
              if arrowKinds.indices.contains(i - 1) {
                let actualArrowKind = arrowKinds[i - 1]
                Arrows(kind: actualArrowKind, offset: theme.theme.innerPadding.vertical + theme.theme.repliesSpacing)
              }
            }
          }
        }
        
        HStack(spacing: 8) {
          // Main Load More button
          HStack(spacing: 6) {
            Image(systemName: "plus.message.fill")
            HStack(spacing: 3) {
              HStack(spacing: 0) {
                Text("Load")
                if loadMoreLoading {
                  Text("ing")
                    .transition(.scale.combined(with: .opacity))
                }
              }
              Text(count == 0 ? "some" : String(count))
              HStack(spacing: 0) {
                Text("more")
                if loadMoreLoading {
                  Text("...")
                    .transition(.scale.combined(with: .opacity))
                }
              }
            }
            
            // Progress indicator only
            if autoLoadProgress > 0 && !loadMoreLoading {
              ZStack {
                Circle()
                  .stroke(selectedTheme.comments.theme.loadMoreText.color().opacity(0.3), lineWidth: 1)
                  .frame(width: 12, height: 12)
                
                Circle()
                  .trim(from: 0, to: autoLoadProgress)
                  .stroke(selectedTheme.comments.theme.loadMoreText.color(), lineWidth: 1.5)
                  .frame(width: 12, height: 12)
                  .rotationEffect(.degrees(-90))
                  .animation(.linear(duration: timerInterval), value: autoLoadProgress)
              }
            }
          }
          .padding(.vertical, selectedTheme.comments.theme.loadMoreInnerPadding.vertical)
          .padding(.horizontal, selectedTheme.comments.theme.loadMoreInnerPadding.horizontal)
          .opacity(loadMoreLoading ? 0.5 : 1)
          .background(Capsule(style: .continuous).fill(selectedTheme.comments.theme.loadMoreBackground()))
          .compositingGroup()
          .fontSize(selectedTheme.comments.theme.loadMoreText.size, selectedTheme.comments.theme.loadMoreText.weight.t)
          .foregroundColor(selectedTheme.comments.theme.loadMoreText.color())
          .background(
            // Hidden reference view to get the height
            GeometryReader { geometry in
              Color.clear
                .onAppear {
                  // Store the height for the cancel button
                }
            }
          )
          
          // Cancel button with expand/collapse animation
          if autoLoadProgress > 0 && !loadMoreLoading {
            Button(action: {
              cancelAutoLoadTimer()
            }) {
              Circle()
                .fill(selectedTheme.comments.theme.loadMoreBackground())
                .frame(
                  width: selectedTheme.comments.theme.loadMoreInnerPadding.vertical * 2 + selectedTheme.comments.theme.loadMoreText.size + 4,
                  height: selectedTheme.comments.theme.loadMoreInnerPadding.vertical * 2 + selectedTheme.comments.theme.loadMoreText.size + 4
                )
                .overlay(
                  Image(systemName: "xmark")
                    .font(.system(size: selectedTheme.comments.theme.loadMoreText.size * 0.8, weight: .semibold))
                    .foregroundColor(selectedTheme.comments.theme.loadMoreText.color())
                    .scaleEffect(autoLoadProgress > 0 ? 1.0 : 0.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: autoLoadProgress > 0)
                )
                .scaleEffect(autoLoadProgress > 0 ? 1.0 : 0.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: autoLoadProgress > 0)
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Circle())
          }
        }
        .padding(.top, data.depth == 0 ? 0 : theme.theme.repliesSpacing)
        .padding(.vertical, max(0, theme.theme.innerPadding.vertical - (data.depth == 0 ? theme.theme.cornerRadius : 0)))
      }
      .padding(.horizontal, horPad)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(selectedTheme.comments.theme.bg())
      .contentShape(Rectangle())
      .onTapGesture {
        handleTap()
      }
      .allowsHitTesting(!loadMoreLoading)
      .id("\(comment.id)-more")
      .onAppear {
        if data.depth == 0 {
          handleTap()
          return
        }
        
        if NetworkMonitor.shared.connectedToWifiIfDataSaver(), let count = data.count, count == 1 {
          handleTap()
          return
        }
        
        // Request auto-load slot for other cases
        requestAutoLoadSlot()
      }
      .onDisappear {
        // Cancel timer and remove from queue when view disappears
        cancelAutoLoadTimer()
      }
      .onChange(of: autoLoadManager.isCurrentlyAutoLoading(comment.id)) {
        if !loadMoreLoading {
          // It's our turn to auto-load
          DispatchQueue.main.async {
            startAutoLoadTimer()
          }
        }
      }
    }
  }
}
