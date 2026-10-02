import Foundation
import os
import UIKit

/// Échec de chargement d'une image (le réseau, lui, lève ses `URLError` habituelles ; l'annulation,
/// `CancellationError`).
nonisolated enum ImageLoadingError: Error, Sendable, Equatable {
    /// Réponse HTTP hors 2xx (400 / 404 : objet absent du stockage, typiquement une ancienne miniature).
    case httpStatus(Int)
    /// Octets reçus mais illisibles comme image, ou fichier local illisible.
    case undecodable
}

/// Chargeur d'images de l'app — l'équivalent de l'ImageLoader de Coil (Android) :
/// - sa PROPRE session : jamais de jeton Bearer (Supabase Storage est public), cookies coupés, pas d'URLCache
///   (le cache disque est le nôtre). La session est injectée : l'API simulée sert aussi les images en Debug ;
/// - cache mémoire des images décodées (URL + taille cible), puis cache disque des octets (64 Mo) ;
/// - réduction à la taille d'affichage et décodage hors du fil principal (ImageIO) ;
/// - demandes identiques en vol fusionnées : un seul téléchargement, rendu à tous ceux qui l'attendent ;
/// - annulation : une tâche annulée cesse aussitôt d'attendre ; le téléchargement s'arrête quand plus personne
///   (ni vue, ni préchargement) n'en a besoin ;
/// - préchargement des images à venir (`prefetch`), annulable (`cancelPrefetch`).
nonisolated final class ImagePipeline: Sendable {
    /// Instance de l'app. Avec `-WeydaMockAPI YES` (Debug), les images passent aussi par l'API simulée :
    /// aucune requête réelle pendant les tests d'interface et le tour de captures.
    static let shared: ImagePipeline = {
        #if DEBUG
        let protocols: [AnyClass] = LaunchOptions.mockAPI ? [MockURLProtocol.self] : []
        #else
        let protocols: [AnyClass] = []
        #endif
        return ImagePipeline(session: ImagePipeline.makeSession(protocolClasses: protocols))
    }()

    // Types imbriqués : `nonisolated` explicite (l'isolation par défaut du module ne s'hérite pas de l'englobant).
    private nonisolated struct Entry: Sendable {
        let token: UInt64
        let task: Task<Void, Never>
        var waiters: [UInt64: CheckedContinuation<UIImage, any Error>]
        var prefetching: Bool
    }

    private nonisolated struct LoadState: Sendable {
        var nextID: UInt64 = 0
        /// Chargements en vol, par clé de requête.
        var entries: [String: Entry] = [:]
        /// Réponses « objet absent » déjà reçues (miniature d'une ancienne annonce) : échec immédiat, sans requête.
        var failedStatus: [URL: Int] = [:]
    }

    private let session: URLSession
    private let memory: ImageMemoryCache?
    private let disk: ImageDiskCache?
    private let lock = OSAllocatedUnfairLock(initialState: LoadState())

    /// `memory` / `disk` à nil : sans ce cache (tests).
    init(
        session: URLSession,
        memory: ImageMemoryCache? = ImageMemoryCache(),
        disk: ImageDiskCache? = ImageDiskCache.makeDefault()
    ) {
        self.session = session
        self.memory = memory
        self.disk = disk
    }

    /// Session dédiée aux images : ni cookies, ni cache HTTP, ni en-tête d'authentification.
    static func makeSession(protocolClasses: [AnyClass] = []) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.httpMaximumConnectionsPerHost = 6
        if !protocolClasses.isEmpty {
            configuration.protocolClasses = protocolClasses
        }
        return URLSession(configuration: configuration)
    }

    // MARK: - Lecture

    /// Image déjà en mémoire pour cette requête (synchrone, sans E/S) : affichage immédiat d'une image déjà vue.
    func cachedImage(for request: ImageRequest) -> UIImage? {
        memory?.image(forKey: request.cacheKey)
    }

    func image(for url: URL, targetSize: CGSize, scale: CGFloat) async throws -> UIImage {
        try await image(for: ImageRequest(url: url, targetSize: targetSize, scale: scale))
    }

    /// Mémoire → disque → réseau, réduite à la taille demandée. Lève `CancellationError` dès que la tâche
    /// appelante est annulée, `ImageLoadingError` ou une `URLError` sinon.
    func image(for request: ImageRequest) async throws -> UIImage {
        if let cached = cachedImage(for: request) { return cached }
        let key = request.cacheKey
        let waiterID = lock.withLockUnchecked { state -> UInt64 in
            state.nextID += 1
            return state.nextID
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, any Error>) in
                let registered = lock.withLockUnchecked { state -> Bool in
                    // Sous le verrou, que `onCancel` prend aussi : soit l'annulation est passée avant (la tâche
                    // est déjà marquée annulée), soit elle trouvera ce client inscrit.
                    if Task.isCancelled { return false }
                    if state.entries[key] != nil {
                        state.entries[key]?.waiters[waiterID] = continuation
                    } else {
                        let entry = startLoad(request, state: &state, priority: .userInitiated, waiter: (waiterID, continuation))
                        state.entries[key] = entry
                    }
                    return true
                }
                if !registered { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            self.leave(key: key, waiterID: waiterID)
        }
    }

    // MARK: - Préchargement

    /// Charge à l'avance (réseau, disque, décodage) les images qui vont apparaître ; ne bloque pas.
    func prefetch(urls: [URL], targetSize: CGSize, scale: CGFloat) {
        let requests = urls
            .map { ImageRequest(url: $0, targetSize: targetSize, scale: scale) }
            .filter { cachedImage(for: $0) == nil }
        guard !requests.isEmpty else { return }
        lock.withLockUnchecked { state in
            for request in requests {
                let key = request.cacheKey
                if state.entries[key] != nil {
                    state.entries[key]?.prefetching = true
                } else {
                    let entry = startLoad(request, state: &state, priority: .utility, waiter: nil)
                    state.entries[key] = entry
                }
            }
        }
    }

    /// Abandonne des préchargements (lignes sorties de l'écran) ; une image attendue par une vue continue.
    func cancelPrefetch(urls: [URL], targetSize: CGSize, scale: CGFloat) {
        let keys = urls.map { ImageRequest(url: $0, targetSize: targetSize, scale: scale).cacheKey }
        let abandoned = lock.withLockUnchecked { state -> [Task<Void, Never>] in
            var tasks: [Task<Void, Never>] = []
            for key in keys {
                guard var entry = state.entries[key], entry.prefetching else { continue }
                entry.prefetching = false
                if entry.waiters.isEmpty {
                    state.entries[key] = nil
                    tasks.append(entry.task)
                } else {
                    state.entries[key] = entry
                }
            }
            return tasks
        }
        abandoned.forEach { $0.cancel() }
    }

    /// Vide le cache mémoire (alerte mémoire du système) ; le disque reste.
    func removeAllFromMemory() {
        memory?.removeAll()
    }

    /// Chargements en vol (tests).
    var inFlightCount: Int {
        lock.withLockUnchecked { $0.entries.count }
    }

    // MARK: - Interne

    /// Crée l'entrée d'un chargement et lance sa tâche — appelé sous le verrou.
    private func startLoad(
        _ request: ImageRequest,
        state: inout LoadState,
        priority: TaskPriority,
        waiter: (id: UInt64, continuation: CheckedContinuation<UIImage, any Error>)?
    ) -> Entry {
        state.nextID += 1
        let token = state.nextID
        let task = Task.detached(priority: priority) { [self] in
            await self.run(request, token: token)
        }
        var waiters: [UInt64: CheckedContinuation<UIImage, any Error>] = [:]
        if let waiter { waiters[waiter.id] = waiter.continuation }
        return Entry(token: token, task: task, waiters: waiters, prefetching: waiter == nil)
    }

    /// Un client annulé cesse d'attendre ; s'il était le dernier (et sans préchargement), le chargement s'arrête.
    private func leave(key: String, waiterID: UInt64) {
        let (continuation, task) = lock.withLockUnchecked { state -> (CheckedContinuation<UIImage, any Error>?, Task<Void, Never>?) in
            guard var entry = state.entries[key] else { return (nil, nil) }
            guard let continuation = entry.waiters.removeValue(forKey: waiterID) else { return (nil, nil) }
            if entry.waiters.isEmpty, !entry.prefetching {
                state.entries[key] = nil
                return (continuation, entry.task)
            }
            state.entries[key] = entry
            return (continuation, nil)
        }
        task?.cancel()
        continuation?.resume(throwing: CancellationError())
    }

    /// Tâche d'un chargement : rend le résultat à tous ceux qui l'attendent encore. Le jeton évite de vider
    /// l'entrée d'un chargement plus récent pour la même clé (après une annulation complète).
    @concurrent
    private func run(_ request: ImageRequest, token: UInt64) async {
        let result: Result<UIImage, any Error>
        do {
            let image = try await fetch(request)
            result = .success(image)
        } catch {
            result = .failure(error)
        }
        let key = request.cacheKey
        let waiters = lock.withLockUnchecked { state -> [CheckedContinuation<UIImage, any Error>] in
            guard let entry = state.entries[key], entry.token == token else { return [] }
            state.entries[key] = nil
            return Array(entry.waiters.values)
        }
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }

    @concurrent
    private func fetch(_ request: ImageRequest) async throws -> UIImage {
        if let cached = cachedImage(for: request) { return cached }
        let url = request.url
        if let status = lock.withLockUnchecked({ $0.failedStatus[url] }) {
            throw ImageLoadingError.httpStatus(status)
        }
        if let data = disk?.data(for: url), let image = ImageDecoder.decode(data, for: request) {
            memory?.insert(image, forKey: request.cacheKey)
            return image
        }
        try Task.checkCancellation()
        let data = try await download(url)
        guard let image = ImageDecoder.decode(data, for: request) else { throw ImageLoadingError.undecodable }
        if !url.isFileURL { disk?.store(data, for: url) }
        memory?.insert(image, forKey: request.cacheKey)
        return image
    }

    private func download(_ url: URL) async throws -> Data {
        if url.isFileURL {
            // Photo locale (aperçu d'un dépôt d'annonce) : lue directement, jamais copiée dans le cache disque.
            guard let data = try? Data(contentsOf: url) else { throw ImageLoadingError.undecodable }
            return data
        }
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return data }
        let status = http.statusCode
        if [400, 403, 404, 410].contains(status) {
            lock.withLockUnchecked { state in
                if state.failedStatus.count >= 500 { state.failedStatus.removeAll() }
                state.failedStatus[url] = status
            }
        }
        throw ImageLoadingError.httpStatus(status)
    }
}
