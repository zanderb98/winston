//
//  External to Internal Links.swift
//  winston
//
//  Created by Ethan Bills on 1/10/24.
//

import Foundation

class MarkdownUtil {
    static func containsSpoiler(_ text: String) -> Bool {
        return text.contains("&gt;!") && text.contains("!&lt;") ||
        text.contains(">!") && text.contains("!<")
    }
    
    static func formatForMarkdown(_ text: String, showSpoiler: Bool = false, isMatch: Bool = false, searchQuery: String? = nil) -> String {
        var processedText = text
                
        // Remove gif links, as they will be displayed
        processedText = processedText.replacingOccurrences(
            of: "https?://\\S+\\.gif",
            with: "",
            options: .regularExpression
        )
        
        // Replace http:// or https:// in existing markdown links
        processedText = processedText.replacingOccurrences(
            of: #"(\[[\w\s\[\]\/.:*]+\])\((https?:\/\/)(\S+?)(?:)\)"#,
            with: "$1(winstonapp://$3)",
            options: .regularExpression
        )
        
        // **NEW: Handle Reddit share links - keep as external https:// links**
        processedText = processedText.replacingOccurrences(
            of: #"\b(?<!\[|\()(https?://(?:www\.)?reddit\.com/r/\w+/s/\w+)\b"#,
            with: "[$0]($0)",
            options: .regularExpression
        )
        
        // **NEW: Handle standard Reddit comment links (convert to internal format)**
        processedText = processedText.replacingOccurrences(
            of: #"\b(?<!\[|\()https?://(?:www\.)?reddit\.com/r/(\w+)/comments/(\w+)(?:/[^\s\)]*)?\b"#,
            with: "[https://www.reddit.com/r/$1/comments/$2](winstonapp://r/$1/comments/$2)",
            options: .regularExpression
        )
        
        // Replace URLs with http:// or https:// (if not already in markdown format)
        processedText = processedText.replacingOccurrences(
            of: #"\b(?<!\[)(https?:\/\/)(.*\.(?:png|jpe?g|bmp|tiff|webp|svgz?|ico)(?:\?.*)?)(?!\])\b"#,
            with: "[![$0]($0)](winstonapp://$2)",
            options: .regularExpression
        )
        
        // Replace URLs with http:// or https:// (if not already in markdown format)
        processedText = processedText.replacingOccurrences(
            of: "\\b(?<!\\[|\\()(https?://)(\\S+)(?!\\]|\\))\\b",
            with: "[$0](winstonapp://$2)",
            options: .regularExpression
        )
        
        // Replace /u/example or u/example
        processedText = processedText.replacingOccurrences(
            of: "(\\s|^)(/?u/\\w+)(\\s|\\b)",
            with: " [$2](winstonapp://$2) ",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Replace /r/example or r/example (but NOT when part of a URL)
        processedText = processedText.replacingOccurrences(
            of: "(\\s|^)(?<!/)(/r/\\w+)(\\s|\\b)",
            with: " [$2](winstonapp://$2) ",
            options: [.regularExpression, .caseInsensitive]
        )
        
        processedText = cleanupText(processedText)
        
        processedText = processedText.replacingOccurrences(
            of: #"!\[gif\]\([\da-zA-Z|]+\)"#,
            with: "",
            options: .regularExpression
        )
        
        if containsSpoiler(processedText) {
            if showSpoiler {
                processedText = processedText.replacingOccurrences(
                    of: ">!",
                    with: "",
                    options: .regularExpression
                )
                
                processedText = processedText.replacingOccurrences(
                    of: "!<",
                    with: ""
                )
            } else {
                processedText = processedText.replacingOccurrences(
                    of: ">!(.*?)!<",
                    with: "■",
                    options: .regularExpression
                )
            }
            
        }
        
        if isMatch, let searchQuery, !searchQuery.isEmpty {
            processedText = processedText.replacingOccurrences(
                of: "(\(searchQuery))",
                with: "`$1`",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: "``", with: "")
        }
        
        return processedText
    }
    
    static func cleanupText(_ text: String, forBody: Bool = false) -> String {
        var processedText = text
        // Replace &#x200B; and &nbsp; with a space
        processedText = processedText.replacingOccurrences(
            of: "&amp;#x200B;|&amp;nbsp;",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Replace &#x200B; with an empty string
        processedText = processedText.replacingOccurrences(
            of: "&#x200B;",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        
        processedText = processedText.replacingOccurrences(
            of: "&gt;",
            with: ">"
        )
        
        processedText = processedText.replacingOccurrences(
            of: "&lt;",
            with: "<"
        )
        
        processedText = processedText.replacingOccurrences(
            of: "&Hat;",
            with: "^"
        )
        
        if forBody {
            // Remove gif links
            processedText = processedText.replacingOccurrences(
                of: "https?://\\S+\\.gif",
                with: "",
                options: .regularExpression
            )
            
            // Replace http:// or https:// in existing markdown links
            processedText = processedText.replacingOccurrences(
                of: #"([[(\w\])\/.:*]+])\((https?:\/\/)(\S+?|)(?:)\)"#,
                with: "",
                options: .regularExpression
            )
            
            processedText = processedText.replacingOccurrences(
                of: #"\b(?<!\[)(https?:\/\/)(.*\.(?:png|jpe?g|bmp|tiff|webp|svgz?|ico)(?:\?.*)?)(?!\])\b"#,
                with: "",
                options: .regularExpression
            )
            
            processedText = processedText.replacingOccurrences(
                of: "\\b(?<!\\[|\\()(https?://)(\\S+)(?!\\]|\\))\\b",
                with: "",
                options: .regularExpression
            )
            
            processedText = processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
            
        return processedText
    }
}
