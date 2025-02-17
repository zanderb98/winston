//
//  TextsSettings.swift
//  winston
//
//  Created by Igor Marcossi on 09/09/23.
//

import SwiftUI

struct TextsSettings: View {
  @Binding var theme: PostLinkTheme
    var body: some View {
      Group {
        
        FakeSection("Title") {
          FontSelector(theme: $theme.titleText, defaultVal: defaultTheme.postLinks.theme.titleText)
        }
        
        FakeSection("Body") {
          FontSelector(theme: $theme.bodyText, defaultVal: defaultTheme.postLinks.theme.bodyText)
        }
        
      }
    }
}
