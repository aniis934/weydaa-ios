import SwiftUI

/// « Modifier mon profil » — portage d'`EditProfileRoute` / `EditProfileScreen` (EditProfileScreen.kt) : nom,
/// e-mail (nouveau code de vérification si l'adresse change), téléphone, bio. Enregistré : retour au profil.
struct EditProfileView: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        AccountMemberGate(title: L10n.editProfileTitle) { _ in
            EditProfileHost(model: EditProfileViewModel(users: container.users, auth: container.auth))
        }
    }
}

/// Possède le ViewModel ; les liaisons de texte passent par ses méthodes (effacement des erreurs à la saisie).
private struct EditProfileHost: View {
    @StateObject private var model: EditProfileViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: @autoclosure @escaping () -> EditProfileViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        EditProfileScreen(
            state: model.state,
            name: binding(.name),
            email: binding(.email),
            phone: binding(.phone),
            bio: binding(.bio),
            onSubmit: { _ = model.submit() },
            onRetryLoad: { _ = model.load() }
        )
        .onAppear {
            _ = model.loadIfNeeded()
        }
        .onChange(of: model.state.saved) { saved in
            if saved {
                dismiss()
            }
        }
    }

    /// Lue et écrite sur le fil principal (comme les liaisons d'`AppRouter`).
    private func binding(_ field: EditProfileField) -> Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.value(of: field) } },
            set: { value in MainActor.assumeIsolated { model.update(field, to: value) } }
        )
    }
}

/// Formulaire sans état propre (hors focus) : les champs ne s'éditent qu'une fois le profil complet relu.
struct EditProfileScreen: View {
    private let state: EditProfileState
    @Binding private var name: String
    @Binding private var email: String
    @Binding private var phone: String
    @Binding private var bio: String
    private let onSubmit: () -> Void
    private let onRetryLoad: () -> Void
    @FocusState private var focus: EditProfileField?

    init(
        state: EditProfileState,
        name: Binding<String>,
        email: Binding<String>,
        phone: Binding<String>,
        bio: Binding<String>,
        onSubmit: @escaping () -> Void,
        onRetryLoad: @escaping () -> Void
    ) {
        self.state = state
        _name = name
        _email = email
        _phone = phone
        _bio = bio
        self.onSubmit = onSubmit
        self.onRetryLoad = onRetryLoad
    }

    var body: some View {
        AuthScaffold(screen: "editProfile") {
            if let message = state.loadErrorMessage {
                loadError(message)
            }
            AuthTextField(
                L10n.authName,
                text: $name,
                focus: $focus,
                field: .name,
                error: state.nameError,
                kind: .name,
                isEnabled: state.canEdit
            )
            .submitLabel(.next)
            .onSubmit { focus = .email }
            AuthTextField(
                L10n.authEmail,
                text: $email,
                focus: $focus,
                field: .email,
                error: state.emailError,
                supporting: emailNote,
                kind: .contactEmail,
                isEnabled: state.canEdit
            )
            .submitLabel(.next)
            .onSubmit { focus = .phone }
            AuthTextField(
                L10n.authPhoneOptional,
                text: $phone,
                focus: $focus,
                field: .phone,
                error: state.phoneError,
                kind: .phone,
                isEnabled: state.canEdit
            )
            AccountTextArea(
                L10n.editProfileBio,
                text: $bio,
                focus: $focus,
                field: .bio,
                error: state.bioError,
                counter: state.bioCounter,
                isEnabled: state.canEdit
            )
            if let message = state.errorMessage {
                ErrorBanner(message: message)
                    .padding(.bottom, WeydaSpace.md)
            }
            SubmitButton(
                L10n.editProfileSave,
                isEnabled: state.canSubmit,
                isLoading: state.isSubmitting || state.isLoading,
                action: { submit() }
            )
            .padding(.top, WeydaSpace.sm)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            OfflineBanner()
        }
        .navigationTitle(L10n.editProfileTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Une nouvelle adresse recevra un code de vérification (Android : texte d'aide sous le champ).
    private var emailNote: String? {
        state.emailChanged ? L10n.editProfileEmailChangeNote : nil
    }

    /// Profil complet illisible : rien n'est éditable (enregistrer effacerait téléphone et bio), on propose de
    /// réessayer.
    private func loadError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            ErrorBanner(message: message)
            Button(action: onRetryLoad) {
                Text(L10n.retry)
                    .weydaText(.labelLarge)
                    .foregroundStyle(WeydaColor.primary)
                    .frame(minHeight: WeydaSize.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, WeydaSpace.md)
    }

    private func submit() {
        focus = nil
        onSubmit()
    }
}
