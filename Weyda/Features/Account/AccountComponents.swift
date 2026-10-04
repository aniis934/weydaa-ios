import SwiftUI
import UIKit

// Briques propres aux écrans du compte (Profil, Mes annonces, Mes données, Nous contacter). Les champs, le bandeau
// d'erreur et le bouton principal des formulaires sont ceux de la connexion (`Weyda/Features/Auth/AuthComponents.swift`,
// comme sur Android) ; le message bref en bas d'écran est la bannière commune (`weydaBanner`, Banner.swift).
// Les noms d'ici sont préfixés « Account » pour ne jamais en croiser un autre dans le module.

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
                .navigationBarTitleDisplayMode(.large)
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

// MARK: - Bannières

/// Bannières des écrans du compte et du dépôt (`weydaBanner`) : succès (pictogramme coché ; elle vibre d'elle-même) ou
/// échec (pictogramme d'alerte, vibration d'erreur). Créées UNE fois, dans le ViewModel.
nonisolated enum AccountBanner {
    static func success(_ message: String) -> WeydaBanner {
        WeydaBanner(message, symbol: "checkmark.circle.fill", kind: .success)
    }

    static func failure(_ message: String) -> WeydaBanner {
        WeydaBanner(message, symbol: "exclamationmark.circle.fill", kind: .error)
    }
}

// MARK: - Lignes de menu

/// Ligne d'une liste groupée (Profil) : pictogramme de la marque, libellé, valeur facultative au bout (la langue
/// courante, comme les Réglages d'iOS), puis un pictogramme de fin facultatif (sortie vers les Réglages). Le chevron
/// des liens est celui de `NavigationLink` ; `destructive` = déconnexion. Très grand texte : la valeur passe SOUS le
/// libellé (à côté, « Langue » se coupait en « Langu / e » et « Français » en « Franç… »).
struct AccountMenuRow: View {
    private let title: String
    private let systemImage: String
    private let value: String?
    private let trailingSymbol: String?
    private let destructive: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, systemImage: String, value: String? = nil, trailingSymbol: String? = nil, destructive: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.trailingSymbol = trailingSymbol
        self.destructive = destructive
    }

    var body: some View {
        HStack(spacing: WeydaSpace.md) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: WeydaSize.iconLarge)
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                stackedTexts
            } else {
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
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: WeydaSize.touchTarget)
        .contentShape(Rectangle())
    }

    /// Très grand texte : libellé puis valeur, l'un sous l'autre, sur toute la largeur.
    private var stackedTexts: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
            Text(title)
                .weydaText(.bodyLarge)
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let value {
                Text(value)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconColor: Color {
        destructive ? WeydaColor.secondary : WeydaColor.primary
    }

    private var titleColor: Color {
        destructive ? WeydaColor.secondary : WeydaColor.onSurface
    }
}

// MARK: - Langue

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

/// Section « Langue » du Profil (membre et visiteur) — l'écran `LanguageScreen` d'Android, à la manière d'iOS : pas
/// de sélecteur maison, la langue de l'app se règle dans les Réglages de l'iPhone (Réglages › Weydaa › Langue). La
/// ligne y mène directement ; la note dessous dit quoi y faire, et quoi faire si le choix n'y figure pas (iOS ne le
/// propose que si l'iPhone a plusieurs langues préférées).
struct AccountLanguageSection: View {
    @Environment(\.openURL) private var openURL

    init() {}

    var body: some View {
        Section {
            Button(action: openSettings) {
                AccountMenuRow(
                    title: L10n.profileLanguage,
                    systemImage: "globe",
                    value: AccountLanguage.currentName,
                    trailingSymbol: "arrow.up.forward.app"
                )
            }
            .listRowBackground(WeydaColor.surface)
            .accessibilityHint(L10n.languageOpenSettings)
            .accessibilityIdentifier("profile.language")
        } footer: {
            VStack(alignment: .leading, spacing: WeydaSpace.xs) {
                Text(L10n.languageHint)
                Text(L10n.languageLegacyHint)
            }
            .weydaText(.bodySmall)
            .foregroundStyle(WeydaColor.onSurfaceVariant)
        }
    }

    /// La page de Weydaa dans les Réglages (langue de l'app, notifications…).
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
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
        let maxLines: Int = minLines + AccountTextAreaMetrics.extraLines
        return TextField("", text: $text, axis: .vertical)
            .lineLimit(minLines...maxLines)
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
                    .foregroundStyle(messageColor)
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

    private var messageColor: Color {
        error == nil ? WeydaColor.onSurfaceVariant : WeydaColor.error
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

/// Côté du W qui s'écrit dans un bouton pendant l'appel (comme `SubmitButton`).
nonisolated enum AccountButtonMetrics {
    static let loaderSide: CGFloat = 22
}

/// Bouton pleine largeur ROUGE d'une action définitive (suppression du compte) — le pendant destructif de
/// `SubmitButton` (Android : `Button` aux couleurs `error`). Le W s'écrit pendant l'appel ; un nouvel appui est ignoré.
struct AccountDestructiveButton: View {
    private let title: String
    private let isEnabled: Bool
    private let isLoading: Bool
    private let action: () -> Void

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
                        .frame(width: AccountButtonMetrics.loaderSide, height: AccountButtonMetrics.loaderSide)
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

/// Bouton pleine largeur secondaire (contour vert : « Préparer le fichier ») — Android : `OutlinedButton`. Le W
/// s'écrit pendant l'appel ; un nouvel appui est ignoré.
struct AccountSecondaryButton: View {
    private let title: String
    private let isLoading: Bool
    private let action: () -> Void

    init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: submit) {
            ZStack {
                Text(title)
                    .weydaText(.titleSmall)
                    .foregroundStyle(WeydaColor.primary)
                    .multilineTextAlignment(.center)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    WeydaLoader(color: WeydaColor.primary)
                        .frame(width: AccountButtonMetrics.loaderSide, height: AccountButtonMetrics.loaderSide)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WeydaColor.primary)
        .accessibilityLabel(isLoading ? L10n.loading : title)
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
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
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

// MARK: - Feuille de partage

/// Feuille de partage du SYSTÈME, ouverte d'elle-même dès que l'export est prêt (Android : `ACTION_SEND` + sélecteur)
/// — présentée par UIKit au-dessus de l'écran courant : c'est la vraie feuille d'iOS (AirDrop, Fichiers, Mail…), pas
/// une copie glissée dans une feuille SwiftUI. L'écran garde ensuite un `ShareLink` pour repartager le même fichier
/// sans refaire d'export (2 par 24 h).
enum AccountShareSheet {
    static func present(_ url: URL) {
        guard let presenter = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad (app iPhone agrandie) : une feuille de partage doit être ancrée quelque part.
        controller.popoverPresentationController?.sourceView = presenter.view
        presenter.present(controller, animated: true)
    }

    /// Le contrôleur affiché tout en haut de la fenêtre active (une feuille SwiftUI ouverte compte).
    private static func topViewController() -> UIViewController? {
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { scene in
            scene as? UIWindowScene
        }
        let windows: [UIWindow] = scenes.flatMap { scene in scene.windows }
        let window: UIWindow? = windows.first { candidate in candidate.isKeyWindow } ?? windows.first
        var top: UIViewController? = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
