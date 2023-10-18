//
//  GalleryThumb.swift
//  winston
//
//  Created by Igor Marcossi on 22/08/23.
//

import SwiftUI
import Defaults
import Nuke

struct GalleryThumb: View {
  
  var cornerRadius: Double
  var width: CGFloat
  var height: CGFloat?
  var url: URL
  var imgRequest: ImageRequest? = nil
  
//  @Environment(\.useTheme) private var selectedTheme
  
  var body: some View {
    URLImage(url: url, imgRequest: imgRequest, processors: [.resize(width: width)])
//      .equatable()
      .scaledToFill()
      .zIndex(1)
      .allowsHitTesting(false)
      .fixedSize(horizontal: false, vertical: height.isNil)
      .frame(width: width, height: height)
      .clipped()
      .mask(RR(cornerRadius, Color.black).equatable())
      .contentShape(Rectangle())
  }
}
