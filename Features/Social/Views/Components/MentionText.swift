//
//  MentionText.swift
//  WRKT
//
//  Text component that highlights @mentions with custom styling
//

import SwiftUI

struct MentionText: View {
    let text: String
    let mentions: [CommentMention]?
    let font: Font

    init(text: String, mentions: [CommentMention]? = nil, font: Font = .subheadline) {
        self.text = text
        self.mentions = mentions
        self.font = font
    }

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(text)

        // Find all @mentions in text using regex
        let pattern = "@([a-zA-Z0-9_]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return attributed
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        // Apply styling to mentions (reverse order to preserve ranges)
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }

            if let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].foregroundColor = DS.tint
                attributed[attributedRange].font = font.weight(.semibold)
            }
        }

        return attributed
    }
}

// MARK: - Preview

#Preview("Simple Mention") {
    VStack(alignment: .leading, spacing: 16) {
        MentionText(
            text: "Hey @john_doe check this out!",
            font: .subheadline
        )

        MentionText(
            text: "Great workout @jane_smith! Let's train together @mike tomorrow",
            font: .body
        )

        MentionText(
            text: "No mentions in this text",
            font: .subheadline
        )
    }
    .padding()
    .background(Color.black)
}
