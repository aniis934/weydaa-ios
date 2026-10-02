import SwiftUI

/// Écran de garde d'une fonction réservée aux membres (Déposer, Messages, Profil… — phase 3) — portage de
/// `LoginRequired.kt`. La tuile de l'icône de l'app : le visiteur retrouve la marque à l'endroit exact où on lui
/// demande de se connecter. Défilant : en très grand texte, rien n'est rogné.
struct LoginRequired: View {
    private let title: String
    private let message: String
    private let onLogin: () -> Void

    private static let tileSide: CGFloat = 72

    init(title: String, message: String, onLogin: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.onLogin = onLogin
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    WeydaTile(size: Self.tileSide)
                    Text(title)
                        .weydaText(.headlineSmall)
                        .foregroundStyle(WeydaColor.onBackground)
                        .multilineTextAlignment(.center)
                        .padding(.top, WeydaSpace.lg)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .weydaText(.bodyMedium)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.top, WeydaSpace.sm)
                    Button(action: onLogin) {
                        Text(L10n.authLoginButton)
                            .weydaText(.labelLarge)
                            .foregroundStyle(WeydaColor.onPrimary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(WeydaColor.primary)
                    .padding(.top, WeydaSpace.xxl)
                }
                .frame(maxWidth: WeydaSize.formMaxWidth)
                .padding(WeydaSpace.xxxl)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(WeydaColor.background)
    }
}
