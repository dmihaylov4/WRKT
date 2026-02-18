//
//  SmartSearch.swift
//  WRKT
//
//  Smart fuzzy search with typo tolerance
//

import Foundation

/// Smart search utility with typo tolerance and fuzzy matching
enum SmartSearch {

    /// Search with typo tolerance - handles common typos and partial matches
    /// Returns true if the query matches the target string
    static func matches(query: String, in target: String) -> Bool {
        let queryLower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let targetLower = target.lowercased()

        guard !queryLower.isEmpty else { return true }

        // 1. Exact substring match (fastest check)
        if targetLower.contains(queryLower) {
            return true
        }

        // 2. Tokenize query and target into words
        let queryTokens = queryLower.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        let targetWords = targetLower.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)

        // 3. Check if all query tokens match (order-independent)
        // Each token must either:
        //   - Be a prefix of a target word (handles partial typing)
        //   - Have fuzzy match with a target word (handles typos)
        return queryTokens.allSatisfy { token in
            targetWords.contains { targetWord in
                // Prefix match (e.g., "ben" matches "bench")
                targetWord.hasPrefix(token) ||
                // Contains match (e.g., "press" is in "dumbbell press")
                targetWord.contains(token) ||
                // Fuzzy match with typo tolerance
                fuzzyMatch(token: token, targetWord: targetWord)
            }
        }
    }

    /// Fuzzy match with typo tolerance using Levenshtein distance
    /// Allows 1 character difference per 4 characters (25% tolerance)
    private static func fuzzyMatch(token: String, targetWord: String) -> Bool {
        // Don't fuzzy match very short queries (too ambiguous)
        guard token.count >= 3 else { return false }

        // Calculate allowed edit distance based on token length
        // 3-4 chars: 1 edit, 5-8 chars: 2 edits, 9+ chars: 3 edits
        let allowedDistance = max(1, token.count / 4)

        let distance = levenshteinDistance(token, targetWord)
        return distance <= allowedDistance
    }

    /// Calculate Levenshtein distance (minimum edits to transform one string to another)
    /// Handles: insertions, deletions, substitutions
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        // Optimization: if length difference is too large, skip computation
        if abs(m - n) > 3 { return abs(m - n) }

        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        // Initialize first column and row
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        // Fill the matrix
        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }

        return matrix[m][n]
    }

    /// Score a match (higher = better)
    /// Used for ranking search results
    static func score(query: String, in target: String) -> Int {
        let queryLower = query.lowercased()
        let targetLower = target.lowercased()

        var score = 0

        // Exact match (highest score)
        if targetLower == queryLower {
            score += 1000
        }

        // Starts with query (very high score)
        if targetLower.hasPrefix(queryLower) {
            score += 500
        }

        // Contains as substring (high score)
        if targetLower.contains(queryLower) {
            score += 250
        }

        // Word boundary match (e.g., "bench press" contains word "bench")
        let targetWords = targetLower.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        for word in targetWords {
            if word == queryLower {
                score += 400
            } else if word.hasPrefix(queryLower) {
                score += 200
            }
        }

        // Bonus: shorter targets ranked higher (more specific)
        score += max(0, 100 - target.count)

        return score
    }
}
