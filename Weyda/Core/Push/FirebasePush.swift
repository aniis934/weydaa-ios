// `@_implementationOnly` (et non `internal import`) : aucun type Firebase ne sort de ce fichier, et la cible de tests
// (`@testable import Weyda`) n'a pas à trouver les modules Objective-C des paquets Firebase, visibles de l'app seulement
// — un `internal import` d'un module non résilient reste « requis » pour un import testable (« missing required
// module »). Avertissement attendu : « using '@_implementationOnly' without enabling library evolution » (sans risque
// ici : aucun type Firebase dans une propriété stockée).
@preconcurrency @_implementationOnly import FirebaseCore
@preconcurrency @_implementationOnly import FirebaseCrashlytics
@preconcurrency @_implementationOnly import FirebaseMessaging
import Foundation
import os
import UIKit
import UserNotifications

/// Firebase dans l'app (push FCM + rapports de plantage) — équivalent de l'initialisation par `google-services.json`
/// d'Android. `GoogleService-Info.plist` n'est JAMAIS dans le dépôt (public) : `ios-release` l'écrit depuis le coffre
/// GitHub avant XcodeGen. Absent (CI, captures), en API simulée ou pendant les tests unitaires : Firebase ne démarre
/// pas et tout le push est inerte (`PushServices.unavailable`).
enum FirebasePush {
    /// `GoogleService-Info.plist` embarqué dans l'app.
    static var isBundled: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }

    /// Firebase doit-il démarrer ? Fichier présent, ni API simulée (captures reproductibles) ni tests unitaires.
    static var isEnabled: Bool {
        isBundled && !LaunchOptions.mockAPI && !LaunchOptions.isRunningUnitTests
    }

    /// Configure Firebase une seule fois — au lancement par l'`AppDelegate`, ou par le conteneur s'il est créé avant —
    /// et rend vrai si Firebase tourne. Crashlytics suit la politique d'Android : collecte en Release seulement
    /// (`crashlyticsEnabled` = false en debug).
    @discardableResult
    static func prepare() -> Bool {
        guard isEnabled else { return false }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            #if DEBUG
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
            #else
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
            #endif
        }
        return FirebaseApp.app() != nil
    }

    /// Jeton APNs de l'appareil remis à Firebase à la main (`FirebaseAppDelegateProxyEnabled` = NO : pas de swizzling).
    static func setAPNsToken(_ token: Data) {
        guard FirebaseApp.app() != nil else { return }
        Messaging.messaging().apnsToken = token
    }

    /// Services réels du registre ; `.unavailable` si Firebase ne tourne pas.
    static func liveServices() -> PushServices {
        guard prepare() else { return .unavailable }
        return PushServices(
            isAvailable: true,
            authorizationStatus: { await NotificationSystem.authorizationStatus() },
            requestAuthorization: { await NotificationSystem.requestAuthorization() },
            registerForRemoteNotifications: { UIApplication.shared.registerForRemoteNotifications() },
            hasAPNsToken: { Messaging.messaging().apnsToken != nil },
            currentToken: { await FirebaseTokens.current() },
            deleteToken: { await FirebaseTokens.delete() },
            setBadge: { count in NotificationSystem.setBadge(count) },
            tokenRefreshNotificationName: Notification.Name.MessagingRegistrationTokenRefreshed.rawValue
        )
    }
}

/// Jeton FCM (API Firebase « jeton », celle qu'attend le serveur : `device_tokens.token`). Hors du fil principal, et
/// l'objet `Messaging` (non `Sendable`) ne quitte jamais la fonction qui l'utilise.
nonisolated enum FirebaseTokens {
    private static let logger = Logger(subsystem: "com.weydaa.app", category: "push")

    /// Jeton courant (gardé en cache par Firebase) ; nil si Firebase ne peut pas le fournir (réseau, jeton APNs absent).
    @concurrent
    static func current() async -> String? {
        do {
            return try await Messaging.messaging().token()
        } catch {
            logger.notice("Jeton FCM indisponible : \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Destruction du jeton de l'appareil (Android : `FirebaseMessaging.deleteToken()`).
    @concurrent
    static func delete() async {
        do {
            try await Messaging.messaging().deleteToken()
        } catch {
            logger.notice("Jeton FCM non détruit : \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Centre de notifications d'iOS : autorisation et pastille de l'icône. Les objets UserNotifications restent dans la
/// fonction qui les crée ; seules des valeurs `Sendable` en sortent.
nonisolated enum NotificationSystem {
    @concurrent
    static func authorizationStatus() async -> PushAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return status(settings.authorizationStatus)
    }

    static func status(_ raw: UNAuthorizationStatus) -> PushAuthorizationStatus {
        switch raw {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    /// Alerte système (une seule fois dans la vie de l'app : iOS retient la réponse).
    @concurrent
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    /// Pastille de l'icône : `setBadgeCount` à partir d'iOS 17, propriété de l'application avant.
    @MainActor
    static func setBadge(_ count: Int) {
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count, withCompletionHandler: nil)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }
}
