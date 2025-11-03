//
//  CollectionExtensions.swift
//  WRKT
//
//  Useful extensions for Swift collections

import Foundation

// MARK: - Array Safe Subscript

extension Array {
    /// Safe array subscript that returns nil instead of crashing on out-of-bounds access
    ///
    /// Example:
    /// ```swift
    /// let array = [1, 2, 3]
    /// print(array[safe: 5]) // nil instead of crash
    /// print(array[safe: 1]) // Optional(2)
    /// ```
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Collection Empty Check

extension Collection {
    /// Returns true if the collection is not empty
    var isNotEmpty: Bool {
        return !isEmpty
    }
}
