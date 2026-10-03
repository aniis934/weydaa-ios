import Foundation

/// Tri stable par clé entière : `sortedBy` (Kotlin) est stable, `sorted(by:)` (Swift) ne le garantit pas. Sert aux
/// images (`order`), aux catégories et sous-catégories (`displayOrder`) : à clé égale, l'ordre du serveur est gardé.
nonisolated enum StableOrder {
    static func sorted<T>(_ items: [T], by key: (T) -> Int) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                let left = key(lhs.element)
                let right = key(rhs.element)
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map { $0.element }
    }
}
