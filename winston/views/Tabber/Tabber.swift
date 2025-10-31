//
//  Tabber.swift
//  winston
//
//  Created by Igor Marcossi on 24/06/23.
//

import SwiftUI
import Defaults
import SpriteKit

struct Tabber: View, Equatable {
    static func == (lhs: Tabber, rhs: Tabber) -> Bool { true }
    
    var redditCredentialsManager = RedditCredentialsManager.shared
    @State var nav = Nav.shared
    
    @State var tabBarHeight: Double? = nil
    
    @Environment(\.useTheme) private var currentTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.setTabBarHeight) private var setTabBarHeight
    @Environment(\.accountSwitcherTransmitter) private var transmitter
    @State private var medium = UIImpactFeedbackGenerator(style: .soft)
  

    @Default(.AppearanceDefSettings) private var appearanceDefSettings
    
    @State var sharedTheme: ThemeData? = nil
    @State private var tabViewID = UUID()
    
    func meTabTap() {
        if nav.activeTab == .me {
            nav[.me].resetNavPath()
        } else {
            nav.activeTab = .me
        }
    }
    
    init(theme: WinstonTheme) {
        Tabber.updateTabAndNavBar(tabTheme: theme.general.tabBarBG, navTheme: theme.general.navPanelBG)
    }
    
    static func updateTabAndNavBar(tabTheme: ThemeForegroundBG, navTheme: ThemeForegroundBG) {
        let toolbarAppearence = UINavigationBarAppearance()
        if !navTheme.blurry {
            toolbarAppearence.configureWithOpaqueBackground()
        }
        toolbarAppearence.backgroundColor = UIColor(navTheme.color())
        UINavigationBar.appearance().standardAppearance = toolbarAppearence
        let transparentAppearence = UITabBarAppearance()
        if !tabTheme.blurry {
            transparentAppearence.configureWithOpaqueBackground()
        }
        transparentAppearence.backgroundColor = UIColor(tabTheme.color())
        UITabBar.appearance().standardAppearance = transparentAppearence
    }
    
    var body: some View {
      TabView(selection: $nav.activeTab.onUpdate { newTab in
        if nav.activeTab == newTab {
          nav.resetStack()

          if newTab == .me {
            transmitter.showing = true
          }
        }
      }) {
            Tab("Posts", systemImage: "doc.text.image", value: Nav.TabIdentifier.posts) {
                WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
                    SubredditsStack(router: nav[.posts])
                }
            }
            
            Tab("Saved", systemImage: "bookmark", value: Nav.TabIdentifier.saved) {
                WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
                    SavedContainer(router: nav[.saved])
                }
            }
            
            Tab(appearanceDefSettings.showUsernameInTabBar ? (RedditAPI.shared.me?.data?.name ?? "Me") : "Me",
                systemImage: "person.fill", value: Nav.TabIdentifier.me) {
                WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
                    Me(router: nav[.me])
                }
            }
            
            Tab("Settings", systemImage: "gearshape.fill", value: Nav.TabIdentifier.settings) {
                Settings(router: nav[.settings])
            }
            
            Tab("Search", systemImage: "magnifyingglass", value: Nav.TabIdentifier.search, role: .search) {
                WithCredentialOnly(credential: redditCredentialsManager.selectedCredential) {
                  Search(router: nav[.search])
                }
            }
            
        }
        .searchToolbarBehavior(.minimize)
//        .overlay(TabBarOverlay(meTabTap: meTabTap), alignment: .bottom)
        .if(nav.activeTab == .me) {
            view in view.overlay(TabBarOverlay(meTabTap: meTabTap), alignment: .bottom)
        }
        .openFromWebListener()
        .themeFetchingListener() // From WinstonAPI
        .newCredentialListener()
        .themeImportingListener() // From local file
        .globalLoaderProvider()
        .refetchMeListener()
        .task(priority: .background) {
            cleanCredentialOrphanEntities()
            autoSelectCredentialIfNil()
            removeDefaultThemeFromThemes()
            checkForOnboardingStatus()
            if RedditCredentialsManager.shared.selectedCredential != nil {
                RedditCredentialsManager.shared.updateMe()
                Task(priority: .background) { await updatePostsInBox(RedditAPI.shared) }
            }
        }
        .accentColor(currentTheme.general.accentColor())
    }
}

