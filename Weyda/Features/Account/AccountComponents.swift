import SwiftUI
import UIKit

// Briques propres aux écrans du compte (Profil, Mes annonces, Mes données, Nous contacter). Les champs, le bandeau
// d'erreur et le bouton principal des formulaires sont ceux de la connexion (`Weyda/Features/Auth/AuthComponents.swift`,
// comme sur Android) ; les noms d'ici sont préfixés « Account » pour ne jamais en croiser un autre dans le module.

// MARK: - Garde des écrans de membre

/// Écran réservé aux membres (Mes annonces, Modifier le profil, Mot de passe, Mes données) — la garde d'Android
/// (`isMemberOnlyRoute`, WeydaRoot.kt), portée à la manière d'iOS :
///  · un visiteur (lien profond, session fermée depuis un autre onglet) voit l'invitation à se connecter ;
///  · si la session se ferme pendant que l'écran est affiché (déconnexion, mot de passe changé, compte supprimé,
///    jetons révoqués), l'écran se retire de la pile en gardant son contenu le temps de l'animation : il ne reste
///    jamais là avec les données de l'ancien compte, toutes ses requêtes en 401.
/// Le contenu est recréé pour un autre compte (`id`) : rien ne passe d'un utilisateur au suivant.
struct AccountMemberGate<Content: View>: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    /// Dernier membre vu : le contenu reste affiché pendant le retrait de l'écran.
    @State private var lastUser: User? = nil
    private let title: String
    private let content: (User) -> Content

    init(title: String, @ViewBuilder content: @escaping (User) -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Group {
            if let user = session.user ?? lastUser {
                content(user)
                    .id(user.id)
            } else {
                LoginRequired(
                    title: L10n.loginRequiredTitle,
                    message: L10n.loginRequiredBody,
                    onLogin: { router.requestLogin() }
                )
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("screen.loginRequired")
            }
        }
        .onAppear {
            if let user = session.user {
                lastUser = user
            }
        }
        .onChange(of: session.user) { user in
            if let user {
                lastUser = user
            } else if lastUser != nil {
                dismiss()
            }
        }
    }
}

// MARK: - Lignes de menu

/// Ligne d'une liste groupée (Profil) : pictogramme de la marque, libellé, valeur facultative au bout (la langue
/// courante, comme les Réglages d'iOS). Le chevron est celui de `NavigationLink` ; `destructive` = déconnexion.
struct AccountMenuRow: View {
    private let title: String
    private let systemImage: String
    private let value: String?
    private let destructive: Bool

    init(title: String, systemImage: String, value: String? = nil, destructive: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.destructive = destructive
    }

    var body: some View {
        HStack(spacing: WeydaSpace.md) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: WeydaSize.iconLarge)
                .accessibilityHidden(true)
            Text(title)
                .weydaText(.bodyLarge)
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: WeydaSize.touchTarget)
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        destructive ? WeydaColor.secondary : WeydaColor.primary
    }

    private var titleColor: Color {
        destructive ? WeydaColor.secondary : WeydaColor.onSurface
    }
}

// MARK: - Texte long

/// Champ de texte sur plusieurs lignes (bio, message de contact) — même gabarit que `AuthTextField` (libellé
/// au-dessus, cadre vert au focus et rouge en erreur, erreur ou aide dessous), qui n'existe qu'en une ligne ;
/// compteur facultatif au bout de la ligne d'aide (« 57 / 500 »).
struct AccountTextArea<Field: Hashable>: View {
    private let label: String
    @Binding private var text: String
    private let focus: FocusState<Field?>.Binding
    private let field: Field
    private let error: String?
    private let supporting: String?
    private let counter: String?
    private let minLines: Int
    private let isEnabled: Bool

    init(
        _ label: String,
        text: Binding<String>,
        focus: FocusState<Field?>.Binding,
        field: Field,
        error: String? = nil,
        supporting: String? = nil,
        counter: String? = nil,
        minLines: Int = 3,
        isEnabled: Bool = true
    ) {
        self.label = label
        _text = text
        self.focus = focus
        self.field = field
        self.error = error
        self.supporting = supporting
        self.counter = counter
        self.minLines = minLines
        self.isEnabled = isEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            Text(label)
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .accessibilityHidden(true)
            input
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, WeydaSpace.md)
    }

    private var input: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.field, style: .continuous)
        return TextField("", text: $text, axis: .vertical)
            .lineLimit(minLines...(minLines + AccountTextAreaMetrics.extraLines))
            .textInputAutocapitalization(.sentences)
            .weydaText(.bodyLarge)
            .foregroundStyle(WeydaColor.onSurface)
            .focused(focus, equals: field)
            .disabled(!isEnabled)
            .padding(WeydaSpace.md)
            .background(WeydaColor.surface, in: shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private var footer: some View {
        let message: String? = error ?? supporting
        if message != nil || counter != nil {
            HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.sm) {
                Text(message ?? "")
                    .weydaText(.bodySmall)
                    .foregroundStyle(error == nil ? WeydaColor.onSurfaceVariant : WeydaColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let counter {
                    Text(Format.ltrIsolate(counter))
                        .weydaText(.labelSmall)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var isFocused: Bool {
        focus.wrappedValue == field
    }

    private var borderColor: Color {
        if error != nil { return WeydaColor.error }
        return isFocused ? WeydaColor.primary : WeydaPalette.cardOutline
    }

    private var borderWidth: CGFloat {
        error != nil || isFocused ? 1.5 : 1
    }
}

nonisolated enum AccountTextAreaMetrics {
    /// Lignes visibles en plus du minimum avant que le champ défile (bio : 3 à 6, message : 5 à 8).
    static let extraLines = 3
}

// MARK: - Boutons et cartes

/// Bouton pleine largeur ROUGE d'une action définitive (suppression du compte) — le pendant destructif de
/// `SubmitButton` (Android : `Button` aux couleurs `error`). Le W s'écrit pendant l'appel ; un nouvel appui est ignoré.
struct AccountDestructiveButton: View {
    private let title: String
    private let isEnabled: Bool
    private let isLoading: Bool
    private let action: () -> Void

    private static let loaderSide: CGFloat = 22

    init(_ title: String, isEnabled: Bool = true, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: submit) {
            ZStack {
                Text(title)
                    .weydaText(.titleSmall)
                    .foregroundStyle(labelColor)
                    .multilineTextAlignment(.center)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    WeydaLoader(color: WeydaColor.onError)
                        .frame(width: Self.loaderSide, height: Self.loaderSide)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WeydaColor.error)
        .disabled(!isEnabled && !isLoading)
        .accessibilityLabel(isLoading ? L10n.loading : title)
    }

    private var labelColor: Color {
        isEnabled ? WeydaColor.onError : WeydaColor.onSurfaceVariant
    }

    private func submit() {
        guard !isLoading else { return }
        action()
    }
}

/// Carte de section d'un écran défilant (Mes données) : surface, filet fin, titre puis contenu.
struct AccountCard<Content: View>: View {
    private let title: String
    private let titleColor: Color
    private let content: Content

    init(title: String, titleColor: Color = WeydaColor.onSurface, @ViewBuilder content: () -> Content) {
        self.title = title
        self.titleColor = titleColor
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: WeydaSpace.sm) {
            Text(title)
                .weydaText(.titleMedium)
                .foregroundStyle(titleColor)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(WeydaSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeydaColor.surface, in: shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
    }
}

// MARK: - Message transitoire

extension View {
    /// Message transitoire en bas de l'écran (Android : snackbar) : lu par VoiceOver, effacé au bout de 4 s par
    /// `onShown` (le ViewModel remet son `notice` à nil).
    func accountNotice(_ notice: String?, onShown: @escaping () -> Void) -> some View {
        modifier(AccountNoticeModifier(notice: notice, onShown: onShown))
    }
}

private struct AccountNoticeModifier: ViewModifier {
    private let notice: String?
    private let onShown: () -> Void
    /// Message dont le temps d'affichage est écoulé (déclenche `onShown`).
    @State private var elapsed: String? = nil

    init(notice: String?, onShown: @escaping () -> Void) {
        self.notice = notice
        self.onShown = onShown
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let notice {
                    AccountNoticeToast(text: notice)
                        .padding(.horizontal, WeydaSpace.screen)
                        .padding(.bottom, WeydaSpace.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .weydaAnimation(.easeOut(duration: WeydaDuration.medium), value: notice)
            .task(id: notice) {
                elapsed = nil
                guard let notice else { return }
                UIAccessibility.post(notification: .announcement, argument: notice)
                do {
                    try await Task.sleep(nanoseconds: AccountNoticeTiming.visibleNanoseconds)
                } catch {
                    return
                }
                elapsed = notice
            }
            .onChange(of: elapsed) { value in
                if value != nil {
                    onShown()
                }
            }
    }
}

nonisolated enum AccountNoticeTiming {
    /// 4 s, la durée d'une snackbar courte d'Android.
    static let visibleNanoseconds: UInt64 = 4_000_000_000
}

/// La pastille du message : couleurs inversées (sombre sur fond clair, claire sur fond sombre), comme une snackbar.
private struct AccountNoticeToast: View {
    let text: String

    var body: some View {
        Text(text)
            .weydaText(.bodyMedium)
            .foregroundStyle(WeydaColor.background)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, WeydaSpace.lg)
            .padding(.vertical, WeydaSpace.md)
            .frame(maxWidth: WeydaSize.formMaxWidth, alignment: .leading)
            .background(WeydaColor.onBackground, in: RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("account.notice")
    }
}

// MARK: - Langue et chaînes en attente

/// Langue de l'interface, telle que l'affichent les Réglages (le nom de la langue dans sa propre écriture).
nonisolated enum AccountLanguage {
    static var currentName: String {
        switch WeydaLocale.language {
        case "ar": L10n.languageAr
        case "en": L10n.languageEn
        default: L10n.languageFr
        }
    }
}

/// Textes du compte qui attendent leur clé au catalogue (demandées dans la note de l'agent ACCOUNT) : chaque
/// propriété renvoie aujourd'hui la clé existante la plus proche, à remplacer par l'accès typé une fois la clé
/// ajoutée (une ligne chacune).
nonisolated enum AccountStrings {
    /// `stat_expired` « Expirées » (statistiques du profil) — d'ici là : « Expirée » (statut d'une annonce).
    static var statExpired: String { L10n.statusExpired }

    /// `account_delete_apple_hint` — d'ici là : aucune explication (seuls les comptes Apple la verront, lot A).
    static var appleDeleteHint: String? { nil }

    /// `account_delete_apple_confirm` « Confirmer avec Apple et supprimer » — d'ici là : « Supprimer définitivement ».
    static var appleDeleteConfirm: String { L10n.deleteAccountAction }

    /// `retry_in_hours` « Réessayez dans %1$d h. » (export refusé : 2 par 24 h) — d'ici là : rien, le message seul.
    static func retryInHours(_ hours: Int) -> String? { nil }
}
