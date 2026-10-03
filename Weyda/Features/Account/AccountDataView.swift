import SwiftUI

/// « Mes données » — portage d'`AccountDataRoute` / `AccountDataScreen` (AccountDataScreen.kt), conformité loi 18-07 :
/// portabilité (export JSON partagé par la feuille de partage du système) et droit à l'effacement (suppression réelle
/// du compte, confirmée par le mot de passe, ou par Google ou Apple pour un compte créé avec eux). Compte supprimé :
/// la session se ferme, `AccountMemberGate` retire l'écran et le Profil repasse en visiteur.
struct AccountDataView: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        AccountMemberGate(title: L10n.accountDataTitle) { user in
            AccountDataHost(model: Self.makeModel(container: container, user: user))
        }
    }

    /// Branchements réels : moyens de connexion relus sur le serveur (`UserRepository.signInMethods` : `providers`
    /// n'existe pas dans `User`), autorisations Apple / Google du système (simulées en API simulée).
    private static func makeModel(container: AppContainer, user: User) -> AccountDataViewModel {
        let users = container.users
        let apple = AppleSignInCoordinator()
        let google = GoogleSignInCoordinator()
        return AccountDataViewModel(
            accountData: container.accountData,
            user: user,
            loadSignInMethods: {
                let methods = try await users.signInMethods()
                return AccountSignInMethods(hasPassword: methods.hasPassword, providers: methods.providers)
            },
            appleCredential: {
                try await apple.signIn()
            },
            googleIDToken: {
                try await google.signIn()
            }
        )
    }
}

/// Possède le ViewModel ; ouvre la feuille de partage quand un export est prêt.
private struct AccountDataHost: View {
    @StateObject private var model: AccountDataViewModel

    init(model: @autoclosure @escaping () -> AccountDataViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        AccountDataScreen(
            state: model.state,
            password: passwordBinding,
            confirmDelete: confirmBinding,
            onExport: { _ = model.export() },
            onAskDelete: { model.askDelete() },
            onConfirmDelete: { _ = model.confirmDelete() }
        )
        .onAppear {
            _ = model.loadIfNeeded()
        }
        .onChange(of: model.state.pendingShare) { file in
            guard let file else { return }
            model.exportShared()
            AccountShareSheet.present(file)
        }
    }

    /// Lue et écrite sur le fil principal (comme les liaisons d'`AppRouter`).
    private var passwordBinding: Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.state.password } },
            set: { value in MainActor.assumeIsolated { model.updatePassword(value) } }
        )
    }

    /// La boîte de confirmation se ferme d'elle-même après un appui : seul « fermé » est transmis.
    private var confirmBinding: Binding<Bool> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.state.confirmDelete } },
            set: { value in
                MainActor.assumeIsolated {
                    if !value {
                        model.dismissDelete()
                    }
                }
            }
        )
    }
}

/// Écran sans état propre (hors focus) : la carte de l'export, puis celle de la suppression.
struct AccountDataScreen: View {
    private let state: AccountDataState
    @Binding private var password: String
    @Binding private var confirmDelete: Bool
    private let onExport: () -> Void
    private let onAskDelete: () -> Void
    private let onConfirmDelete: () -> Void
    @FocusState private var focus: AccountDataField?

    init(
        state: AccountDataState,
        password: Binding<String>,
        confirmDelete: Binding<Bool>,
        onExport: @escaping () -> Void,
        onAskDelete: @escaping () -> Void,
        onConfirmDelete: @escaping () -> Void
    ) {
        self.state = state
        _password = password
        _confirmDelete = confirmDelete
        self.onExport = onExport
        self.onAskDelete = onAskDelete
        self.onConfirmDelete = onConfirmDelete
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeydaSpace.lg) {
                exportCard
                deleteCard
            }
            .frame(maxWidth: WeydaSize.formMaxWidth, alignment: .leading)
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.vertical, WeydaSpace.lg)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(WeydaColor.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            OfflineBanner()
        }
        .navigationTitle(L10n.accountDataTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(L10n.deleteAccountConfirmTitle, isPresented: $confirmDelete) {
            Button(confirmTitle, role: .destructive) {
                onConfirmDelete()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.deleteAccountConfirmBody)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.accountData")
    }

    // MARK: - Export

    private var exportCard: some View {
        AccountCard(title: L10n.exportTitle) {
            Text(L10n.exportBody)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            if let message = state.exportError {
                ErrorBanner(message: message)
            }
            if let file = state.exportFile {
                AccountExportReady(file: file)
            } else {
                AccountSecondaryButton(L10n.exportAction, isLoading: state.isExporting, action: onExport)
                    .accessibilityIdentifier("accountData.export")
            }
        }
    }

    // MARK: - Suppression

    private var deleteCard: some View {
        AccountCard(title: L10n.deleteAccountTitle, titleColor: WeydaColor.error) {
            Text(L10n.deleteAccountBody)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            proof
            if let message = state.deleteError {
                ErrorBanner(message: message)
            }
            AccountDestructiveButton(
                confirmTitle,
                isEnabled: state.canAskDelete,
                isLoading: state.isDeleting,
                action: { askDelete() }
            )
            .accessibilityIdentifier("accountData.delete")
        }
    }

    /// Mot de passe à saisir, ou l'explication de la reconnexion Google / Apple (aucune saisie).
    @ViewBuilder
    private var proof: some View {
        switch state.method {
        case .password:
            PasswordField(
                L10n.deleteAccountPassword,
                text: $password,
                focus: $focus,
                field: .password,
                isEnabled: !state.isDeleting
            )
            .submitLabel(.done)
            .onSubmit { askDelete() }
        case .google:
            proofHint(L10n.accountDeleteGoogleHint)
        case .apple:
            proofHint(L10n.accountDeleteAppleHint)
        }
    }

    private func proofHint(_ text: String) -> some View {
        Text(text)
            .weydaText(.bodySmall)
            .foregroundStyle(WeydaColor.onSurfaceVariant)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Libellé du bouton et de la confirmation : « Supprimer définitivement », ou « Confirmer avec Google / Apple et
    /// supprimer » (la reconnexion s'ouvre juste après).
    private var confirmTitle: String {
        switch state.method {
        case .password: L10n.deleteAccountAction
        case .google: L10n.accountDeleteGoogleConfirm
        case .apple: L10n.accountDeleteAppleConfirm
        }
    }

    private func askDelete() {
        focus = nil
        onAskDelete()
    }
}

/// Export prêt : le nom du fichier, puis « Partager » (feuille de partage du système, sans nouvel export).
private struct AccountExportReady: View {
    let file: URL

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            HStack(alignment: .top, spacing: WeydaSpace.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(WeydaColor.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                    Text(L10n.exportReady)
                        .weydaText(.labelLarge)
                        .foregroundStyle(WeydaColor.onSurface)
                    // Un nom de fichier se lit de gauche à droite, même dans une interface en arabe.
                    Text(Format.ltrIsolate(file.lastPathComponent))
                        .weydaText(.bodySmall)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .accessibilityElement(children: .combine)
            ShareLink(item: file) {
                Label(L10n.share, systemImage: "square.and.arrow.up")
                    .weydaText(.titleSmall)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(WeydaColor.primary)
            .accessibilityIdentifier("accountData.share")
        }
    }
}
