//
//  Behavior.swift
//  winston
//
//  Created by Igor Marcossi on 05/07/23.
//

import SwiftUI
import Defaults

struct BehaviorPanel: View {
  @Default(.maxPostLinkImageHeightPercentage) var maxPostLinkImageHeightPercentage
  @Default(.openYoutubeApp) var openYoutubeApp
  @Default(.preferenceDefaultFeed) var preferenceDefaultFeed
  @Default(.useAuth) var useAuth
  @Default(.preferredSort) var preferredSort
  @Default(.preferredCommentSort) var preferredCommentSort
  @Default(.blurPostLinkNSFW) var blurPostLinkNSFW
  @Default(.blurPostNSFW) var blurPostNSFW
  @Default(.collapseAutoModerator) var collapseAutoModerator
  @Default(.readPostOnScroll) var readPostOnScroll
  @Default(.hideReadPosts) var hideReadPosts
  @Default(.enableSwipeAnywhere) var enableSwipeAnywhere
  @Default(.autoPlayVideos) var autoPlayVideos
  @Default(.loopVideos) private var loopVideos
  @Default(.lightboxViewsPost) private var lightboxViewsPost
  
  var body: some View {
    List {
      
      Section("General") {
        Toggle("Open Youtube Videos Externally", isOn: $openYoutubeApp)
        
        Picker("Default Launch Feed", selection: $preferenceDefaultFeed) {
          Text("Home").tag("home")
          Text("Popular").tag("popular")
          Text("All").tag("all")
          Text("Subscription List").tag("subList")
        }
        .pickerStyle(DefaultPickerStyle())
        
        let auth_type = Biometrics().biometricType()
        Toggle("Lock Winston With \(auth_type)", isOn: $useAuth)

        NavigationLink(value: SettingsPages.filteredSubreddits){
          Label("Filtered Subreddits", systemImage: "list.bullet")
            .labelStyle(.titleOnly)
        }
      }
      
      Section {
        Toggle("Navigation everywhere", isOn: $enableSwipeAnywhere)
      } footer: {
        Text("This will allow you to do go back by swiping anywhere in the screen, but will disable post and comments swipe gestures.")
      }
      
      Section("Posts") {
        NavigationLink("Posts swipe settings", value: SettingsPages.postSwipe)
        Toggle("Loop videos", isOn: $loopVideos)
        Toggle("Autoplay videos (muted)", isOn: $autoPlayVideos)
        Toggle("Read on preview media", isOn: $lightboxViewsPost)
        Toggle("Read on scroll", isOn: $readPostOnScroll)
        Toggle("Hide read posts", isOn: $hideReadPosts)
        Toggle("Blur NSFW in opened posts", isOn: $blurPostNSFW)
        Toggle("Blur NSFW in posts links", isOn: $blurPostLinkNSFW)
        Menu {
          ForEach(SubListingSortOption.allCases) { opt in
            if case .top(_) = opt {
              Menu {
                ForEach(SubListingSortOption.TopListingSortOption.allCases, id: \.self) { topOpt in
                  Button {
                    preferredSort = .top(topOpt)
                  } label: {
                    HStack {
                      Text(topOpt.rawValue.capitalized)
                      Spacer()
                      Image(systemName: topOpt.icon)
                    }
                  }
                }
              } label: {
                Label(opt.rawVal.value.capitalized, systemImage: opt.rawVal.icon)
              }
            } else {
              Button {
                preferredSort = opt
              } label: {
                HStack {
                  Text(opt.rawVal.value.capitalized)
                  Spacer()
                  Image(systemName: opt.rawVal.icon)
                }
              }
            }
          }
        } label: {
          Button { } label: {
            HStack {
              Text("Default post sorting")
              Spacer()
              Image(systemName: preferredSort.rawVal.icon)
            }
            .foregroundColor(.primary)
          }
        }
        
        VStack(alignment: .leading) {
          HStack {
            Text("Max Posts Image Height")
            Spacer()
            Text(maxPostLinkImageHeightPercentage == 110 ? "Original" : "\(Int(maxPostLinkImageHeightPercentage))%")
              .opacity(0.6)
          }
          Slider(value: $maxPostLinkImageHeightPercentage, in: 10...110, step: 10)
        }
      }
      
      Section("Comments") {
        NavigationLink("Comments Swipe Settings", value: SettingsPages.commentSwipe)
        Picker("Comments Sorting", selection: $preferredCommentSort) {
          ForEach(CommentSortOption.allCases, id: \.self) { val in
            Label(val.rawVal.id.capitalized, systemImage: val.rawVal.icon)
          }
        }
        
        Toggle("Collapse AutoModerator comments", isOn: $collapseAutoModerator)
      }
      
    }
    .navigationTitle("Behavior")
    .navigationBarTitleDisplayMode(.inline)
  }
}
//
//struct Behavior_Previews: PreviewProvider {
//    static var previews: some View {
//        Behavior()
//    }
//}
