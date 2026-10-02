import SwiftUI

/// Onglet Profil d'un visiteur (avant la phase 3) — portage de `GuestProfile` (ProfileScreen.kt) : l'invitation à
/// se connecter, puis « À propos et informations légales », consultables sans compte. `router.requestLogin()`
/// mène ici. Le bouton de connexion ouvrira la feuille de connexion en phase 3.
struct GuestProfileView: View {
    @EnvironmentObject private var router: AppRouter

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            LoginRequired(
                title: L10n.loginRequiredTitle,
                message: L10n.loginRequiredBody,
                onLogin: { router.requestLogin() }
            )
            AccountLinks()
                .padding(.horizontal, WeydaSpace.screen)
                .padding(.bottom, WeydaSpace.lg)
        }
        .background(WeydaColor.background)
        .navigationTitle(AppTab.account.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(AppTab.account.rawValue)")
    }
}

/// Liens du Profil visiteur : À propos (et, en Debug, la démonstration du design).
private struct AccountLinks: View {
    var body: some View {
        VStack(spacing: WeydaSpace.md) {
            NavigationLink(value: AppRoute.about) {
                AccountLinkRow(title: L10n.legalTitle, systemImage: "info.circle")
            }
            .buttonStyle(.weydaCard)
            .accessibilityIdentifier("open.about")
            #if DEBUG
            NavigationLink {
                DesignShowcaseView()
            } label: {
                Text(verbatim: "Design system")
                    .weydaText(.labelLarge)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("open.showcase")
            #endif
        }
        .frame(maxWidth: WeydaSize.formMaxWidth)
    }
}

/// Une ligne de menu dans une carte : pictogramme, libellé, chevron (retourné en arabe).
private struct AccountLinkRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: WeydaSpace.md) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(WeydaColor.primary)
                .accessibilityHidden(true)
            Text(title)
                .weydaText(.bodyLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WeydaColor.outline)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, WeydaSpace.lg)
        .frame(minHeight: WeydaSize.touchTarget + WeydaSpace.md)
        .background(WeydaColor.surface, in: RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
                .strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
    }
}
