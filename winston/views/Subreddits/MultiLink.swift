//
//  MultiLink.swift
//  winston
//
//  Created by Igor Marcossi on 20/08/23.
//

import SwiftUI
import Popovers

struct MultiLink: View {
  var multi: Multi
  @State private var subs: [Subreddit] = []
  
  var body: some View {
    Button {
      Nav.to(.reddit(.multiFeed(multi)))
    } label: {
      HStack(spacing: 12) {
        Group {
          if let imgLink = multi.data?.icon_url, let imgURL = URL(string: imgLink) {
            URLImage(url: imgURL)
              .scaledToFill()
              .frame(width: 28, height: 28)
              .mask(Circle())
          } else {
              let color = Color(uiColor: UIColor(hex: multi.data?.key_color ?? "#8E8E93"))
            ZStack {
              Circle().fill(color.opacity(0.2))
              Image(systemName: "person.3.fill")
                .foregroundColor(color)
                .font(.system(size: 14, weight: .semibold))
            }
            .frame(width: 28, height: 28)
          }
        }
        Text(multi.data?.display_name ?? "")
          .foregroundColor(.primary)
          .fontSize(16, .medium)
          .lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      ForEach(subs) { sub in
        if let data = sub.data {
          SubItemButton(data: data, action: { Nav.to(.reddit(.subFeed(sub))) })
        }
      }
    }
    .onAppear {
      if subs.count == 0 {
        subs = multi.data?.subreddits?.compactMap { sub in
          if let data = sub.data { return Subreddit(data: data) }
          return nil
        } ?? []
      }
    }
  }
}

