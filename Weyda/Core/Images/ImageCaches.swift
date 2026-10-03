import CryptoKit
import Foundation
import os
import UIKit

/// Cache mémoire des images DÉCODÉES et réduites, par URL + taille cible (l'équivalent du MemoryCache de Coil).
/// Coût = octets du bitmap ; le système vide aussi `NSCache` de lui-même quand la mémoire manque.
///
/// `@unchecked Sendable` : `NSCache` est sûr entre fils (documenté) ; l'enveloppe ne fait que le transporter.
nonisolated final class ImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()

    init(costLimit: Int = ImageMemoryCache.defaultCostLimit, countLimit: Int = 300) {
        cache.totalCostLimit = costLimit
        cache.countLimit = countLimit
    }

    /// 1/16 de la mémoire de l'appareil, entre 32 et 128 Mo (≈ 260 vignettes de liste décodées au plafond).
    static var defaultCostLimit: Int {
        let share = min(ProcessInfo.processInfo.physicalMemory / 16, 128 * 1024 * 1024)
        return max(Int(share), 32 * 1024 * 1024)
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    static func cost(of image: UIImage) -> Int {
        guard let bitmap = image.cgImage else { return 1 }
        return bitmap.bytesPerRow * bitmap.height
    }
}

/// Cache disque des octets TÉLÉCHARGÉS (WebP du stockage), par URL — l'équivalent du DiskCache de Coil
/// (64 Mo, comme Android). Fichiers dans Caches/ (jamais sauvegardés, purgeables par le système) ; au-delà de
/// la limite, les moins récemment lus partent d'abord (date de modification rafraîchie à chaque lecture).
/// Les images du stockage sont immuables (nom = UUID) : aucune revalidation HTTP n'est nécessaire.
nonisolated final class ImageDiskCache: Sendable {
    let directory: URL
    let sizeLimit: Int

    // Type imbriqué : `nonisolated` explicite (l'isolation par défaut du module ne s'hérite pas de l'englobant).
    private nonisolated struct TrimState: Sendable {
        var bytesSinceTrim: Int
        var trimming = false
    }

    private let trimState: OSAllocatedUnfairLock<TrimState>

    init(directory: URL, sizeLimit: Int = 64 * 1024 * 1024) {
        self.directory = directory
        self.sizeLimit = sizeLimit
        // Élagage dès le premier enregistrement du lancement : le cache a pu grossir la fois précédente.
        self.trimState = OSAllocatedUnfairLock(initialState: TrimState(bytesSinceTrim: sizeLimit))
    }

    /// Caches/WeydaImages.
    static func makeDefault() -> ImageDiskCache? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return ImageDiskCache(directory: caches.appendingPathComponent("WeydaImages", isDirectory: true))
    }

    func data(for url: URL) -> Data? {
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return data
    }

    func store(_ data: Data, for url: URL) {
        let file = fileURL(for: url)
        if (try? data.write(to: file, options: .atomic)) == nil {
            // Premier enregistrement, ou dossier purgé par le système entre-temps : on le (re)crée une fois.
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        }
        let limit = sizeLimit
        let size = data.count
        let shouldTrim = trimState.withLockUnchecked { state -> Bool in
            state.bytesSinceTrim += size
            guard state.bytesSinceTrim >= limit / 10, !state.trimming else { return false }
            state.bytesSinceTrim = 0
            state.trimming = true
            return true
        }
        guard shouldTrim else { return }
        trim()
        trimState.withLockUnchecked { $0.trimming = false }
    }

    func remove(for url: URL) {
        try? FileManager.default.removeItem(at: fileURL(for: url))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Supprime les fichiers les moins récemment lus jusqu'à 80 % de la limite.
    func trim() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else {
            return
        }
        var entries: [(file: URL, date: Date, size: Int)] = []
        var total = 0
        for file in files {
            guard let values = try? file.resourceValues(forKeys: keys) else { continue }
            let size = values.fileSize ?? 0
            entries.append((file, values.contentModificationDate ?? .distantPast, size))
            total += size
        }
        guard total > sizeLimit else { return }
        let target = sizeLimit * 8 / 10
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if total <= target { break }
            if (try? FileManager.default.removeItem(at: entry.file)) != nil { total -= entry.size }
        }
    }

    /// Nom de fichier = SHA-256 de l'URL (aucune URL en clair sur le disque, aucun caractère interdit).
    func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name, isDirectory: false)
    }
}
