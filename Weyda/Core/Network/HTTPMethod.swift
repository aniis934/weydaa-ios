import Foundation

/// Méthodes HTTP utilisées par l'API Weyda (`docs/API-CONTRACT.md`, dépôt privé).
nonisolated enum HTTPMethod: String, CaseIterable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}
