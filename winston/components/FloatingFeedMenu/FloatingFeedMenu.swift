//
//  FloatingFeedMenu.swift
//  winston
//
//  Created by Igor Marcossi on 16/12/23.
//

import SwiftUI
import Combine
import Defaults

struct FloatingFeedMenu: View, Equatable {
  static func == (lhs: FloatingFeedMenu, rhs: FloatingFeedMenu) -> Bool {
    lhs.subId == rhs.subId && lhs.filters == rhs.filters && lhs.selectedFilter == rhs.selectedFilter
  }
  
  @Default(.subredditFilters) var subredditFilters
  @Default(.localFavorites) var localFavorites
  @Default(.localHideSeen) var localHideSeen
  
  var subId: String
  var subName: String?
  var filters: [ShallowCachedFilter]
  @Binding var selectedFilter: ShallowCachedFilter?
  @Binding var customFilter: ShallowCachedFilter?
  var refresh: (() async -> Void)
  
  @State private var menuOpen = false
  @State private var showingFilters = false
  @State private var compact: Bool
  @State private var refreshRotationDegrees = 0.0
  
  @Namespace private var ns
  
  private let mainTriggerSize: Double = 48
  private let actionsSize: Double = 48
  private let itemsSpacing: Double = 20
  private let screenEdgeMargin: Double = 12
  
  var itemsSpacingDownscaled: Double { itemsSpacing - ((mainTriggerSize - actionsSize) / 2) }
  
  @Default(.SubredditFeedDefSettings) var subredditFeedDefSettings
  @Default(.PostLinkDefSettings) var postLinkDefSettings
  
  init(subId: String, subName: String?, filters: [ShallowCachedFilter], selectedFilter: Binding<ShallowCachedFilter?>, customFilter: Binding<ShallowCachedFilter?>, refresh: @escaping (() async -> Void)) {
    self.subId = subId
    self.subName = subName
    self.filters = filters
    self.refresh = refresh
    
    self._selectedFilter = selectedFilter
    self._customFilter = customFilter
    
    _compact = State(initialValue: Defaults[.SubredditFeedDefSettings].compactPerSubreddit[subId] ?? Defaults[.PostLinkDefSettings].compactMode.enabled)
  }
  
  func dismiss() {
    if menuOpen {
      Hap.shared.play(intensity: 0.75, sharpness: 0.4)
      //      doThisAfter(0) {
      withAnimation {
        showingFilters = false
      }
      withAnimation(.snappy(extraBounce: 0.3)) {
        menuOpen = false
      }
      
    }
  }
  
  func selectFilter(_ filter: ShallowCachedFilter) {
    let newVal = selectedFilter == filter ? nil : filter
    withAnimation(.spring) {
      selectedFilter = newVal
    }
  }
  
  var body: some View {
    let customFilters = CachedFilter.filtersFromDefaultsString(subredditFilters[subId])

    ZStack(alignment: .bottomTrailing) {
      FloatingBGBlur(active: menuOpen, dismiss: dismiss).equatable()
      
      GlassEffectContainer {
        HStack(alignment: .bottom, spacing: 0) {
          Spacer()
          ZStack(alignment: .bottomTrailing) {
            if !showingFilters, let selectedFilter {
              FilterButton(filter: selectedFilter, isSelected: true, selectFilter: selectFilter, customFilter: $customFilter)
                .matchedGeometryEffect(id: "floating-\(selectedFilter.id)", in: ns, properties: .position)
                .padding(.trailing, itemsSpacingDownscaled)
                .frame(height: mainTriggerSize)
                .padding(.bottom, screenEdgeMargin)
                .transition(.offset(x: 0.01))
            }
            
            if menuOpen {
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                  ForEach(Array(customFilters.enumerated()).reversed(), id: \.element) { i, el in
                    let isSelected = selectedFilter?.id == el.id
                    let placeholder = isSelected && !showingFilters
                    let elId = "floating-\(el.id)\(placeholder ? "-placeholder" : "")"
                    
                    FilterButton(filter: el, isSelected: isSelected, selectFilter: selectFilter, customFilter: $customFilter)
                    //                    .equatable()
                      .rotation3DEffect(Angle(degrees: 180), axis: (x: CGFloat(0), y: CGFloat(10), z: CGFloat(0)))
                      .matchedGeometryEffect(id: "floating-\(el.id)", in: ns)
                      .scaleEffect(x: showingFilters || isSelected ? 1 : 0.01, y: 1, anchor: .leading)
                      .opacity((showingFilters || isSelected) && !placeholder ? 1 : 0)
                      .animation(.bouncy(duration: 0.4).delay(Double(showingFilters && !isSelected ? customFilters.count - i - 1 : 0) * 0.05), value: showingFilters)
                      .transition(.offset(x: -0.01))
                      .id(elId)
                  }
                }
              }
              .environment(\EnvironmentValues.refresh as! WritableKeyPath<EnvironmentValues, RefreshAction?>, nil)
              .flipsForRightToLeftLayoutDirection(true)
              .environment(\.layoutDirection, .rightToLeft)
              .padding(.trailing, 12)
              .frame(height: mainTriggerSize, alignment: .trailing)
              .padding(.top, 16)
              .contentShape(Rectangle())
              .scrollClipDisabled()
              .padding(.bottom, screenEdgeMargin)
              .transition(.offset(x: 0.01))
            }
            
            let showBackButton = (!menuOpen || customFilters.count == 0) && selectedFilter == nil
            
            if showBackButton {
              HStack(spacing: 14) {
                Image(systemName: "chevron.left")
                  .fontSize(22, .semibold)
//                  .foregroundStyle(Color.accentColor)
                  .padding(.horizontal, 14)
                  .frame(width: actionsSize, height: actionsSize)
                  .drawingGroup()
                  .glassEffect(.regular.interactive(), in: .circle)
                  .increaseHitboxOf(actionsSize, by: 1.125, shape: Circle(), disable: false)
                  .onTapGesture {
                    Hap.shared.play(intensity: 0.75, sharpness: 0.9)
                    if Nav.shared.activeTab == .saved {
                      Nav.shared.activeTab = .posts
                    } else {
                      Nav.shared.activeRouter.goBack()
                    }
                  }
                Image(systemName: "arrow.clockwise")
                  .fontSize(22, .semibold)
//                  .foregroundStyle(Color.accentColor)
                  .padding(.horizontal, 14)
                  .frame(width: actionsSize, height: actionsSize)
                  .rotationEffect(Angle(degrees: refreshRotationDegrees), anchor: .center)
                  .drawingGroup()
                  .glassEffect(.regular.interactive(), in: .circle)
                  .opacity(1)
                  .allowsHitTesting(true)
                  .onTapGesture {
                    Hap.shared.play(intensity: 0.75, sharpness: 0.9)
                    Task {
                      await refresh()
                    }
                    withAnimation {
                      refreshRotationDegrees += 360
                    }
                  }
              }
              .padding(.trailing, 12)
              .frame(height: mainTriggerSize, alignment: .trailing)
              .padding(.top, 16)
              .contentShape(Rectangle())
              .scrollClipDisabled()
              .padding(.bottom, screenEdgeMargin)
              .opacity(1)
              .allowsHitTesting(true)
            }
            
          }
          
          // -
          
          VStack(spacing: itemsSpacingDownscaled) {
            VStack(spacing: itemsSpacing) {
              if menuOpen {
                Image(systemName: localHideSeen.contains(subId) ? "eye.slash.fill" : "eye.slash")
                  .fontSize(22, .bold)
                  .frame(width: actionsSize, height: actionsSize)
                  .foregroundStyle(Color.accentColor)
                  .drawingGroup()
                  .glassEffect(.regular.interactive(), in: .circle)
                  .transition(.comeFrom(.bottom, index: 1, total: 2))
                  .highPriorityGesture(TapGesture().onEnded({
                    Hap.shared.play(intensity: 0.75, sharpness: 0.9)
                    
                    withAnimation {
                      if localHideSeen.contains(subId) {
                        localHideSeen = localHideSeen.filter{ $0 != subId }
                      } else {
                        localHideSeen.append(subId)
                      }
                      
                      Task {
                        await refresh()
                      }
                    }
                  }))
                
                if let subName {
                  Image(systemName: localFavorites.contains(subName) ? "star.fill" : "star")
                    .fontSize(22, .bold)
                    .frame(width: actionsSize, height: actionsSize)
                    .foregroundStyle(Color.accentColor)
                    .drawingGroup()
                    .glassEffect(.regular.interactive(), in: .circle)
                    .transition(.comeFrom(.bottom, index: 1, total: 2))
                    .highPriorityGesture(TapGesture().onEnded({
                      Hap.shared.play(intensity: 0.75, sharpness: 0.9)
                      
                      withAnimation {
                        if localFavorites.contains(subName) {
                          localFavorites = localFavorites.filter{ $0 != subName }
                        } else {
                          localFavorites.append(subName)
                        }
                      }
                    }))
                }
                
                Image(systemName: compact ? "doc.text.image" : "doc.plaintext")
                  .fontSize(22, .bold)
                  .frame(width: actionsSize, height: actionsSize)
                  .foregroundColor(Color.accentColor)
                  .drawingGroup()
                  .glassEffect(.regular.interactive(), in: .circle)
                  .transition(.comeFrom(.bottom, index: 0, total: 2))
                  .increaseHitboxOf(actionsSize, by: 1.125, shape: Circle(), disable: menuOpen)
                  .highPriorityGesture(TapGesture().onEnded({
                    Hap.shared.play(intensity: 0.75, sharpness: 0.9)
                    compact = !compact
                    subredditFeedDefSettings.compactPerSubreddit[self.subId] = compact
                  }))
                
                Image(systemName: "plus")
                  .fontSize(22, .bold)
                  .frame(width: actionsSize, height: actionsSize)
                  .foregroundColor(Color.accentColor)
                  .drawingGroup()
                  .glassEffect(.regular.interactive(), in: .circle)
                  .transition(.comeFrom(.bottom, index: 0, total: 2))
                  .increaseHitboxOf(actionsSize, by: 1.125, shape: Circle(), disable: menuOpen)
                  .highPriorityGesture(TapGesture().onEnded({
                    Hap.shared.play(intensity: 0.75, sharpness: 0.9)
                    customFilter = CachedFilter.getNewShallow(subredditId: subId)
                  }))
              }
            }
            
            FloatingMainTrigger(menuOpen: $menuOpen, showingFilters: $showingFilters, dismiss: dismiss, size: mainTriggerSize, actionsSize: actionsSize)
          }
          .padding(.trailing, 28)
          .padding(.bottom, screenEdgeMargin)
        }
      }
    }
  }
}



extension View {
  func floatingMenu(subId: String, subName: String?, filters: [ShallowCachedFilter], selectedFilter: Binding<ShallowCachedFilter?>, customFilter: Binding<ShallowCachedFilter?>, refresh: @escaping (() async -> Void)) -> some View {
    self.overlay(alignment: .bottomTrailing) {
      FloatingFeedMenu(subId: subId, subName: subName, filters: filters, selectedFilter: selectedFilter, customFilter: customFilter, refresh: refresh)
    }
  }
}

func createTimer(seconds: Double, callback: @escaping (Int, Int) -> Void) -> Timer {
  let totalLoops = Int(120.0 * seconds)
  var currentLoop = 0
  
  let timer = Timer.scheduledTimer(withTimeInterval: 1.0/120.0, repeats: true) { (timer) in
    callback(currentLoop, totalLoops)
    currentLoop += 1
    if currentLoop >= totalLoops {
      timer.invalidate()
    }
  }
  RunLoop.current.add(timer, forMode: .common)
  
  return timer
}

