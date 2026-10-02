import Foundation

/// Configuration lue dans l'Info.plist, elle-même alimentée par Config/*.xcconfig (et, en CI, par
/// le coffre GitHub via Config/Secrets.xcconfig — jamais commité). Valeur vide = fonction coupée
/// (ex. : sans clé Supabase, le temps réel est désactivé, l'app reste fonctionnelle en HTTP seul).
nonisolated struct AppConfig: Sendable {
    let apiBaseURL: URL
    let supabaseURL: URL?
    let supabaseAnonKey: String?

    static let current = AppConfig(info: Bundle.main.infoDictionary ?? [:])

    private static let defaultAPIBaseURL = URL(string: "https://weydaa.com/")!

    init(apiBaseURL: URL, supabaseURL: URL?, supabaseAnonKey: String?) {
        self.apiBaseURL = apiBaseURL
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
    }

    init(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let raw = info[key] as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let apiHost = value("WeydaAPIHost")
        let supabaseHost = value("WeydaSupabaseHost")
        self.init(
            apiBaseURL: apiHost.flatMap { URL(string: "https://\($0)/") } ?? Self.defaultAPIBaseURL,
            supabaseURL: supabaseHost.flatMap { URL(string: "https://\($0)") },
            supabaseAnonKey: value("WeydaSupabaseAnonKey")
        )
    }
}
