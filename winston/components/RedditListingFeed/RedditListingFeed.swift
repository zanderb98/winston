//
//  SubredditPosts.swift
//  winston
//
//  Created by Igor Marcossi on 23/01/24.
//

import SwiftUI
import Defaults
import SwiftData

struct RedditListingFeed<Header: View, Footer: View, S: Sorting>: View {
  private var showSubInPosts: Bool
  private var feedId: String
  private var title: String
  private var theme: ThemeBG
  //  private var fetch: (_ force: Bool, _ lastElementId: String?, _ searchQuery: String?) async -> [RedditEntityType]?
  private var header: () -> Header
  private var footer: () -> Footer
  private var subreddit: Subreddit?
  private var disableSearch: Bool
  var forceRefresh: Binding<Bool>?
  @Default(.SubredditFeedDefSettings) private var subredditFeedDefSettings
  @Default(.GeneralDefSettings) private var generalDefSettings
  @Default(.localHideSeen) private var localHideSeen
  
  @State private var customFilter: ShallowCachedFilter?
  @State private var currentPostId: String? = nil
  @State private var currentPostAnchor: UnitPoint = .center
  
  @SilentState private var appearedPosts: [String] = []
  @SilentState private var disappearedPosts: [String] = []
  
  func getSubIcon(_ subId: String) -> String {
    if subId == "all" {
      return "signpost.right.and.left.circle.fill"
    } else if subId == "home" {
      return "house.circle.fill"
    } else if subId == savedKeyword {
      return "bookmark.circle.fill"
    } else if subId == "popular" {
      return "chart.line.uptrend.xyaxis.circle.fill"
    }
    
    return "questionmark.circle.fill"
  }
  
  func getSubColor(_ subId: String) -> Color {
    if subId == "all" {
      return Color.hex("F1A33C")
    } else if subId == "home" {
      return  Color.hex("EB5545")
    } else if subId == savedKeyword {
      return  Color.hex("67CD67")
    } else if subId == "popular" {
      return  Color.hex("3B82F6")
    }
    
    return Color.accentColor
  }
  
  
  init(feedId: String, showSubInPosts: Bool = false, title: String, theme: ThemeBG, fetch: @escaping FeedItemsManager<S>.ItemsFetchFn, @ViewBuilder header: @escaping () -> Header = { EmptyView() }, @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }, initialSorting: S? = nil, disableSearch: Bool = true, subreddit: Subreddit? = nil, forceRefresh: Binding<Bool>? = nil) where S == SubListingSortOption {
    self.showSubInPosts = showSubInPosts
    self.feedId = feedId
    self.title = title
    self.theme = theme
    self.header = header
    self.footer = footer
    self.subreddit = subreddit
    self.disableSearch = disableSearch
    self.forceRefresh = forceRefresh // Assign the optional forceRefresh Binding
    self._itemsManager = .init(wrappedValue: FeedItemsManager(sorting: initialSorting, fetchFn: fetch, subId: subreddit?.id ?? ""))
    self._searchEnabled = .init(initialValue: disableSearch)
    self._filters = FetchRequest<CachedFilter>(sortDescriptors: [NSSortDescriptor(key: "text", ascending: true)], predicate: NSPredicate(format: "subID == %@", (subreddit?.data?.display_name ?? feedId) as CVarArg), animation: .default)
  }
  
  @FetchRequest private var filters: FetchedResults<CachedFilter>
  
  @State private var searchEnabled: Bool
  @SilentState private var fetchedFilters: Bool = false
  
  @StateObject private var itemsManager: FeedItemsManager<S>
  
  @Environment(\.useTheme) private var selectedTheme
  @Environment(\.contentWidth) private var contentWidth
  
  @Default(.PostLinkDefSettings) private var postLinkDefSettings
  @Default(.SubredditFeedDefSettings) private var feedDefSettings
  
  func refetch(_ force: Bool = false) async {
    //    if let subreddit, !feedsAndSuch.contains(subreddit.id) {
    //      Task {
    //        withAnimation { itemsManager.loadingPinned = true }
    //        if let pinnedPosts = await subreddit.fetchPinnedPosts() {
    //          itemsManager.pinnedPosts = pinnedPosts
    //        }
    //        withAnimation { itemsManager.loadingPinned = false }
    //      }
    //    }
    await itemsManager.fetchCaller(loadingMore: false, force: force, hideRead: localHideSeen.contains(subreddit?.id ?? ""))
    //        if let subreddit, !fetchedFilters {
    //            Task { await subreddit.fetchAndCacheFlairs() }
    //            fetchedFilters = true
    //        }
  }
  
  func refresh() async {
    await refetch(true)
  }
  
  func setCurrentOpenPost(post: Post) {
    currentPostId = post.id + (post.winstonData?.uniqueId ?? "")
    //      if let currentVideo = post.winstonData?.media as? SharedVideo {
    //        Nav.shared.currVideoId = currentVideo.id
    //      } else {
    //        Nav.shared.currVideoId = nil
    //      }
    
    if let height = post.winstonData?.postDimensions.size.height, height > 640 {
      currentPostAnchor = .top
    } else {
      currentPostAnchor = .center
    }
  }
  
  func sortUpdated(opt: S) {
    itemsManager.sorting = opt
    feedDefSettings.subredditSorts[self.subreddit?.id ?? feedId] = opt as? SubListingSortOption
  }
  
  @ViewBuilder
  func getPinnedSection() -> some View {
    if itemsManager.displayMode != .loading, itemsManager.pinnedPosts.count > 0 || itemsManager.loadingPinned {
      let isThereDivider = selectedTheme.postLinks.divider.style != .no
      let paddingH = selectedTheme.postLinks.theme.outerHPadding
      let paddingV = selectedTheme.postLinks.spacing / (isThereDivider ? 4 : 2)
      Section("Pinned") {
        if itemsManager.loadingPinned {
          ProgressView().frame(maxWidth:.infinity, minHeight: 100)
        } else {
          ScrollView(.horizontal) {
            LazyHStack(spacing: paddingV * 2) {
              ForEach(itemsManager.pinnedPosts) { post in
                StickiedPostLink(post: post)
              }
            }
            .scrollTargetLayout()
            .padding(.horizontal, paddingH)
            .padding(.bottom, paddingV)
          }
          .scrollTargetBehavior(.viewAligned)
          .listRowInsets(.zero)
          .scrollIndicators(.hidden)
        }
      }
      .listRowInsets(EdgeInsets(top: 0, leading: paddingH, bottom: 0, trailing: paddingH))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
    }
  }
  
  var body: some View {
    let shallowCachedFilters = filters.map { $0.getShallow() }
    let isThereDivider = selectedTheme.postLinks.divider.style != .no
    let paddingH = selectedTheme.postLinks.theme.outerHPadding
    let paddingV = selectedTheme.postLinks.spacing / (isThereDivider ? 4 : 2)
    GeometryReader { geo in
      ScrollViewReader { proxy in
        List {
          header()
          
          //        getPinnedSection()
          
          Group {
            switch itemsManager.displayMode {
            case .loading:
              Section {
                     VStack(spacing: 16) {
                         // Normal progress view
                         ProgressView()
                             .scaleEffect(1.2)
                         
                         // Fixed height container for dots so ProgressView doesn't move
                         VStack {
                             HStack(spacing: 4) {
                                 ForEach(1...min(max(itemsManager.loadingProgress.currentCall, 1), 10), id: \.self) { index in
                                     Circle()
                                         .fill(index == itemsManager.loadingProgress.currentCall ? Color.primary.opacity(0.6) : Color.secondary.opacity(0.2))
                                         .frame(width: 6, height: 6)
                                         .scaleEffect(index == itemsManager.loadingProgress.currentCall ? 1.2 : 1.0)
                                         .opacity(index <= itemsManager.loadingProgress.currentCall && itemsManager.loadingProgress.currentCall > 1 ? 1.0 : 0.0)
                                         .animation(.easeInOut(duration: 0.3), value: itemsManager.loadingProgress.currentCall)
                                 }
                                 
                                 if itemsManager.loadingProgress.currentCall > 10 {
                                     HStack(spacing: 2) {
                                         ForEach(0..<3, id: \.self) { _ in
                                             Circle()
                                                 .fill(Color.secondary.opacity(0.3))
                                                 .frame(width: 3, height: 3)
                                         }
                                     }
                                     .opacity(itemsManager.loadingProgress.currentCall > 10 ? 1.0 : 0.0)
                                     .animation(.easeInOut(duration: 0.3), value: itemsManager.loadingProgress.currentCall > 10)
                                 }
                             }
                         }
                         .frame(height: 20) // Fixed height container
                     }
                     .frame(maxWidth: .infinity, minHeight: geo.size.height)
                     .padding(.bottom, 32)
                     .id(UUID())
                 }
            case .empty:
              Text("Nothing around here :(")
                .frame(maxWidth: .infinity)
            case .error, .endOfFeed, .items:
              
              Section {
                ForEach(Array(itemsManager.entities.enumerated()), id: \.element) { i, el in
                  Group {
                    switch el {
                    case .post(let post):
                      if let winstonData = post.winstonData, let sub = winstonData.subreddit ?? subreddit {
                        PostLink(id: post.id, theme: selectedTheme.postLinks, showSub: showSubInPosts, compactPerSubreddit: feedDefSettings.compactPerSubreddit[sub.id], contentWidth: contentWidth, defSettings: postLinkDefSettings, setCurrentOpenPost: setCurrentOpenPost)
                          .id(post.id + winstonData.uniqueId)
                          .environment(\.contextPost, post)
                          .environment(\.contextSubreddit, sub)
                          .environment(\.contextPostWinstonData, winstonData)
                          .listRowInsets(EdgeInsets(top: paddingV, leading: paddingH, bottom: paddingV, trailing: paddingH))
                          .onAppear {
                            if !appearedPosts.contains(post.id) {
                              appearedPosts.append(post.id)
                              
                              if disappearedPosts.count > 0 {
                                SeenSubredditManager.shared.postsSeen(subId: subreddit?.id ?? "", newPostIds: disappearedPosts)
                                disappearedPosts = []
                              }
                            }
                          }.onDisappear {
                            if !(subreddit?.data?.over18 ?? false) {
                              disappearedPosts.append(post.id)
                            }
                          }
                        
                        if isThereDivider /*&& (i != (itemsManager.entities.count - 1))*/ {
                          NiceDivider(divider: selectedTheme.postLinks.divider)
                            .id("\(post.id)-divider")
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        }
                      }
                    case .subreddit(let sub): SubredditLink(sub: sub)
                    case .multi(_): EmptyView()
                    case .comment(let comment):
                      VStack(spacing: 8) {
                        ShortCommentPostLink(comment: comment)
                          .padding(.horizontal, 12)
                        if let commentWinstonData = comment.winstonData {
                          CommentLink(showReplies: false, comment: comment, commentWinstonData: commentWinstonData, children: comment.childrenWinston)
                        }
                      }
                      .padding(.vertical, 12)
                      .background(PostLinkBG(theme: selectedTheme.postLinks.theme, stickied: false, secondary: false))
                      .mask(RR(selectedTheme.postLinks.theme.cornerRadius, Color.black))
                      .allowsHitTesting(false)
                      .contentShape(Rectangle())
                      .onTapGesture {
                        if let data = comment.data, let link_id = data.link_id, let subID = data.subreddit {
                          Nav.to(.reddit(.postHighlighted(Post(id: link_id, subID: subID), comment.id)))
                        }
                      }
                      .listRowInsets(EdgeInsets(top: paddingV, leading: paddingH, bottom: paddingV, trailing: paddingH))
                    case .user(let user): UserLink(user: user)
                    case .message(let message):
                      let isThereDivider = selectedTheme.postLinks.divider.style != .no
                      let paddingH = selectedTheme.postLinks.theme.outerHPadding
                      let paddingV = selectedTheme.postLinks.spacing / (isThereDivider ? 4 : 2)
                      MessageLink(message: message)
                        .listRowInsets(EdgeInsets(top: paddingV, leading: paddingH, bottom: paddingV, trailing: paddingH))
                      
                      if isThereDivider && (i != (itemsManager.entities.count - 1)) {
                        NiceDivider(divider: selectedTheme.postLinks.divider)
                          .id("\(message.id)-divider")
                          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                      }
                    }
                  }
                  .onAppear { Task { await itemsManager.elementAppeared(entity: el, index: i, currentPostId: currentPostId) } }
                  .onDisappear { Task { await itemsManager.elementDisappeared(entity: el, index: i) } }
                }
              }
              
              //              if itemsManager.displayMode == .endOfFeed {
              //                Section {
              //                  EndOfFeedView()
              //                }
              //              }
              
              if itemsManager.displayMode == .error {
                Section {
                  VStack {
                    Text("There was an error")
                    
                    Button("Manually reload", systemImage: "arrow.clockwise") {
                      withAnimation {
                        itemsManager.displayMode = .items
                      }
                      Task { await itemsManager.fetchCaller(loadingMore: true, hideRead: localHideSeen.contains(subreddit?.id ?? "")) }
                    }
                    .buttonStyle(.actionSecondary)
                  }
                  .frame(maxWidth: .infinity)
                  .compositingGroup()
                  .opacity(0.5)
                  .id("error-load-more-manual")
                }
              }
              
              //          default: EmptyView()
            }
            
            if itemsManager.displayMode == .items {
              Section {
                ProgressView()
                  .frame(maxWidth: .infinity, minHeight: 150)
                  .id(UUID())
              }
            }
          }
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
          
          footer()
        }
        .themedListBG(theme)
        .if(!disableSearch) { $0.searchable(text: $itemsManager.searchQuery.value) }
        .scrollIndicators(.never)
        .listStyle(.plain)
        .navigationTitle(title)
        .environment(\.defaultMinListRowHeight, 1)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            HStack {
              if let currSort = itemsManager.sorting {
                Menu {
                  ForEach(Array(S.allCases), id: \.self) { opt in
                    if let children = opt.meta.children {
                      Menu {
                        ForEach(children, id: \.self.meta.apiValue) { child in
                          if let val = child.valueWithParent as? S {
                            Button(child.meta.label, systemImage: child.meta.icon) {
                              sortUpdated(opt: val)
                            }
                          }
                        }
                      } label: {
                        Label(opt.meta.label, systemImage: opt.meta.icon)
                      }
                    } else {
                      Button(opt.meta.label, systemImage: opt.meta.icon) {
                        sortUpdated(opt: opt)
                      }
                    }
                  }
                } label: {
                  Image(systemName: currSort.meta.icon)
                    .foregroundColor(Color.accentColor)
                  //                    .fontSize(17, .bold)
                }
              }
              //          .disabled(subreddit.id == "saved")
              //        }
              
              if let sub = subreddit, let data = sub.data {
                Button {
                  Nav.to(.reddit(.subInfo(sub)))
                } label: {
                  SubredditIcon(subredditIconKit: data.subredditIconKit)
                }
              } else {
                let subId = subreddit?.id ?? ""
                Image(systemName: getSubIcon(subId))
                  .symbolRenderingMode(.palette)
                  .foregroundStyle(.white, getSubColor(subId))
                  .fontSize(24)
              }
            }
          }
        }
        .floatingMenu(subId: subreddit?.id ?? feedId, subName: subreddit?.data?.name ?? feedId, filters: shallowCachedFilters, selectedFilter: $itemsManager.selectedFilter, customFilter: $customFilter, refresh: refresh)
        //    .onChange(of: itemsManager.selectedFilter) { searchEnabled = $1?.type != .custom }
        .refreshable { await refresh() }
        .onChange(of: generalDefSettings.redditCredentialSelectedID) { _, _ in
          withAnimation {
            itemsManager.entities = []
            itemsManager.displayMode = .loading
          }
          
          Task { await refetch() }
        }
        .onChange(of: itemsManager.searchQuery.value) { itemsManager.displayMode = .loading }
        .onChange(of: subredditFeedDefSettings.chunkLoadSize) { itemsManager.chunkSize = $1 }
        .onChange(of: forceRefresh?.wrappedValue) { newValue in
          if newValue == true {
            Task {
              await refresh()
              forceRefresh?.wrappedValue = false // Reset
            }
          }
        }
        .onChange(of: itemsManager.searchQuery.debounced) { Task { await refetch() } }
        .onChange(of: itemsManager.selectedFilter?.text) { Task { await refetch() } }
        .onChange(of: itemsManager.sorting?.meta.apiValue) { Task { await refetch() } }
        .onAppear {
          if currentPostId != nil {
            proxy.scrollTo(currentPostId, anchor: currentPostAnchor)
            itemsManager.lastAppearedId = ""
          }
          
          itemsManager.scrollProxy = proxy
          currentPostId = nil
          //            Nav.shared.currVideoId = nil
          
          if itemsManager.displayMode != .loading { return }
          Task { await refetch() }
        }
        .onDisappear {
          disappearedPosts = []
          appearedPosts = []
        }
        .sheet(item: $customFilter) { custom in
          CustomFilterView(filter: custom, subId: subreddit?.id ?? feedId)
        }
      }
    }
  }
}
