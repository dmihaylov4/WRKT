//
//  FavoritesStore.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 15.10.25.
//


import Foundation
import Combine

@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var ids: Set<String> = []

    private let key = "favorites.exerciseIDs"

    init() {
        if let arr = UserDefaults.standard.array(forKey: key) as? [String] {
            ids = Set(arr)
        }
    }

    private func persist() {
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        persist()
    }

    func add(_ id: String) {
        guard !ids.contains(id) else { return }
        ids.insert(id); persist()
    }

    func remove(_ id: String) {
        guard ids.contains(id) else { return }
        ids.remove(id); persist()
    }

    func clearAll() {
        ids.removeAll()
        persist()
    }
}
