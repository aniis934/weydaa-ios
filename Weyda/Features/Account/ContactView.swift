import SwiftUI

/// « Nous contacter » — portage de `ContactRoute` / `ContactScreen` (ContactScreen.kt) : nom, e-mail, sujet, message,
/// envoyés à l'équipe (réponse par e-mail). Ouvert aux visiteurs ; pré-rempli pour un membre. Envoyé : confirmation,
/// puis « Retour ».
struct ContactView: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        ContactHost(model: ContactViewModel(api: container.api, user: container.sessionManager.user))
    }
}

/// Possède le ViewModel ; les liaisons de texte passent par ses méthodes (bornes, effacement des erreurs).
private struct ContactHost: View {
    @StateObject private var model: ContactViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: @autoclosure @escaping () -> ContactViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        ContactScreen(
            state: model.state,
            name: binding(.name),
            email: binding(.email),
            subject: binding(.subject),
            message: binding(.message),
            onSend: { _ = model.send() },
            onBack: { dismiss() }
        )
    }

    /// Lue et écrite sur le fil principal (comme les liaisons d'`AppRouter`).
    private func binding(_ field: ContactField) -> Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.value(of: field) } },
            set: { value in MainActor.assumeIsolated { model.update(field, to: value) } }
        )
    }
}

/// Formulaire sans état propre (hors focus), puis la confirmation d'envoi.
struct ContactScreen: View {
    private let state: ContactState
    @Binding private var name: String
    @Binding private var email: String
    @Binding private var subject: String
    @Binding private var message: String
    private let onSend: () -> Void
    private let onBack: () -> Void
    @FocusState private var focus: ContactField?

    init(
        state: ContactState,
        name: Binding<String>,
        email: Binding<String>,
        subject: Binding<String>,
        message: Binding<String>,
        onSend: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.state = state
        _name = name
        _email = email
        _subject = subject
        _message = message
        self.onSend = onSend
        self.onBack = onBack
    }

    var body: some View {
        AuthScaffold(screen: "contact") {
            if state.isSent {
                AuthConfirmation(
                    systemImage: "checkmark.circle.fill",
                    title: L10n.contactSentTitle,
                    message: L10n.contactSentBody
                )
                SubmitButton(L10n.back, action: onBack)
            } else {
                form
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            OfflineBanner()
        }
        .navigationTitle(L10n.contactTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var form: some View {
        Text(L10n.contactIntro)
            .weydaText(.bodyMedium)
            .foregroundStyle(WeydaColor.onSurfaceVariant)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, WeydaSpace.xl)
        AuthTextField(
            L10n.contactName,
            text: $name,
            focus: $focus,
            field: .name,
            error: state.nameError,
            kind: .name,
            isEnabled: !state.isSending
        )
        .submitLabel(.next)
        .onSubmit { focus = .email }
        AuthTextField(
            L10n.contactEmail,
            text: $email,
            focus: $focus,
            field: .email,
            error: state.emailError,
            kind: .contactEmail,
            isEnabled: !state.isSending
        )
        .submitLabel(.next)
        .onSubmit { focus = .subject }
        AuthTextField(
            L10n.contactSubject,
            text: $subject,
            focus: $focus,
            field: .subject,
            error: state.subjectError,
            kind: .text,
            isEnabled: !state.isSending
        )
        .submitLabel(.next)
        .onSubmit { focus = .message }
        AccountTextArea(
            L10n.contactMessage,
            text: $message,
            focus: $focus,
            field: .message,
            error: state.messageError,
            minLines: ContactScreenMetrics.messageLines,
            isEnabled: !state.isSending
        )
        if let errorMessage = state.errorMessage {
            ErrorBanner(message: errorMessage)
                .padding(.bottom, WeydaSpace.md)
        }
        SubmitButton(
            L10n.contactSend,
            isEnabled: !state.isSending,
            isLoading: state.isSending,
            action: { send() }
        )
        .padding(.top, WeydaSpace.sm)
    }

    private func send() {
        focus = nil
        onSend()
    }
}

nonisolated enum ContactScreenMetrics {
    /// Le message s'ouvre sur 5 lignes, comme Android (`minLines = 5`).
    static let messageLines = 5
}
