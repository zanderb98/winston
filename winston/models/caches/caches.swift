//
//  cache.swift
//  winston
//
//  Created by Igor Marcossi on 20/09/23.
//

import Foundation
import YouTubePlayerKit
import NukeUI

class Caches {
  static let ytPlayers = BaseCache<YTMediaExtracted>(cacheLimit: 35)
  static let postsAttrStr = BaseCache<AttributedString>(cacheLimit: 100)
  static let postsPreviewModels = BaseObservableCache<PreviewModel>(cacheLimit: 100)
  static let avatars = BaseCache<ImageRequest>(cacheLimit: 100)
}
