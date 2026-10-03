import SwiftUI

/// « Vérifiez votre email pour déposer des annonces et contacter les vendeurs. — Vérifier » — portage de
/// `VerifyEmailBanner.kt` : en tête du Profil et de l'assistant de dépôt (un compte non vérifié y remplissait tout
/// le formulaire pour échouer au premier envoi de photo). Toute la carte est touchable : elle ouvre la feuille de
/// connexion directement à l'étape du code.
///
///     VerifyEmailBanner()                              // router.requestEmailVerification()
///     VerifyEmailBanner(onVerifyEmail: { … })          // action fournie par l'écran
struct VerifyEmailBanner: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let onVerifyEmail: (() -> Void)?

    /// Ouvre la feuille à l'étape du code (`AppRouter.requestEmailVerification()`).
    init() {
        onVerifyEmail = nil
    }

    init(onVerifyEmail: @escaping () -> Void) {
        self.onVerifyEmail = onVerifyEmail
    }

    var body: some View {
        Button(action: verify) {
            content
                .padding(WeydaSpace.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    WeydaColor.tertiaryContainer,
                    in: RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
        }
        .buttonStyle(WeydaPressStyle())
        // VoiceOver : la phrase, sur un bouton (l'action va de soi) ; Contrôle vocal : « Vérifier ».
        .accessibilityLabel(L10n.profileVerifyBanner)
        .accessibilityInputLabels([L10n.profileVerifyAction, L10n.profileVerifyBanner])
        .accessibilityIdentifier("verifyEmailBanner")
    }

    /// Icône, phrase et action sur une ligne ; en très grand texte, l'action passe sous la phrase.
    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                HStack(alignment: .top, spacing: WeydaSpace.sm) {
                    icon
                    message
                }
                action
            }
        } else {
            HStack(spacing: WeydaSpace.sm) {
                icon
                message
                action
            }
        }
    }

    private var icon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.body)
            .foregroundStyle(WeydaColor.tertiary)
            .accessibilityHidden(true)
    }

    private var message: some View {
        Text(L10n.profileVerifyBanner)
            .weydaText(.bodyMedium)
            .foregroundStyle(WeydaColor.onTertiaryContainer)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var action: some View {
        Text(L10n.profileVerifyAction)
            .weydaText(.labelLarge)
            .foregroundStyle(WeydaColor.primary)
    }

    private func verify() {
        if let onVerifyEmail {
            onVerifyEmail()
        } else {
            router.requestEmailVerification()
        }
    }
}
