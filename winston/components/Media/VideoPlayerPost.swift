import SwiftUI
import Defaults
import CoreMedia
import AVKit
import AVFoundation
import Combine
import MediaPlayer

// MARK: - AVPlayer Pool Manager
class AVPlayerPool {
  static let shared = AVPlayerPool()
  private let maxPoolSize = 3
  private var availablePlayers: [AVPlayer] = []
  private var inUsePlayers: [String: AVPlayer] = [:] // Changed to dictionary for better tracking
  private let queue = DispatchQueue(label: "com.app.avplayerpool")
  private var hasBeenReset: [String] = []
  
  private init() {}
  
  func resetVideo(post: Post, video: SharedVideo) {
    if hasBeenReset.contains(video.id) {
      return
    }
    
    hasBeenReset.append(video.id)
    
    DispatchQueue.main.async {
      let newVideo: MediaExtractedType = .video(SharedVideo.get(url: video.url, size: video.size, resetCache: true, prevVideoId: video.id))
      post.winstonData?.extractedMedia = newVideo
      post.winstonData?.extractedMediaForcedNormal = newVideo
    }
  }
  
  func getPlayer(for id: String) -> AVPlayer {
    return queue.sync {
      // Check if player already exists for this ID
      if let existingPlayer = inUsePlayers[id] {
        return existingPlayer
      }
      
      // Try to reuse an available player
      if !availablePlayers.isEmpty {
        let player = availablePlayers.removeFirst()
        inUsePlayers[id] = player
        return player
      }
      
      // Create new player
      let newPlayer = AVPlayer()
      newPlayer.volume = 0.0
      newPlayer.isMuted = true
      newPlayer.automaticallyWaitsToMinimizeStalling = false
      newPlayer.actionAtItemEnd = .pause
      
      // Prevent Now Playing info
      newPlayer.allowsExternalPlayback = false
      newPlayer.preventsDisplaySleepDuringVideoPlayback = false
      
      inUsePlayers[id] = newPlayer
      return newPlayer
    }
  }
  
  func returnPlayer(for id: String) {
    queue.sync {
      guard let player = inUsePlayers[id] else { return }
      
      // Reset player state on main thread to avoid crashes
      DispatchQueue.main.async { [weak player] in
        guard let player = player else { return }
        player.pause()
        player.seek(to: .zero)
        player.replaceCurrentItem(with: nil)
      }
      
      inUsePlayers.removeValue(forKey: id)
      
      // Only keep up to maxPoolSize players
      if availablePlayers.count < maxPoolSize {
        availablePlayers.append(player)
      }
    }
  }
  
  func drain() {
    queue.sync {
      // Pause all players on main thread
      let allPlayers = Array(inUsePlayers.values) + availablePlayers
      DispatchQueue.main.async {
        allPlayers.forEach { $0.pause() }
      }
      
      availablePlayers.removeAll()
      inUsePlayers.removeAll()
    }
  }
}

struct SharedVideo: Equatable {
  static func == (lhs: SharedVideo, rhs: SharedVideo) -> Bool {
    lhs.url == rhs.url && lhs.id == rhs.id
  }
  
  var player: AVPlayer
  var url: URL
  var id: String
  var size: CGSize
  var key: String
  private var isCleanedUp = false
  
  static func get(url: URL, size: CGSize, resetCache: Bool = false, prevVideoId: String? = nil) -> SharedVideo {
    if resetCache {
      let cacheKey = SharedVideo.cacheKey(url: url, size: size)
      Caches.videos.cache.removeValue(forKey: cacheKey)
    }
    
    let sharedVideo = SharedVideo(url: url, size: size)
    
    if let prevVideoId {
      Nav.shared.currVideos[sharedVideo.id] = Nav.shared.currVideos[prevVideoId]
      Nav.shared.currVideos[prevVideoId] = nil
    }
    
    return sharedVideo
  }
  
  static func cacheKey(url: URL, size: CGSize) -> String {
    return "\(url.absoluteString):\(Int(size.width))x\(Int(size.height))"
  }
  
  init(url: URL, size: CGSize) {
    self.url = url
    self.id = randomString(length: 12)
    self.size = size
    self.key = SharedVideo.cacheKey(url: url, size: size)
    
    if let asset = Caches.videos.get(key: self.key) {
      let playerItem = AVPlayerItem(asset: asset)
      self.player = AVPlayer(playerItem: playerItem)
    } else {
      if NetworkMonitor.shared.connectedToWifiIfDataSaver() {
        self.player = AVPlayer(url: url)
        if let asset = self.player.currentItem?.asset {
          Caches.videos.addKeyValue(key: self.key, data: { asset }, expires: Date().dateByAdding(1, .day).date)
        }
      } else {
        self.player = AVPlayer()
      }
    }
    
    // Configure player to not interfere with background audio
    self.player.volume = 0.0
    self.player.isMuted = true
    self.player.automaticallyWaitsToMinimizeStalling = true
    self.player.preventsDisplaySleepDuringVideoPlayback = false
    
    // Ensure player doesn't take over audio session
    self.player.allowsExternalPlayback = false
    
    // For ambient videos, we shouldn't interfere with now playing at all
  }
  
  func loadIfNeeded() {
    guard !isCleanedUp, player.currentItem == nil else { return }
    
    Task(priority: .high) {
      do {
        let asset = AVURLAsset(url: self.url)
        let _ = try await asset.load(.duration, .tracks, .isPlayable)
        
        Caches.videos.addKeyValue(key: self.key, data: { asset }, expires: Date().dateByAdding(1, .day).date)
        
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 5.0
        
        await MainActor.run {
          guard !self.isCleanedUp else { return }
          player.replaceCurrentItem(with: playerItem)
          
          // Ensure audio settings are maintained after item replacement
          player.volume = 0.0
          player.isMuted = true
//          print("[VID] Asset loaded and player item set for: \(self.url)")
        }
        
      } catch {
        print("[VID] Failed to load asset: \(error)")
      }
    }
  }
  
  func safeCleanup() {
    guard !isCleanedUp else { return }
    
    Task { @MainActor in
      // Pause and reset player before cleanup
      player.pause()
      player.seek(to: .zero) { _ in
        // Replace with nil item to properly release resources
        self.player.replaceCurrentItem(with: nil)
      }
    }
  }
  
  mutating func cleanup() {
    guard !isCleanedUp else { return }
    isCleanedUp = true
    safeCleanup()
  }
  
  private func clearNowPlayingInfo() {
    // Only clear if we actually set any now playing info
    // For silent/ambient videos, we shouldn't be setting any info anyway
    // So this should be safe, but let's be extra cautious
    if MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Video" {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
  }
}

struct VideoPlayerPost: View, Equatable {
  static func == (lhs: VideoPlayerPost, rhs: VideoPlayerPost) -> Bool {
    lhs.url == rhs.url && lhs.sharedVideo == rhs.sharedVideo
  }
  
  weak var controller: UIViewController?
  var sharedVideo: SharedVideo?
  let markAsSeen: (() async -> ())?
  var compact = false
  var contentWidth: CGFloat
  var url: URL
  var size: CGSize
  let resetVideo: ((SharedVideo) -> ())?
  var maxMediaHeightScreenPercentage: CGFloat
  @State private var firstFullscreen = false
  @State private var fullscreen = false
  @State private var hasAppeared = false
  @State private var observersAdded = false
  @State private var notificationTokens: [Any] = []
  
  @State private var cancellables = Set<AnyCancellable>()
  
  @Default(.VideoDefSettings) private var videoDefSettings
  @Environment(\.scenePhase) private var scenePhase
  
  private var autoPlayVideos: Bool { videoDefSettings.autoPlay }
  private var loopVideos: Bool { videoDefSettings.loop }
  private var muteVideos: Bool { videoDefSettings.mute }
  private var pauseBackgroundAudioOnFullscreen: Bool { videoDefSettings.pauseBGAudioOnFullscreen }
  
  init(controller: UIViewController?, cachedVideo: SharedVideo?, markAsSeen: (() async -> ())?, compact: Bool = false, contentWidth: CGFloat, url: URL, resetVideo: ((SharedVideo) -> ())?, maxMediaHeightScreenPercentage: CGFloat) {
    self.controller = controller
    self.sharedVideo = cachedVideo
    self.markAsSeen = markAsSeen
    self.compact = compact
    self.contentWidth = contentWidth
    self.url = url
    self.size = cachedVideo?.size ?? .zero
    self.resetVideo = resetVideo
    self.maxMediaHeightScreenPercentage = maxMediaHeightScreenPercentage
  }
  
  var safe: Double { getSafeArea().top + getSafeArea().bottom }
  
  var body: some View {
    let maxHeight: CGFloat = (maxMediaHeightScreenPercentage / 100) * (.screenH)
    let sourceWidth = size.width
    let sourceHeight = size.height
    let propHeight = (contentWidth * sourceHeight) / sourceWidth
    let finalHeight = maxMediaHeightScreenPercentage != 110 ? Double(min(maxHeight, propHeight)) : Double(propHeight)
    
    if let sharedVideo = sharedVideo {
      ZStack {
        Group {
          if !fullscreen {
            VideoPlayer(player: sharedVideo.player)
              .scaledToFill()
              .ignoresSafeArea()
          } else {
            Color.black
          }
        }
        .frame(width: compact ? scaledCompactModeThumbSize() : contentWidth, height: compact ? scaledCompactModeThumbSize() : CGFloat(finalHeight))
        .clipped()
        .fixedSize()
        .mask(RR(12, Color.black))
        .allowsHitTesting(false)
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture().onEnded({ _ in
          handleVideoTap()
        }))
        .allowsHitTesting(false)
        .mask(RR(12, Color.black))
        .overlay(
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
              handleVideoTap()
            }
        )
        
        Image(systemName: "play.fill").foregroundColor(.white.opacity(0.75)).fontSize(32).shadow(color: .black.opacity(0.45), radius: 12, y: 8).opacity((autoPlayVideos && sharedVideo.player.currentItem != nil) || NetworkMonitor.isConnectedToWiFi() ? 0 : 1).allowsHitTesting(false)
      }
      .onAppear {
        handleOnAppear()
      }
      .onChange(of: NetworkMonitor.shared.connectedToWifi) {
        if NetworkMonitor.shared.connectedToWifi {
          sharedVideo.loadIfNeeded()
        }
      }
      .onChange(of: scenePhase) { _, newPhase in
        handleScenePhaseChange(newPhase)
      }
      .onDisappear() {
        handleOnDisappear()
      }
      .onChange(of: fullscreen) { _, val in
        handleFullscreenChange(val)
      }
      .onChange(of: sharedVideo) { _, _ in
        // After video reset, autoplay again
        
        // Set up status observers for autoplay
        setupAutoplayObservers()
        
        // Try immediate autoplay if ready
        attemptAutoplay()
      }
      .fullScreenCover(isPresented: $fullscreen) {
        FullScreenVP(sharedVideo: sharedVideo)
      }
    }
  }
  
  // MARK: - Safe Event Handlers
  
  private func handleVideoTap() {
    guard let sharedVideo = sharedVideo else { return }
    
    if markAsSeen != nil {
      Task(priority: .background) { await markAsSeen?() }
    }
    
    sharedVideo.loadIfNeeded()
    withAnimation {
      fullscreen = true
    }
  }
  
  private func handleOnAppear() {
      guard let sharedVideo = sharedVideo, !hasAppeared else { return }
      hasAppeared = true
      
      DispatchQueue.main.async {
          if loopVideos && !observersAdded {
              addObserver()
          }
          
          if (sharedVideo.player.status == .failed) {
              resetVideo?(sharedVideo)
          } else if NetworkMonitor.shared.connectedToWifiIfDataSaver() {
              sharedVideo.loadIfNeeded()
          }
          
          // Set up status observers for autoplay
          setupAutoplayObservers()
          
          // Try immediate autoplay if ready
          attemptAutoplay()
          
          Nav.shared.currVideos[sharedVideo.id] = (Nav.shared.currVideos[sharedVideo.id] ?? 0) + 1
      }
  }

  // Add this new method to set up status observers using Combine
  private func setupAutoplayObservers() {
      guard let sharedVideo = sharedVideo, autoPlayVideos else { return }
      
      // Clean up any existing observers first
      cleanupAutoplayObservers()
      
      let videoUrl = sharedVideo.url // Capture URL for logging
      
      // Observe player status changes
      sharedVideo.player.publisher(for: \.status)
          .receive(on: DispatchQueue.main)
          .sink { [self] status in
//              print("[VID] Player status changed to: \(status.rawValue) for \(videoUrl)")
              attemptAutoplay()
          }
          .store(in: &cancellables)
      
      // Observe current item changes
      sharedVideo.player.publisher(for: \.currentItem)
          .receive(on: DispatchQueue.main)
          .sink { [self] item in
//              print("[VID] Current item changed: \(item != nil) for \(videoUrl)")
              observeCurrentItemStatus()
              attemptAutoplay()
          }
          .store(in: &cancellables)
      
      // Set up initial item observer if item already exists
      observeCurrentItemStatus()
  }

  // Helper method to observe the current item's status
  private func observeCurrentItemStatus() {
      guard let sharedVideo = sharedVideo else { return }
      
      if let currentItem = sharedVideo.player.currentItem {
          currentItem.publisher(for: \.status)
              .receive(on: DispatchQueue.main)
              .sink { [self] status in
//                  print("[VID] Player item status changed to: \(status.rawValue) for \(sharedVideo.url)")
                  attemptAutoplay()
              }
              .store(in: &cancellables)
      }
  }

  // Remove the static method and Nav extension as they're no longer needed

  // Enhanced autoplay attempt method that can access state
  private func attemptAutoplay() {
      guard let sharedVideo = sharedVideo else { return }
      
      // Check all conditions
      let shouldAutoplay = autoPlayVideos
      let hasAppearedCheck = hasAppeared
      let notFullscreen = !fullscreen
      let hasCurrentItem = sharedVideo.player.currentItem != nil
      let playerReady = sharedVideo.player.status == .readyToPlay
      let itemReady = sharedVideo.player.currentItem?.status == .readyToPlay
      
//      print("[VID] Autoplay check - shouldAutoplay: \(shouldAutoplay), notAlreadyPlayed: \(notAlreadyPlayed), hasAppeared: \(hasAppearedCheck), notFullscreen: \(notFullscreen), hasCurrentItem: \(hasCurrentItem), playerReady: \(playerReady), itemReady: \(itemReady ?? false)")
      
      guard shouldAutoplay && hasAppearedCheck && notFullscreen else {
          return
      }
      
      if hasCurrentItem && playerReady && (itemReady == true) {
//          print("[VID] ✅ Starting autoplay for: \(sharedVideo.url)")
        sharedVideo.player.play()
        cleanupAutoplayObservers()
      }
  }

  // Helper method to clean up autoplay observers
  private func cleanupAutoplayObservers() {
      cancellables.removeAll()
  }

  // Update the handleOnDisappear method
  private func handleOnDisappear() {
      guard let sharedVideo = sharedVideo, hasAppeared else { return }
      hasAppeared = false
      
      // Clean up all observers
      removeObserver()
      cleanupAutoplayObservers()
      
      // Handle video cleanup
      if (Nav.shared.currVideos[sharedVideo.id] ?? 0) <= 1 {
          Task(priority: .background) {
              await MainActor.run {
                  sharedVideo.player.seek(to: .zero)
                  sharedVideo.player.pause()
              }
          }
      }
      
      Nav.shared.currVideos[sharedVideo.id] = (Nav.shared.currVideos[sharedVideo.id] ?? 0) > 1 ? Nav.shared.currVideos[sharedVideo.id]! - 1 : nil
  }

  // Update the handleScenePhaseChange method to reset autoplay on reactivation
  private func handleScenePhaseChange(_ newPhase: ScenePhase) {
      guard let sharedVideo = sharedVideo, hasAppeared else { return }
      
      DispatchQueue.main.async {
          if newPhase == .active {
              // Reactivate audio session if needed
              do {
                  try AVAudioSession.sharedInstance().setActive(true)
              } catch {
                  print("[VID] Failed to reactivate audio session: \(error)")
              }
              
              // Check for failed players and reset if needed
              if (sharedVideo.player.status == .failed ||
                  sharedVideo.player.currentItem?.status == .failed) {
                  print("[VID] Player failed or stuck, resetting video")
                  resetVideo?(sharedVideo)
              } else if autoPlayVideos && !fullscreen {
                  // Reset autoplay observers and try again
                  setupAutoplayObservers()
                  attemptAutoplay()
              }
          } else if newPhase == .inactive || newPhase == .background {
              sharedVideo.player.pause()
              
              // Deactivate audio session when going to background
              do {
                  try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
              } catch {
                  print("[VID] Failed to deactivate audio session: \(error)")
              }
          }
      }
  }
  
  private func handleFullscreenChange(_ val: Bool) {
    guard let sharedVideo = sharedVideo else { return }
    
    DispatchQueue.main.async {
      if !firstFullscreen {
        firstFullscreen = true
        sharedVideo.player.isMuted = muteVideos
        sharedVideo.player.play()
      }
      
      if !val {
        // Exiting fullscreen - ensure video layer refreshes properly
        if !autoPlayVideos {
          sharedVideo.player.seek(to: .zero)
          sharedVideo.player.pause()
          firstFullscreen = false
        } else {
          // Force a brief pause/play to refresh the video layer
          let currentTime = sharedVideo.player.currentTime()
          sharedVideo.player.pause()
          
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            sharedVideo.player.play()
            // Ensure we return to the correct position
            sharedVideo.player.seek(to: currentTime)
          }
        }
      }
      
      sharedVideo.player.volume = val ? 1.0 : 0.0
    }
  }
  
  
  // MARK: - Observer Management
  
  func addObserver() {
      guard let sharedVideo = sharedVideo, !observersAdded else { return }
      observersAdded = true
      
      DispatchQueue.main.async {
        let token1 = NotificationCenter.default.addObserver(
          forName: .AVPlayerItemDidPlayToEndTime,
          object: sharedVideo.player.currentItem,
          queue: .main) { [sharedVideo] notif in
            sharedVideo.player.seek(to: .zero)
            sharedVideo.player.play()
          }
        
        let token2 = NotificationCenter.default.addObserver(
          forName: .AVPlayerItemFailedToPlayToEndTime,
          object: sharedVideo.player.currentItem,
          queue: .main) { [sharedVideo, resetVideo] notif in
            resetVideo?(sharedVideo)
          }
        
        // Store tokens for cleanup
        notificationTokens.append(token1)
        notificationTokens.append(token2)
      }
    }
  
  func removeObserver() {
      guard observersAdded else { return }
      observersAdded = false
      
      // Remove stored notification observers
      notificationTokens.forEach { token in
        NotificationCenter.default.removeObserver(token)
      }
      notificationTokens.removeAll()
    }
}

struct FullScreenVP: View {
  var sharedVideo: SharedVideo
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase // Add scene phase monitoring
  @State private var cancelDrag: Bool?
  @State private var drag: CGSize = .zero
  @State private var isDismissing = false
  @State private var isActive = true // Track if view is active
  @Default(.VideoDefSettings) private var videoDefSettings
  
  var body: some View {
    let interpolate = interpolatorBuilder([0, 100], value: abs(drag.height))
    
    GeometryReader { geometry in
      VideoPlayer(player: sharedVideo.player)
        .frame(width: geometry.size.width, height: geometry.size.height)
        .scaleEffect(interpolate([1, 0.9], true))
        .offset(cancelDrag ?? false ? .zero : drag)
        .highPriorityGesture(
          DragGesture(minimumDistance: 10)
            .onChanged { val in
              guard isActive else { return } // Only allow drag when active
              
              if cancelDrag == nil {
                cancelDrag = abs(val.translation.width) > abs(val.translation.height)
              }
              if cancelDrag == nil || cancelDrag! { return }
              
              var transaction = Transaction()
              transaction.isContinuous = true
              transaction.animation = .interpolatingSpring(stiffness: 1000, damping: 100, initialVelocity: 0)
              
              withTransaction(transaction) {
                drag = val.translation
              }
            }
            .onEnded { val in
              guard isActive else { return }
              
              let prevCancelDrag = cancelDrag
              cancelDrag = nil
              if prevCancelDrag == nil || prevCancelDrag! { return }
              
              let shouldClose = abs(val.translation.width) > 100 || abs(val.translation.height) > 100
              
              if shouldClose {
                performDismissal()
              } else {
                withAnimation(.interpolatingSpring(stiffness: 200, damping: 20, initialVelocity: 0)) {
                  drag = .zero
                }
              }
            }
        )
    }
    .ignoresSafeArea()
    .background(Color.black)
    .statusBarHidden()
    .onAppear {
      isActive = true
      setupFullscreenPlayback()
    }
    .onDisappear {
      if !isDismissing {
        resetToPortrait()
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      handleScenePhaseChange(newPhase)
    }
  }
  
  private func handleScenePhaseChange(_ newPhase: ScenePhase) {
    switch newPhase {
    case .active:
      isActive = true
      
      // Only reset drag position if there was an actual drag issue
      // Don't force any layout changes that would affect fullscreen presentation
      if abs(drag.height) > 10 || abs(drag.width) > 10 {
        withAnimation(.easeInOut(duration: 0.3)) {
          drag = .zero
        }
      }
      
      // Resume playback if it was playing and user wants audio
      if !isDismissing {
        sharedVideo.player.play()
      }
      
    case .inactive, .background:
      isActive = false
      // Pause but maintain fullscreen state
      sharedVideo.player.pause()
      
    @unknown default:
      break
    }
  }
  
  private func setupFullscreenPlayback() {
    AppDelegate.orientationLock = UIInterfaceOrientationMask.all
    
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
    
    if let rootViewController = windowScene.windows.first?.rootViewController {
      rootViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
    
    sharedVideo.player.isMuted = videoDefSettings.mute
    sharedVideo.player.volume = videoDefSettings.mute ? 0.0 : 1.0
    sharedVideo.player.play()
  }
  
  private func performDismissal() {
    isDismissing = true
    isActive = false
    
    // Reset player audio settings
    sharedVideo.player.volume = 0.0
    sharedVideo.player.isMuted = true
    
    resetToPortrait()
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      withAnimation(.interpolatingSpring(stiffness: 200, damping: 20, initialVelocity: 0)) {
        drag = .zero
        dismiss()
      }
    }
  }
  
  private func resetToPortrait() {
         AppDelegate.orientationLock = UIInterfaceOrientationMask.portrait
         
         guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
         
         // Use async to avoid blocking UI
         Task { @MainActor in
             windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
             
             if let rootViewController = windowScene.windows.first?.rootViewController {
                 rootViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
             }
         }
     }}

extension AVPlayer {
  var isVideoPlaying: Bool {
    return rate != 0 && error == nil
  }
}
