//
//  FeedThemingPanel.swift
//  winston
//
//  Created by Igor Marcossi on 14/09/23.
//

import SwiftUI

struct FeedThemingPanel: View {
  @Binding var theme: WinstonTheme
  @StateObject private var routerProxy = RouterProxy(Router())
  @EnvironmentObject private var redditAPI: RedditAPI
  var body: some View {
    ScrollWithPreview(handlerBGOnly: false, theme: theme.postLinks.bg) {
      VStack(spacing: 32) {
        FakeSection("General") {
          LabeledSlider(label: "Posts spacing", value: $theme.postLinks.spacing, range: 0...56)
            .resetter($theme.postLinks.spacing, defaultTheme.postLinks.spacing)
          Divider()
          ThemeBGPicker(bg: $theme.postLinks.bg, defaultVal: defaultTheme.postLinks.bg)
        }
        
        FakeSection("Divider") {
          LineThemeEditor(theme: $theme.postLinks.divider, defaultVal: defaultTheme.postLinks.divider)
        }
        .padding(.top, 8)
        
      }
    } preview: {
      ScrollView(showsIndicators: false) {
        VStack(spacing: theme.postLinks.spacing) {
          PostLink(post: Post(data: postSampleData, api: redditAPI), sub: Subreddit(id: postSampleData.subreddit, api: redditAPI))
            .equatable()
            .environment(\.useTheme, theme)
            .environmentObject(routerProxy)
            .allowsHitTesting(false)
          
          NiceDivider(divider: theme.postLinks.divider)
          
          PostLink(post: Post(data: postSampleData, api: redditAPI), sub: Subreddit(id: postSampleData.subreddit, api: redditAPI))
            .equatable()
            .environment(\.useTheme, theme)
            .environmentObject(routerProxy)
            .allowsHitTesting(false)
        }
        .fixedSize(horizontal: false, vertical: true)
      }
      .highPriorityGesture(DragGesture())
      .frame(height: (UIScreen.screenHeight - getSafeArea().top - getSafeArea().bottom) / 2, alignment: .top)
      .clipped()
      .mask(RR(20, .black).padding(.horizontal, theme.postLinks.theme.outerHPadding))
    }
    .scrollContentBackground(.hidden)
    .themedListBG(theme.lists.bg)
    .navigationTitle("Posts feed")
    .navigationBarTitleDisplayMode(.inline)
  }
}

