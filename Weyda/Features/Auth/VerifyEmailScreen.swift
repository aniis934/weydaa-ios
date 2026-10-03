import SwiftUI

/// Code e-mail (étape `verifyEmail` de la feuille) — portage de `VerifyEmailRoute` / `VerifyEmailScreen` (Android) :
/// code à 6 chiffres envoyé à l'adresse du compte, renvoi après compte à rebours, « Plus tard » ; puis « Email
/// vérifié ! » et « Continuer ». Ouvert après une inscription, ou depuis le bandeau « Vérifiez votre email ».
struct VerifyEmailView: View {
    @EnvironmentObject private var container: AppContainer
    private let startsWithCooldown: Bool
    private let onDone: () -> Void

    /// `startsWithCooldown` : un code vient de partir (inscription) — le renvoi attend 60 s.
    init(startsWithCooldown: Bool, onDone: @escaping () -> Void) {
        self.startsWithCooldown = startsWithCooldown
        self.onDone = onDone
    }

    var body: some View {
        VerifyEmailHost(
            model: VerifyEmailViewModel(auth: container.auth, startsWithCooldown: startsWithCooldown),
            onDone: onDone
        )
    }
}

private struct VerifyEmailHost: View {
    @StateObject private var model: VerifyEmailViewModel
    private let onDone: () -> Void

    init(model: @autoclosure @escaping () -> VerifyEmailViewModel, onDone: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model())
        self.onDone = onDone
    }

    var body: some View {
        VerifyEmailScreen(state: model.state, code: codeBinding, actions: actions)
    }

    private var actions: VerifyEmailActions {
        let model = self.model
        return VerifyEmailActions(
            submit: { _ = model.submit() },
            resend: { _ = model.resend() },
            later: onDone,
            done: onDone
        )
    }

    private var codeBinding: Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.state.code } },
            set: { value in MainActor.assumeIsolated { _ = model.onCodeChange(value) } }
        )
    }
}

/// Actions de l'écran du code.
struct VerifyEmailActions {
    var submit: () -> Void
    var resend: () -> Void
    /// « Plus tard » : la feuille se ferme, le bandeau du Profil rappellera la vérification.
    var later: () -> Void
    /// « Continuer » après la vérification.
    var done: () -> Void
}

/// Code puis confirmation, sans état propre (hors focus). Le pavé numérique n'a pas de touche « OK » : le 6e chiffre
/// envoie le code (le code reçu dans Mail est aussi proposé au-dessus du clavier).
struct VerifyEmailScreen: View {
    private let state: VerifyEmailState
    @Binding private var code: String
    private let actions: VerifyEmailActions
    @FocusState private var focus: VerifyEmailField?

    init(state: VerifyEmailState, code: Binding<String>, actions: VerifyEmailActions) {
        self.state = state
        _code = code
        self.actions = actions
    }

    var body: some View {
        AuthScaffold(screen: "verifyEmail") {
            if state.verified {
                AuthConfirmation(
                    systemImage: "checkmark.circle.fill",
                    title: L10n.authVerifySuccess,
                    message: L10n.authVerifySuccessBody
                )
                SubmitButton(L10n.authContinue, action: actions.done)
            } else {
                form
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        AuthHeader(
            title: L10n.authVerifyTitle,
            subtitle: L10n.authVerifyBody(TextCheck.ifBlank(state.email, "—"))
        )
        AuthCodeField(
            L10n.authVerifyCode,
            text: $code,
            focus: $focus,
            field: .code,
            error: state.codeError,
            isEnabled: !state.isSubmitting
        )
        .submitLabel(.done)
        .onSubmit(actions.submit)
        if let message = state.errorMessage {
            ErrorBanner(message: message)
                .padding(.bottom, WeydaSpace.md)
        }
        if state.resent {
            Text(L10n.authVerifyResent)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, WeydaSpace.md)
        }
        SubmitButton(
            L10n.authVerifyButton,
            isEnabled: state.canSubmit,
            isLoading: state.isSubmitting,
            action: submit
        )
        .padding(.top, WeydaSpace.sm)
        VerifyEmailLinks(
            resendTitle: resendTitle,
            canResend: state.canResend,
            onResend: actions.resend,
            onLater: actions.later
        )
        .padding(.top, WeydaSpace.sm)
    }

    /// « Renvoyer dans 42 s » pendant le compte à rebours, sinon « Renvoyer le code ».
    private var resendTitle: String {
        state.cooldownSeconds > 0 ? L10n.authVerifyResendIn(state.cooldownSeconds) : L10n.authVerifyResend
    }

    private func submit() {
        focus = nil
        actions.submit()
    }
}

/// « Renvoyer le code » et « Plus tard » sur une ligne (Android : Row SpaceBetween) ; l'un sous l'autre si le texte
/// est très grand.
private struct VerifyEmailLinks: View {
    let resendTitle: String
    let canResend: Bool
    let onResend: () -> Void
    let onLater: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WeydaSpace.md) {
                resendButton
                Spacer(minLength: 0)
                laterButton
            }
            VStack(alignment: .leading, spacing: 0) {
                resendButton
                laterButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resendButton: some View {
        Button(action: onResend) {
            Text(resendTitle)
                .monospacedDigit()
                .weydaText(.labelLarge)
                .foregroundStyle(canResend ? WeydaColor.primary : WeydaColor.onSurfaceVariant)
                .frame(minHeight: WeydaSize.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canResend)
        .accessibilityIdentifier("auth.resend")
    }

    private var laterButton: some View {
        Button(action: onLater) {
            Text(L10n.authVerifyLater)
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.primary)
                .frame(minHeight: WeydaSize.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("auth.later")
    }
}
