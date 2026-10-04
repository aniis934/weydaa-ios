import Foundation
import XCTest

/// Manifeste de confidentialité (`Weyda/Resources/PrivacyInfo.xcprivacy`) : présent dans l'app (hôte des tests
/// unitaires, d'où `Bundle.main`), lisible, sans suivi, chaque catégorie d'API « à raison requise » avec au moins une
/// raison, et les deux catégories que le code de l'app utilise vraiment (relevé par grep, `docs/store/app-privacy.md`).
/// Un oubli ici ne casse rien au simulateur : Apple le refuse à l'envoi (ITMS-91053).
final class PrivacyManifestTests: XCTestCase {
    private func loadManifest() throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy absent de l'app (Weyda/Resources, ressource de la cible Weyda dans project.yml)"
        )
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: Any], "le manifeste doit être un dictionnaire")
    }

    private func accessedAPIs() throws -> [[String: Any]] {
        let raw: Any? = try loadManifest()["NSPrivacyAccessedAPITypes"]
        let entries = try XCTUnwrap(raw as? [[String: Any]], "NSPrivacyAccessedAPITypes absent ou mal formé")
        XCTAssertFalse(entries.isEmpty, "aucune API à raison requise déclarée")
        return entries
    }

    /// Raisons déclarées, par catégorie d'API.
    private func reasonsByCategory() throws -> [String: [String]] {
        var reasons: [String: [String]] = [:]
        for entry in try accessedAPIs() {
            let category = try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String, "catégorie d'API absente")
            let declared: [String] = (entry["NSPrivacyAccessedAPITypeReasons"] as? [String]) ?? []
            reasons[category, default: []].append(contentsOf: declared)
        }
        return reasons
    }

    func testManifestIsBundledAndDeclaresNoTracking() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false, "NSPrivacyTracking doit valoir false")
        let domains: [String] = (manifest["NSPrivacyTrackingDomains"] as? [String]) ?? []
        XCTAssertEqual(domains, [], "aucun domaine de suivi")
    }

    func testEveryAccessedAPICategoryHasAWellFormedReason() throws {
        for entry in try accessedAPIs() {
            let category = try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String, "catégorie d'API absente")
            XCTAssertTrue(category.hasPrefix("NSPrivacyAccessedAPICategory"), "catégorie inconnue : \(category)")
            let reasons = try XCTUnwrap(
                entry["NSPrivacyAccessedAPITypeReasons"] as? [String],
                "\(category) : NSPrivacyAccessedAPITypeReasons absent"
            )
            XCTAssertFalse(reasons.isEmpty, "\(category) : au moins une raison")
            for reason in reasons {
                let wellFormed = reason.range(of: #"^[0-9A-Z]{4}\.[0-9]$"#, options: .regularExpression) != nil
                XCTAssertTrue(wellFormed, "\(category) : raison mal formée « \(reason) »")
            }
        }
    }

    /// API utilisées par le code de l'app : UserDefaults (LaunchOptions, historique de recherche, push, trousseau) et
    /// dates de fichiers (cache disque des images, purge des photos de l'appareil photo dans tmp).
    func testDeclaresTheAPIsTheAppUses() throws {
        let reasons = try reasonsByCategory()
        let userDefaults: [String] = reasons["NSPrivacyAccessedAPICategoryUserDefaults"] ?? []
        XCTAssertTrue(userDefaults.contains("CA92.1"), "UserDefaults : raison CA92.1 attendue")
        let fileTimestamp: [String] = reasons["NSPrivacyAccessedAPICategoryFileTimestamp"] ?? []
        XCTAssertTrue(fileTimestamp.contains("C617.1"), "dates de fichiers : raison C617.1 attendue")
    }

    func testCollectedDataTypesAreWellFormedAndNeverUsedForTracking() throws {
        let raw: Any? = try loadManifest()["NSPrivacyCollectedDataTypes"]
        let entries = try XCTUnwrap(raw as? [[String: Any]], "NSPrivacyCollectedDataTypes absent ou mal formé")
        XCTAssertFalse(entries.isEmpty, "types collectés absents (voir docs/store/app-privacy.md)")
        var seen = Set<String>()
        for entry in entries {
            let dataType = try XCTUnwrap(entry["NSPrivacyCollectedDataType"] as? String, "type de données absent")
            XCTAssertTrue(dataType.hasPrefix("NSPrivacyCollectedDataType"), "type inconnu : \(dataType)")
            let isFirst = seen.insert(dataType).inserted
            XCTAssertTrue(isFirst, "\(dataType) déclaré deux fois")
            XCTAssertNotNil(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, "\(dataType) : « lié » absent")
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false, "\(dataType) : jamais de suivi")
            let purposes: [String] = (entry["NSPrivacyCollectedDataTypePurposes"] as? [String]) ?? []
            XCTAssertFalse(purposes.isEmpty, "\(dataType) : au moins une finalité")
            for purpose in purposes {
                XCTAssertTrue(purpose.hasPrefix("NSPrivacyCollectedDataTypePurpose"), "\(dataType) : finalité inconnue « \(purpose) »")
            }
        }
    }
}
