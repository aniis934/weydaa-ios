import Foundation

/// Listes paginées — portage de `ui/common/Paging.kt` (Android).
nonisolated enum Paging {
    /// Rechargement silencieux d'une liste paginée (retour sur l'écran, tirer pour rafraîchir) : la première
    /// page fraîche REMPLACE le début de la liste et les pages suivantes déjà chargées sont gardées, sans
    /// doublon. Remplacer toute la liste par la seule page 1 ramenait l'utilisateur de la 40e ligne à la 24e,
    /// position perdue. Compromis assumé : une ligne poussée hors de la page 1 par des nouveautés ne revient
    /// qu'au prochain rechargement complet.
    static func mergeFirstPage<Element, ID: Hashable>(
        current: [Element],
        fresh: [Element],
        id: (Element) -> ID
    ) -> [Element] {
        if current.count <= fresh.count { return fresh }
        let freshIDs = Set(fresh.map(id))
        return fresh + current.dropFirst(fresh.count).filter { !freshIDs.contains(id($0)) }
    }
}
