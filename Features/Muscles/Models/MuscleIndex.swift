// MuscleIndex.swift (or your existing Untitled.swift)
import Foundation

// MuscleIndex.swift

struct MuscleIndex: Decodable {
    struct Side: Decodable { let classToIds: [String: [String]] }
    let front: Side
    let back:  Side

    static let shared: MuscleIndex = {
        // Always build a runtime map from the current SVGs
        let runtime = buildFromSVGs(frontName: "torso", backName: "torso_back")

        // If JSON exists, merge it; otherwise use runtime directly.
        if let url  = Bundle.main.url(forResource: "muscles_index", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONDecoder().decode(MuscleIndex.self, from: data) {
            return merge(json, runtime)
        } else {
            return runtime
        }
    }()

    /// Old merged API (kept for compatibility)
    func ids(forClassTokens tokens: [String]) -> [String] {
        var out = Set<String>()
        for t in tokens.map({ $0.lowercased() }) {
            if let f = front.classToIds[t] { out.formUnion(f) }
            if let b = back .classToIds[t] { out.formUnion(b) }
        }
        return Array(out)
    }

    /// Preferred side-aware API
    func ids(forClassTokens tokens: [String], side: SVGHumanBodyView.Side) -> [String] {
        var out = Set<String>()
        let src = (side == .front) ? front.classToIds : back.classToIds
        for t in tokens.map({ $0.lowercased() }) {
            if let ids = src[t] { out.formUnion(ids) }
        }
        return Array(out)
    }

    /// Union json+runtime so missing tokens (like "obliques") are filled by runtime.
    private static func merge(_ a: MuscleIndex, _ b: MuscleIndex) -> MuscleIndex {
        func mergeSide(_ sa: Side, _ sb: Side) -> Side {
            var out: [String: Set<String>] = [:]
            for (k, v) in sa.classToIds { out[k, default: []].formUnion(v) }
            for (k, v) in sb.classToIds { out[k, default: []].formUnion(v) }
            return .init(classToIds: out.mapValues { Array($0) })
        }
        return .init(front: mergeSide(a.front, b.front), back: mergeSide(a.back, b.back))
    }
}

// ===== Runtime builder (unchanged; include if you don’t have it yet) =====
private extension MuscleIndex {
    static func buildFromSVGs(frontName: String, backName: String) -> MuscleIndex {
        let frontMap = parseSVG(named: frontName)
        let backMap  = parseSVG(named: backName)
        return .init(front: .init(classToIds: frontMap), back: .init(classToIds: backMap))
    }

    static func parseSVG(named name: String) -> [String: [String]] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }

        let p1 = #"<g\b[^>]*?\bid="([^"]+)"[^>]*?\bclass="([^"]+)"[^>]*?>"#
        let p2 = #"<g\b[^>]*?\bclass="([^"]+)"[^>]*?\bid="([^"]+)"[^>]*?>"#

        guard let re1 = try? NSRegularExpression(pattern: p1, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let re2 = try? NSRegularExpression(pattern: p2, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            AppLogger.error("Failed to create regex patterns for SVG parsing", category: AppLogger.app)
            return [:]
        }

        var map: [String: Set<String>] = [:]
        let ns = raw as NSString

        func ingest(_ re: NSRegularExpression, _ idIdx: Int, _ classIdx: Int) {
            re.matches(in: raw, range: NSRange(location: 0, length: ns.length)).forEach { m in
                let id     = ns.substring(with: m.range(at: idIdx))
                let clsRaw = ns.substring(with: m.range(at: classIdx)).lowercased()

                // Base tokens from class
                var tokens = clsRaw
                    .replacingOccurrences(of: "_", with: "-")
                    .split{ $0 == " " || $0 == "\t" }
                    .map(String.init)
                    .filter { $0 != "muscle" && !$0.isEmpty }

                // Also add tokens from the id itself (covers your exact list)
                tokens += id.lowercased()
                    .replacingOccurrences(of: "_", with: "-")
                    .split(separator: "-")
                    .map(String.init)

                // A few helpful aliases
                var extras: [String] = []
                if tokens.contains("triceps") { extras.append("triceps-brachii") }
                if tokens.contains("rectus") && tokens.contains("abdominis") {
                    extras += ["rectus-abdominis","abs","abdominals"]
                }
                if tokens.contains("deltoid") && (tokens.contains("anterior") || tokens.contains("ant")) {
                    extras += ["anterior-deltoid"]
                }
                if tokens.contains("quadriceps") || tokens.contains("quads") {
                    extras += ["quads"]
                }
                if tokens.contains("latissimus") && tokens.contains("dorsi") {
                    extras += ["latissimus-dorsi","lats"]
                }

                for t in Set(tokens + extras) {
                    map[t, default: []].insert(id)
                    if t.hasSuffix("s") { map[String(t.dropLast()), default: []].insert(id) }
                }
            }
        }
        ingest(re1, 1, 2)
        ingest(re2, 2, 1)

        return map.mapValues { Array($0) }
    }
}
