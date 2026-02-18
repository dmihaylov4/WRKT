//
//  ExerciseMedia.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 15.10.25.
//


// ExerciseMedia.swift
import Foundation

struct ExerciseMedia: Codable, Identifiable, Hashable {
    let id: String                 // should match your Exercise.id (slug)
    let exercise: String           // human name (fallback match)
    let youtube: URL?              // full YouTube link

    var youtubeId: String? {
        youtube.flatMap { YouTube.extractID(from: $0.absoluteString) }
    }
}

enum YouTube {
    static func extractID(from url: String) -> String? {
        guard let c = URLComponents(string: url) else { return nil }
        let host = (c.host ?? "").lowercased()
        let path = c.path

        // youtu.be/VIDEOID
        if host.contains("youtu.be") {
            return path.split(separator: "/").first.map(String.init)
        }
        // youtube.com/watch?v=VIDEOID
        if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
            if let v = c.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty { return v }
            // youtube.com/embed/VIDEOID or /shorts/VIDEOID
            let comps = path.split(separator: "/").map(String.init)
            if let idx = comps.firstIndex(where: { $0 == "embed" || $0 == "shorts" }),
               comps.count > idx+1 { return comps[idx+1] }
        }
        return nil
    }
}
