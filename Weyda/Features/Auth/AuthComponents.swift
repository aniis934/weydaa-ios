import AuthenticationServices
import SwiftUI
import UIKit

// Composants des formulaires de compte — portage d'`ui/auth/AuthComponents.kt` (Android). Comme sur Android, ils
// servent aussi aux écrans du compte (modifier le profil, mot de passe, mes données, nous contacter).
// Champs : libellé AU-DESSUS (toujours visible, lu par VoiceOver comme nom du champ), erreur ou aide DESSOUS.
// Focus enchaîné : chaque champ reçoit la liaison `@FocusState` de l'écran et sa valeur (`field:`).

/// Nature d'un champ : clavier, remplissage automatique (trousseau, code reçu), sens d'écriture.
nonisolated enum AuthFieldKind: Sendable {
    /// Texte libre (sujet, message…).
    case text
    /// Nom complet.
    case name
    /// E-mail servant d'IDENTIFIANT de connexion : le trousseau y propose le compte enregistré.
    case email
    /// E-mail de contact (formulaire « Nous contacter ») : suggestion de l'adresse de la fiche Contacts.
    case contactEmail
    /// Mobile algérien.
    case phone
    /// Code à 6 chiffres reçu par e-mail (remplissage automatique depuis Mail).
    case oneTimeCode
}

/// Gabarit défilant des formulaires (Android : `AuthScaffold`) : contenu à largeur de lecture, gouttières de 24 pt,
/// clavier rabattu en faisant défiler, racine `screen.<nom>` (tour de captures). La barre de navigation reste celle
/// de la pile qui l'accueille (feuille de connexion ou onglet Profil).
struct AuthScaffold<Content: View>: View {
    private let screen: String
    private let content: Content

    init(screen: String, @ViewBuilder content: () -> Content) {
        self.screen = screen
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: WeydaSize.formMaxWidth, alignment: .leading)
            .padding(.horizontal, WeydaSpace.xxl)
            .padding(.top, WeydaSpace.sm)
            .padding(.bottom, WeydaSpace.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(WeydaColor.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(screen)")
    }
}

/// Marque (tuile + « Weydaa »), titre et sous-titre en tête des formulaires (Android : `AuthHeader`).
struct AuthHeader: View {
    private let title: String
    private let subtitle: String

    private static let tileSide: CGFloat = 44

    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WeydaSpace.md) {
                WeydaTile(size: Self.tileSide)
                WeydaWordmark(color: WeydaColor.primary)
            }
            Text(title)
                .weydaText(.headlineSmall)
                .foregroundStyle(WeydaColor.onBackground)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, WeydaSpace.xxl)
            Text(subtitle)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .padding(.top, WeydaSpace.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, WeydaSpace.xxl)
    }
}

/// Champ de saisie (Android : `AuthTextField`) : libellé, cadre (contour vert au focus, rouge en erreur), erreur ou aide.
/// E-mail, téléphone et code s'écrivent de gauche à droite même en arabe (sinon « +213… » s'affiche « 213…+ »).
struct AuthTextField<Field: Hashable>: View {
    private let label: String
    @Binding private var text: String
    private let focus: FocusState<Field?>.Binding
    private let field: Field
    private let error: String?
    private let supporting: String?
    private let kind: AuthFieldKind
    private let isEnabled: Bool

    init(
        _ label: String,
        text: Binding<String>,
        focus: FocusState<Field?>.Binding,
        field: Field,
        error: String? = nil,
        supporting: String? = nil,
        kind: AuthFieldKind = .text,
        isEnabled: Bool = true
    ) {
        self.label = label
        _text = text
        self.focus = focus
        self.field = field
        self.error = error
        self.supporting = supporting
        self.kind = kind
        self.isEnabled = isEnabled
    }

    var body: some View {
        AuthFieldFrame(label: label, error: error, supporting: supporting, input: input)
    }

    private var input: some View {
        TextField("", text: $text)
            .authKeyboard(kind)
            .weydaText(.bodyLarge)
            .foregroundStyle(WeydaColor.onSurface)
            .focused(focus, equals: field)
            .disabled(!isEnabled)
            .modifier(AuthInputChrome(isFocused: focus.wrappedValue == field, hasError: error != nil, hasAccessory: false))
            .accessibilityLabel(label)
    }
}

/// Mot de passe avec bascule afficher / masquer (Android : `PasswordField`). `isNew` : nouveau mot de passe
/// (inscription, réinitialisation) — le trousseau propose alors un mot de passe fort et l'enregistre.
struct PasswordField<Field: Hashable>: View {
    private let label: String
    @Binding private var text: String
    private let focus: FocusState<Field?>.Binding
    private let field: Field
    private let error: String?
    private let supporting: String?
    private let isNew: Bool
    private let isEnabled: Bool
    @State private var revealed: Bool = false
    @State private var refocus: Bool = false

    init(
        _ label: String,
        text: Binding<String>,
        focus: FocusState<Field?>.Binding,
        field: Field,
        error: String? = nil,
        supporting: String? = nil,
        isNew: Bool = false,
        isEnabled: Bool = true
    ) {
        self.label = label
        _text = text
        self.focus = focus
        self.field = field
        self.error = error
        self.supporting = supporting
        self.isNew = isNew
        self.isEnabled = isEnabled
    }

    var body: some View {
        AuthFieldFrame(label: label, error: error, supporting: supporting, input: input)
            .onChange(of: revealed) { _ in
                // La bascule remplace le champ (SecureField ↔ TextField) : le clavier lui est rendu s'il était ouvert.
                guard refocus else { return }
                refocus = false
                focus.wrappedValue = field
            }
    }

    private var input: some View {
        HStack(spacing: 0) {
            entry
                .textContentType(isNew ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .weydaText(.bodyLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .focused(focus, equals: field)
                .accessibilityLabel(label)
            Button(action: toggle) {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.body)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .frame(width: WeydaSize.touchTarget, height: WeydaSize.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealed ? L10n.authPasswordHide : L10n.authPasswordShow)
        }
        .disabled(!isEnabled)
        .modifier(AuthInputChrome(isFocused: focus.wrappedValue == field, hasError: error != nil, hasAccessory: true))
    }

    @ViewBuilder
    private var entry: some View {
        if revealed {
            TextField("", text: $text)
        } else {
            SecureField("", text: $text)
        }
    }

    private func toggle() {
        refocus = focus.wrappedValue == field
        revealed.toggle()
    }
}

/// Erreur globale d'un formulaire (Android : `ErrorBanner`), annoncée par VoiceOver dès son apparition — sinon
/// l'échec d'une connexion passerait inaperçu.
struct ErrorBanner: View {
    private let message: String

    init(message: String) {
        self.message = message
    }

    var body: some View {
        HStack(alignment: .top, spacing: WeydaSpace.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body)
                .accessibilityHidden(true)
            Text(message)
                .weydaText(.bodyMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(WeydaColor.onErrorContainer)
        .padding(WeydaSpace.md)
        .background(WeydaColor.errorContainer, in: RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("auth.error")
        .onAppear { announce() }
        .onChange(of: message) { _ in announce() }
    }

    private func announce() {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

/// Bouton principal pleine largeur (Android : `SubmitButton`) ; pendant l'envoi, le W s'écrit à la place du libellé
/// et un nouvel appui est ignoré.
struct SubmitButton: View {
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
                    WeydaLoader(color: WeydaColor.onPrimary)
                        .frame(width: Self.loaderSide, height: Self.loaderSide)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WeydaColor.primary)
        // Pendant l'envoi, le bouton garde sa couleur (le W reste lisible) ; `submit` ignore l'appui.
        .disabled(!isEnabled && !isLoading)
        .accessibilityLabel(isLoading ? L10n.loading : title)
        .accessibilityIdentifier("auth.submit")
    }

    /// Libellé sombre sur le vert clair du mode sombre (contraste), gris quand le bouton est désactivé.
    private var labelColor: Color {
        isEnabled ? WeydaColor.onPrimary : WeydaColor.onSurfaceVariant
    }

    private func submit() {
        guard !isLoading else { return }
        action()
    }
}

/// « ─── ou ─── » entre le formulaire et les connexions Apple / Google (Android : `OrDivider`).
struct OrDivider: View {
    init() {}

    var body: some View {
        HStack(spacing: WeydaSpace.md) {
            line
            Text(L10n.authOr)
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
            line
        }
        .padding(.vertical, WeydaSpace.lg)
        .accessibilityHidden(true)
    }

    private var line: some View {
        Rectangle()
            .fill(WeydaColor.outlineVariant)
            .frame(height: 1)
    }
}

/// « Pas encore de compte ? Créer un compte » (Android : `AuthSwitchLine`) ; passe sur deux lignes si besoin.
struct AuthSwitchLine: View {
    private let prompt: String
    private let action: String
    private let onTap: () -> Void

    init(prompt: String, action: String, onTap: @escaping () -> Void) {
        self.prompt = prompt
        self.action = action
        self.onTap = onTap
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WeydaSpace.xs) {
                promptText
                actionButton
            }
            VStack(spacing: 0) {
                promptText
                actionButton
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, WeydaSpace.lg)
    }

    private var promptText: some View {
        Text(prompt)
            .weydaText(.bodyMedium)
            .foregroundStyle(WeydaColor.onSurfaceVariant)
            .multilineTextAlignment(.center)
    }

    private var actionButton: some View {
        Button(action: onTap) {
            Text(action)
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.primary)
                .frame(minHeight: WeydaSize.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// « En continuant, vous acceptez les conditions d'utilisation et la politique de confidentialité de Weydaa »
/// (Android : `TermsNotice`), liens compris : sous l'inscription, et sous Apple / Google, qui peuvent créer un compte.
/// Un lien touché ouvre la page du site DANS la feuille (`onOpenPage`) ; repli : Safari.
struct TermsNotice: View {
    private let onOpenPage: (WebPage) -> Void

    init(onOpenPage: @escaping (WebPage) -> Void) {
        self.onOpenPage = onOpenPage
    }

    var body: some View {
        Text(Self.sentence())
            .weydaText(.bodySmall)
            .foregroundStyle(WeydaColor.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .tint(WeydaColor.primary)
            .frame(maxWidth: .infinity)
            .padding(.top, WeydaSpace.md)
            .environment(\.openURL, OpenURLAction { url in
                guard let page = Self.page(for: url) else { return .systemAction }
                onOpenPage(page)
                return .handled
            })
    }

    /// La phrase traduite, les deux mentions devenues des liens vers les pages du site.
    nonisolated static func sentence() -> AttributedString {
        let terms = L10n.authTermsLink
        let privacy = L10n.authPrivacyLink
        var text = AttributedString(L10n.authTermsNotice(terms, privacy))
        if let range = text.range(of: terms) {
            text[range].link = WebPage.terms.url()
        }
        if let range = text.range(of: privacy) {
            text[range].link = WebPage.privacy.url()
        }
        return text
    }

    nonisolated static func page(for url: URL) -> WebPage? {
        WebPage.allCases.first { $0.url() == url }
    }
}

/// Actions des connexions Apple et Google, communes à Connexion et Inscription.
struct AuthSocialActions {
    /// Bouton système Apple, au moment de l'appui : portée et nonce de la demande.
    var appleRequest: (ASAuthorizationAppleIDRequest) -> Void
    /// Bouton système Apple, à la fin (autorisation ou échec).
    var appleCompletion: (Result<ASAuthorization, any Error>) -> Void
    /// API simulée : appui sur le bouton Apple, sans fenêtre système.
    var appleSimulated: () -> Void
    var google: () -> Void
    var openPage: (WebPage) -> Void
}

/// « ou », « Continuer avec Apple », « Continuer avec Google » (si l'app a un identifiant client) puis l'acceptation
/// des conditions : sous Connexion et Inscription (Android : `OrDivider` + `GoogleSignInButton` + `TermsNotice`).
/// Apple et Google créent le compte s'il n'existe pas, d'où les conditions juste dessous.
struct AuthSocialSection: View {
    private let isAppleSimulated: Bool
    private let showsGoogle: Bool
    private let isSubmitting: Bool
    private let isAppleSubmitting: Bool
    private let isGoogleSubmitting: Bool
    private let actions: AuthSocialActions

    init(
        isAppleSimulated: Bool,
        showsGoogle: Bool,
        isSubmitting: Bool,
        isAppleSubmitting: Bool,
        isGoogleSubmitting: Bool,
        actions: AuthSocialActions
    ) {
        self.isAppleSimulated = isAppleSimulated
        self.showsGoogle = showsGoogle
        self.isSubmitting = isSubmitting
        self.isAppleSubmitting = isAppleSubmitting
        self.isGoogleSubmitting = isGoogleSubmitting
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 0) {
            OrDivider()
            AppleSignInButton(
                isSimulated: isAppleSimulated,
                isEnabled: !isSubmitting && !isGoogleSubmitting,
                isLoading: isAppleSubmitting,
                onRequest: actions.appleRequest,
                onCompletion: actions.appleCompletion,
                onSimulatedTap: actions.appleSimulated
            )
            if showsGoogle {
                GoogleSignInButton(
                    isEnabled: !isSubmitting && !isAppleSubmitting,
                    isLoading: isGoogleSubmitting,
                    action: actions.google
                )
                .padding(.top, WeydaSpace.md)
            }
            TermsNotice(onOpenPage: actions.openPage)
        }
        .padding(.top, WeydaSpace.xs)
    }
}

/// Code à 6 chiffres (Android : champ du code de `VerifyEmailScreen`) : grands chiffres espacés, centrés, toujours
/// de gauche à droite ; le code reçu par e-mail est proposé au-dessus du clavier (remplissage automatique).
struct AuthCodeField<Field: Hashable>: View {
    private let label: String
    @Binding private var text: String
    private let focus: FocusState<Field?>.Binding
    private let field: Field
    private let error: String?
    private let isEnabled: Bool

    /// Espace entre les chiffres (Android : letterSpacing 10 sp). Calculé : un type générique ne peut pas avoir de
    /// propriété statique stockée.
    private static var digitSpacing: CGFloat { WeydaSpace.sm }

    init(
        _ label: String,
        text: Binding<String>,
        focus: FocusState<Field?>.Binding,
        field: Field,
        error: String? = nil,
        isEnabled: Bool = true
    ) {
        self.label = label
        _text = text
        self.focus = focus
        self.field = field
        self.error = error
        self.isEnabled = isEnabled
    }

    var body: some View {
        AuthFieldFrame(label: label, error: error, supporting: nil, input: input)
    }

    private var input: some View {
        TextField("", text: $text)
            .authKeyboard(.oneTimeCode)
            .font(WeydaTextStyle.headlineMedium.font.monospacedDigit())
            .tracking(Self.digitSpacing)
            .multilineTextAlignment(.center)
            .foregroundStyle(WeydaColor.onSurface)
            .focused(focus, equals: field)
            .disabled(!isEnabled)
            .modifier(AuthInputChrome(isFocused: focus.wrappedValue == field, hasError: error != nil, hasAccessory: false))
            .accessibilityLabel(label)
            .accessibilityIdentifier("auth.code")
    }
}

/// Résultat d'un formulaire (e-mail envoyé, adresse vérifiée, mot de passe modifié) : pictogramme, titre, explication.
/// VoiceOver repart du haut de l'écran (le formulaire a disparu).
struct AuthConfirmation: View {
    private let systemImage: String
    private let title: String
    private let message: String

    private static let iconSide: CGFloat = 56

    init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: systemImage)
                .resizable()
                .scaledToFit()
                .frame(width: Self.iconSide, height: Self.iconSide)
                .foregroundStyle(WeydaColor.primary)
                .accessibilityHidden(true)
            Text(title)
                .weydaText(.headlineSmall)
                .foregroundStyle(WeydaColor.onBackground)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, WeydaSpace.lg)
            Text(message)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, WeydaSpace.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, WeydaSpace.xxl)
        .padding(.bottom, WeydaSpace.xxl)
        .onAppear {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
}

/// « Continuer avec Apple » : le bouton du SYSTÈME (libellé traduit et style fournis par Apple : noir en clair, blanc
/// en sombre), aux coins arrondis des autres boutons. En API simulée, il ne fait que déclencher `onSimulatedTap`
/// (aucune fenêtre système : les captures restent reproductibles).
struct AppleSignInButton: View {
    private let isSimulated: Bool
    private let isEnabled: Bool
    private let isLoading: Bool
    private let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    private let onCompletion: (Result<ASAuthorization, any Error>) -> Void
    private let onSimulatedTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// Hauteur des boutons Apple et Google (= bouton principal en taille large).
    static let height: CGFloat = 50
    private static let loaderSide: CGFloat = 22

    init(
        isSimulated: Bool,
        isEnabled: Bool,
        isLoading: Bool,
        onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
        onCompletion: @escaping (Result<ASAuthorization, any Error>) -> Void,
        onSimulatedTap: @escaping () -> Void
    ) {
        self.isSimulated = isSimulated
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.onRequest = onRequest
        self.onCompletion = onCompletion
        self.onSimulatedTap = onSimulatedTap
    }

    var body: some View {
        Group {
            if isSimulated {
                Button(action: onSimulatedTap) {
                    systemButton
                        .allowsHitTesting(false)
                }
                .buttonStyle(.plain)
            } else {
                systemButton
            }
        }
        .disabled(!isEnabled || isLoading)
        .overlay {
            if isLoading {
                loadingCover
            }
        }
        .accessibilityIdentifier("auth.apple")
    }

    private var isDark: Bool { colorScheme == .dark }

    private var systemButton: some View {
        SignInWithAppleButton(.continue, onRequest: onRequest, onCompletion: onCompletion)
            .signInWithAppleButtonStyle(isDark ? .white : .black)
            .frame(height: Self.height)
            .clipShape(Capsule())
    }

    /// Pendant l'appel au serveur : le bouton recouvert de sa propre couleur, le W s'écrit dessus.
    private var loadingCover: some View {
        Capsule()
            .fill(Color(rgb: isDark ? WeydaRamp.white : WeydaRamp.black))
            .overlay {
                WeydaLoader(color: Color(rgb: isDark ? WeydaRamp.black : WeydaRamp.white))
                    .frame(width: Self.loaderSide, height: Self.loaderSide)
            }
    }
}

/// « Continuer avec Google » (Android : `GoogleSignInButton`) : contour neutre, logo G officiel (image
/// `GoogleLogo` du catalogue d'assets, omise tant qu'elle n'y est pas), le W pendant l'appel.
struct GoogleSignInButton: View {
    private let isEnabled: Bool
    private let isLoading: Bool
    private let action: () -> Void

    private static let logoSide: CGFloat = 20

    init(isEnabled: Bool, isLoading: Bool, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: WeydaSpace.sm) {
                if isLoading {
                    WeydaLoader()
                        .frame(width: Self.logoSide, height: Self.logoSide)
                } else {
                    logo
                    Text(L10n.authGoogleButton)
                        .weydaText(.titleSmall)
                        .foregroundStyle(WeydaColor.onSurface)
                }
            }
            .frame(maxWidth: .infinity, minHeight: AppleSignInButton.height)
            .background(WeydaColor.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(WeydaColor.outline, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(WeydaPressStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(isLoading ? L10n.loading : L10n.authGoogleButton)
        .accessibilityIdentifier("auth.google")
    }

    @ViewBuilder
    private var logo: some View {
        if let image = UIImage(named: "GoogleLogo") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: Self.logoSide, height: Self.logoSide)
        }
    }
}

// MARK: - Interne

/// Libellé, champ, puis erreur (rouge) ou aide (gris).
private struct AuthFieldFrame<Input: View>: View {
    let label: String
    let error: String?
    let supporting: String?
    let input: Input

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            Text(label)
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .accessibilityHidden(true)
            input
            if let error {
                Text(error)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let supporting {
                Text(supporting)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, WeydaSpace.md)
    }
}

/// Cadre d'un champ : fond carte, contour fin ; vert au focus, rouge en erreur.
private struct AuthInputChrome: ViewModifier {
    let isFocused: Bool
    let hasError: Bool
    /// Un bouton (œil du mot de passe) occupe déjà le bord de fin.
    let hasAccessory: Bool

    private static let minHeight: CGFloat = 48

    private var borderColor: Color {
        if hasError { return WeydaColor.error }
        return isFocused ? WeydaColor.primary : WeydaPalette.cardOutline
    }

    private var borderWidth: CGFloat {
        hasError || isFocused ? 1.5 : 1
    }

    func body(content: Content) -> some View {
        content
            .frame(minHeight: Self.minHeight)
            .padding(.leading, WeydaSpace.md)
            .padding(.trailing, hasAccessory ? WeydaSpace.xxs : WeydaSpace.md)
            .background(WeydaColor.surface, in: RoundedRectangle(cornerRadius: WeydaRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WeydaRadius.field, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
    }
}

extension View {
    /// Clavier, remplissage automatique et sens d'écriture d'un champ selon sa nature.
    @ViewBuilder
    func authKeyboard(_ kind: AuthFieldKind) -> some View {
        switch kind {
        case .text:
            self.textInputAutocapitalization(.sentences)
        case .name:
            self.textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        case .email:
            self.keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
        case .contactEmail:
            self.keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
        case .phone:
            self.keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
        case .oneTimeCode:
            self.keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}
