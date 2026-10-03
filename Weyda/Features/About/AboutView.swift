import SwiftUI

/// « À propos et informations légales » — portage de `settings/AboutScreen.kt`. Accessible depuis le Profil,
/// connecté ou non : l'App Store, comme Google Play, veut la politique de confidentialité et les conditions
/// consultables DANS l'app. Les pages viennent du site (un seul texte à tenir à jour), en feuille Safari.
struct AboutView: View {
    @EnvironmentObject private var router: AppRouter

    init() {}

    var body: some View {
        AboutScreen(
            version: AppVersion.display,
            onContact: { router.push(.contact) },
            onOpenPage: { page in router.push(.webPage(page)) }
        )
    }
}

/// Écran sans état : en-tête (tuile, nom, version), contact, puis les cinq pages légales.
struct AboutScreen: View {
    private let version: String
    private let onContact: () -> Void
    private let onOpenPage: (WebPage) -> Void

    init(version: String, onContact: @escaping () -> Void, onOpenPage: @escaping (WebPage) -> Void) {
        self.version = version
        self.onContact = onContact
        self.onOpenPage = onOpenPage
    }

    var body: some View {
        List {
            Section {
                AboutHeader(version: version)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            Section {
                AboutRow(title: L10n.legalContact, systemImage: "envelope", trailingSymbol: "chevron.forward", hint: nil, action: onContact)
            }
            Section {
                ForEach(WebPage.allCases) { page in
                    AboutRow(
                        title: page.title,
                        systemImage: page.symbol,
                        trailingSymbol: "arrow.up.forward",
                        hint: L10n.legalOpensBrowser,
                        action: { onOpenPage(page) }
                    )
                }
            } footer: {
                // Une seule mention pour les cinq pages (Android la répétait sous chaque ligne).
                Text(L10n.legalOpensBrowser)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(WeydaColor.background)
        .navigationTitle(L10n.legalTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.about")
    }
}

/// La tuile de l'icône, le nom et la version : l'utilisateur sait quelle version il a sous les yeux (support).
private struct AboutHeader: View {
    let version: String

    private static let tileSide: CGFloat = 72

    var body: some View {
        VStack(spacing: WeydaSpace.sm) {
            WeydaTile(size: Self.tileSide)
            WeydaWordmark(color: WeydaColor.onBackground, style: .headlineSmall)
            // Lu de gauche à droite même en arabe (« 1.0.0 (12) », pas « (12) 1.0.0 »).
            Text(L10n.legalVersion(Format.ltrIsolate(version)))
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
        }
        .padding(.vertical, WeydaSpace.sm)
        .accessibilityElement(children: .combine)
    }
}

/// Ligne de menu : pictogramme de marque, libellé, puis chevron (écran poussé) ou flèche sortante (page web).
private struct AboutRow: View {
    let title: String
    let systemImage: String
    let trailingSymbol: String
    let hint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WeydaSpace.md) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(WeydaColor.primary)
                    .frame(width: WeydaSize.iconLarge)
                    .accessibilityHidden(true)
                Text(title)
                    .weydaText(.bodyLarge)
                    .foregroundStyle(WeydaColor.onSurface)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: trailingSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WeydaColor.outline)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: WeydaSize.touchTarget)
            .contentShape(Rectangle())
        }
        .accessibilityHint(hint ?? "")
        .listRowBackground(WeydaColor.surface)
    }
}

/// Version affichée : « 1.0.0 (12) » (version + numéro de build, comme les Réglages d'iOS).
nonisolated enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        guard let build = info["CFBundleVersion"] as? String, !build.isEmpty, build != version else {
            return version
        }
        return "\(version) (\(build))"
    }
}
