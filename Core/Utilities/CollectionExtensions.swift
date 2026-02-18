//
//  CollectionExtensions.swift
//  WRKT
//
//  Useful extensions for Swift collections

import Foundation

// MARK: - Array Safe Subscript

extension Array {
    /// Safe array subscript that returns nil instead of crashing on out-of-bounds access

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
