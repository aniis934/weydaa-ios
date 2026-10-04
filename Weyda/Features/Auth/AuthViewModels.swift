import AuthenticationServices
import Foundation

// États et ViewModels de la feuille de connexion — portage d'`ui/auth/AuthViewModels.kt` (+ `ResetPasswordViewModel`
// de ResetPasswordScreen.kt). Les messages sont déjà traduits (Android : `@StringRes`) ; chaque action renvoie sa
// tâche (`@discardableResult`) : l'interface l'ignore, les tests l'attendent.

// MARK: - Connexion

nonisolated enum LoginField: Hashable, Sendable {
    case email
    case password
}

nonisolated struct LoginState: Equatable, Sendable {
    var email: String = ""
    var password: String = ""
    var emailError: String? = nil
    var passwordError: String? = nil
    var isSubmitting: Bool = false
    var errorMessage: String? = nil
    /// Verrou du compte (423 accountLocked / 429) : secondes avant un nouvel essai (« Réessayez dans N min. » est
    /// déjà dans `errorMessage`).
    var retryAfterSeconds: Int? = nil
    /// Connexion réussie. La feuille, qui suit la session, se ferme d'elle-même (ou passe au code e-mail).
    var success: User? = nil
    /// `POST api/auth/google` en cours (fenêtre de Google comprise).
    var isGoogleSubmitting: Bool = false
    /// `POST api/auth/apple` en cours.
    var isAppleSubmitting: Bool = false

    var isBusy: Bool { isSubmitting || isGoogleSubmitting || isAppleSubmitting }
    var canSubmit: Bool { !isBusy && !TextCheck.isBlank(email) && !password.isEmpty }

    /// Appel en cours ou champ rempli : glisser la feuille vers le bas ne la ferme plus (la saisie serait perdue) ;
    /// « Fermer » reste possible.
    var keepsSheetOpen: Bool { isBusy || !TextCheck.isBlank(email) || !password.isEmpty }
}

/// Connexion par e-mail, Apple ou Google — portage de `LoginViewModel`.
final class LoginViewModel: ObservableObject {
    @Published private(set) var state = LoginState()

    let social: SocialSignIn
    private let auth: AuthRepository

    init(auth: AuthRepository, social: SocialSignIn) {
        self.auth = auth
        self.social = social
    }

    func onEmailChange(_ value: String) {
        state.email = value
        state.emailError = nil
        state.errorMessage = nil
    }

    func onPasswordChange(_ value: String) {
        state.password = value
        state.passwordError = nil
        state.errorMessage = nil
    }

    func value(of field: LoginField) -> String {
        switch field {
        case .email: state.email
        case .password: state.password
        }
    }

    func update(_ field: LoginField, to value: String) {
        switch field {
        case .email: onEmailChange(value)
        case .password: onPasswordChange(value)
        }
    }

    /// Règles locales d'abord (aucun appel réseau si l'e-mail est mal formé ou le mot de passe vide), puis
    /// `POST api/auth/token`. Erreurs Zod 400 → sous les champs ; sinon bandeau, avec le délai d'un compte verrouillé.
    @discardableResult
    func submit() -> Task<Void, Never>? {
        let current = state
        guard !current.isBusy else { return nil }
        let emailError = Validators.email(current.email)?.text
        let passwordError = Validators.passwordRequired(current.password)?.text
        guard emailError == nil, passwordError == nil else {
            state.emailError = emailError
            state.passwordError = passwordError
            return nil
        }
        state.isSubmitting = true
        state.errorMessage = nil
        state.retryAfterSeconds = nil
        return Task { [weak self] in
            guard let self else { return }
            do {
                let user = try await self.auth.login(email: current.email, password: current.password)
                self.succeeded(user)
            } catch {
                let fields = ErrorMapper.fieldMessages(for: error)
                var next = self.state
                next.isSubmitting = false
                next.errorMessage = fields.isEmpty ? ErrorMapper.messageWithRetryHint(for: error) : nil
                next.emailError = fields["email"]
                next.passwordError = fields["password"]
                next.retryAfterSeconds = (error as? APIError)?.retryAfterSeconds
                self.state = next
            }
        }
    }

    // MARK: Apple, Google

    /// « Continuer avec Google » : la page de Google, puis la session.
    @discardableResult
    func continueWithGoogle() -> Task<Void, Never>? {
        runSocial(.google)
    }

    /// id_token déjà obtenu → `POST api/auth/google` (Android : `signInWithGoogle`).
    @discardableResult
    func signInWithGoogle(idToken: String) -> Task<Void, Never>? {
        runSocial(.googleToken(idToken))
    }

    /// Bouton système Apple, au moment de l'appui.
    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        social.apple.prepare(request)
    }

    /// Bouton système Apple, à la fin : l'autorisation part au serveur ; fenêtre fermée → rien.
    @discardableResult
    func completeApple(_ result: Result<ASAuthorization, any Error>) -> Task<Void, Never>? {
        do {
            let credential = try social.apple.credential(from: result)
            return signInWithApple(credential)
        } catch {
            onSocialFailed(error)
            return nil
        }
    }

    /// API simulée : l'appui sur le bouton Apple simule l'autorisation.
    @discardableResult
    func continueWithSimulatedApple() -> Task<Void, Never>? {
        runSocial(.appleAuthorization)
    }

    @discardableResult
    func signInWithApple(_ credential: AppleCredential) -> Task<Void, Never>? {
        runSocial(.apple(credential))
    }

    /// Échec sur l'appareil (fenêtre du système, réponse illisible) ; une annulation ne montre rien.
    func onSocialFailed(_ error: any Error) {
        guard let message = ErrorMapper.message(for: error) else { return }
        state.errorMessage = message
    }

    private func runSocial(_ route: SocialRoute) -> Task<Void, Never>? {
        guard !state.isBusy else { return nil }
        var next = state
        next.errorMessage = nil
        next.retryAfterSeconds = nil
        if route.isGoogle {
            next.isGoogleSubmitting = true
        } else {
            next.isAppleSubmitting = true
        }
        state = next
        let social = self.social
        return Task { [weak self] in
            do {
                let user = try await social.signIn(route)
                self?.succeeded(user)
            } catch {
                guard let self else { return }
                var failed = self.state
                failed.isGoogleSubmitting = false
                failed.isAppleSubmitting = false
                failed.errorMessage = ErrorMapper.messageWithRetryHint(for: error)
                failed.retryAfterSeconds = (error as? APIError)?.retryAfterSeconds
                self.state = failed
            }
        }
    }

    /// Le mot de passe quitte la mémoire dès qu'il a servi (Android : `successConsumed`).
    private func succeeded(_ user: User) {
        var next = state
        next.isSubmitting = false
        next.isGoogleSubmitting = false
        next.isAppleSubmitting = false
        next.password = ""
        next.success = user
        state = next
    }
}

// MARK: - Inscription

nonisolated enum RegisterField: Hashable, Sendable {
    case name
    case email
    case password
    case phone
}

nonisolated struct RegisterState: Equatable, Sendable {
    var name: String = ""
    var email: String = ""
    var password: String = ""
    var phone: String = ""
    var nameError: String? = nil
    var emailError: String? = nil
    var passwordError: String? = nil
    var phoneError: String? = nil
    var isSubmitting: Bool = false
    var errorMessage: String? = nil
    /// Compte créé et session ouverte (e-mail à vérifier : la feuille passe au code).
    var success: User? = nil
    var isGoogleSubmitting: Bool = false
    var isAppleSubmitting: Bool = false

    var isBusy: Bool { isSubmitting || isGoogleSubmitting || isAppleSubmitting }
    var canSubmit: Bool {
        !isBusy && !TextCheck.isBlank(name) && !TextCheck.isBlank(email) && !password.isEmpty
    }

    /// Appel en cours ou champ rempli : glisser la feuille vers le bas ne la ferme plus ; « Fermer » reste possible.
    var keepsSheetOpen: Bool {
        isBusy || !TextCheck.isBlank(name) || !TextCheck.isBlank(email) || !password.isEmpty || !TextCheck.isBlank(phone)
    }
}

/// Inscription par e-mail (puis connexion automatique), Apple ou Google — portage de `RegisterViewModel`.
final class RegisterViewModel: ObservableObject {
    @Published private(set) var state = RegisterState()

    let social: SocialSignIn
    private let auth: AuthRepository
    private var demoApplied: Bool = false

    init(auth: AuthRepository, social: SocialSignIn) {
        self.auth = auth
        self.social = social
    }

    func onNameChange(_ value: String) {
        state.name = value
        state.nameError = nil
        state.errorMessage = nil
    }

    func onEmailChange(_ value: String) {
        state.email = value
        state.emailError = nil
        state.errorMessage = nil
    }

    func onPasswordChange(_ value: String) {
        state.password = value
        state.passwordError = nil
        state.errorMessage = nil
    }

    func onPhoneChange(_ value: String) {
        state.phone = value
        state.phoneError = nil
        state.errorMessage = nil
    }

    func value(of field: RegisterField) -> String {
        switch field {
        case .name: state.name
        case .email: state.email
        case .password: state.password
        case .phone: state.phone
        }
    }

    func update(_ field: RegisterField, to value: String) {
        switch field {
        case .name: onNameChange(value)
        case .email: onEmailChange(value)
        case .password: onPasswordChange(value)
        case .phone: onPhoneChange(value)
        }
    }

    /// Règles du serveur vérifiées sur place (nom 2–50, e-mail, mot de passe fort, mobile algérien facultatif), puis
    /// `POST api/auth/register` + connexion. Erreurs Zod 400 → sous les champs ; sinon bandeau.
    @discardableResult
    func submit() -> Task<Void, Never>? {
        let current = state
        guard !current.isBusy else { return nil }
        let nameError = Validators.name(current.name)?.text
        let emailError = Validators.email(current.email)?.text
        let passwordError = Validators.password(current.password)?.text
        let phoneError = Validators.mobilePhone(current.phone)?.text
        guard nameError == nil, emailError == nil, passwordError == nil, phoneError == nil else {
            var next = state
            next.nameError = nameError
            next.emailError = emailError
            next.passwordError = passwordError
            next.phoneError = phoneError
            state = next
            return nil
        }
        state.isSubmitting = true
        state.errorMessage = nil
        return Task { [weak self] in
            guard let self else { return }
            do {
                let user = try await self.auth.register(
                    name: current.name,
                    email: current.email,
                    password: current.password,
                    phone: Validators.normalizePhone(current.phone)
                )
                self.succeeded(user)
            } catch {
                let fields = ErrorMapper.fieldMessages(for: error)
                var next = self.state
                next.isSubmitting = false
                next.errorMessage = fields.isEmpty ? ErrorMapper.message(for: error) : nil
                next.nameError = fields["name"]
                next.emailError = fields["email"]
                next.passwordError = fields["password"]
                next.phoneError = fields["phone"]
                self.state = next
            }
        }
    }

    // MARK: Apple, Google (même route que la connexion : le serveur crée le compte s'il n'existe pas)

    @discardableResult
    func continueWithGoogle() -> Task<Void, Never>? {
        runSocial(.google)
    }

    @discardableResult
    func signInWithGoogle(idToken: String) -> Task<Void, Never>? {
        runSocial(.googleToken(idToken))
    }

    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        social.apple.prepare(request)
    }

    @discardableResult
    func completeApple(_ result: Result<ASAuthorization, any Error>) -> Task<Void, Never>? {
        do {
            let credential = try social.apple.credential(from: result)
            return signInWithApple(credential)
        } catch {
            onSocialFailed(error)
            return nil
        }
    }

    @discardableResult
    func continueWithSimulatedApple() -> Task<Void, Never>? {
        runSocial(.appleAuthorization)
    }

    @discardableResult
    func signInWithApple(_ credential: AppleCredential) -> Task<Void, Never>? {
        runSocial(.apple(credential))
    }

    func onSocialFailed(_ error: any Error) {
        guard let message = ErrorMapper.message(for: error) else { return }
        state.errorMessage = message
    }

    /// Captures (Debug, `-WeydaAuthDemo invalid`) : formulaire rempli de valeurs FICTIVES refusées, puis envoyé —
    /// les erreurs de champ s'affichent sans saisie au clavier. Une seule fois par écran.
    func applyCaptureDemo(_ demo: String?) {
        guard demo == "invalid", !demoApplied else { return }
        demoApplied = true
        var next = state
        next.name = "K"
        next.email = "karim@"
        next.password = "abc"
        next.phone = "0210 12 34 56"
        state = next
        submit()
    }

    private func runSocial(_ route: SocialRoute) -> Task<Void, Never>? {
        guard !state.isBusy else { return nil }
        var next = state
        next.errorMessage = nil
        if route.isGoogle {
            next.isGoogleSubmitting = true
        } else {
            next.isAppleSubmitting = true
        }
        state = next
        let social = self.social
        return Task { [weak self] in
            do {
                let user = try await social.signIn(route)
                self?.succeeded(user)
            } catch {
                guard let self else { return }
                var failed = self.state
                failed.isGoogleSubmitting = false
                failed.isAppleSubmitting = false
                failed.errorMessage = ErrorMapper.message(for: error)
                self.state = failed
            }
        }
    }

    private func succeeded(_ user: User) {
        var next = state
        next.isSubmitting = false
        next.isGoogleSubmitting = false
        next.isAppleSubmitting = false
        next.password = ""
        next.success = user
        state = next
    }
}

// MARK: - Mot de passe oublié

nonisolated enum ForgotPasswordField: Hashable, Sendable {
    case email
}

nonisolated struct ForgotPasswordState: Equatable, Sendable {
    var email: String = ""
    var emailError: String? = nil
    var isSubmitting: Bool = false
    var errorMessage: String? = nil
    /// E-mail pour lequel la demande est partie (écran de confirmation).
    var sentTo: String? = nil

    var canSubmit: Bool { !isSubmitting && !TextCheck.isBlank(email) }

    /// Envoi en cours, ou adresse saisie pas encore envoyée : glisser la feuille ne la ferme plus (la confirmation,
    /// elle, se ferme librement).
    var keepsSheetOpen: Bool { isSubmitting || (sentTo == nil && !TextCheck.isBlank(email)) }
}

/// « Mot de passe oublié » — portage de `ForgotPasswordViewModel`. Le serveur répond toujours 200 (il ne dit pas si
/// le compte existe) : succès = « si un compte existe, un lien est parti ».
final class ForgotPasswordViewModel: ObservableObject {
    @Published private(set) var state = ForgotPasswordState()

    private let auth: AuthRepository
    private let locale: String

    init(auth: AuthRepository, locale: String = WeydaLocale.language) {
        self.auth = auth
        self.locale = locale
    }

    func onEmailChange(_ value: String) {
        state.email = value
        state.emailError = nil
        state.errorMessage = nil
    }

    @discardableResult
    func submit() -> Task<Void, Never>? {
        let current = state
        guard !current.isSubmitting else { return nil }
        if let error = Validators.email(current.email) {
            state.emailError = error.text
            return nil
        }
        state.isSubmitting = true
        state.errorMessage = nil
        let locale = self.locale
        return Task { [weak self] in
            guard let self else { return }
            do {
                try await self.auth.forgotPassword(email: current.email, locale: locale)
                var next = self.state
                next.isSubmitting = false
                next.sentTo = current.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                self.state = next
            } catch {
                var next = self.state
                next.isSubmitting = false
                next.errorMessage = ErrorMapper.message(for: error)
                self.state = next
            }
        }
    }
}

// MARK: - Nouveau mot de passe (lien de l'e-mail)

nonisolated enum ResetPasswordField: Hashable, Sendable {
    case password
    case confirm
}

nonisolated struct ResetPasswordState: Equatable, Sendable {
    var password: String = ""
    var confirm: String = ""
    var passwordError: String? = nil
    var confirmError: String? = nil
    var isSubmitting: Bool = false
    var errorMessage: String? = nil
    var isDone: Bool = false
    /// Lien sans jeton (copié à moitié) : rien à envoyer.
    var invalidLink: Bool = false

    var canSubmit: Bool {
        !isSubmitting && !TextCheck.isBlank(password) && !TextCheck.isBlank(confirm)
    }

    /// Envoi en cours, ou mot de passe saisi pas encore enregistré : glisser la feuille ne la ferme plus.
    var keepsSheetOpen: Bool { isSubmitting || (!isDone && (!password.isEmpty || !confirm.isEmpty)) }
}

/// Nouveau mot de passe depuis le lien « mot de passe oublié » (`/{locale}/auth/reinitialiser-mdp?token=…`), ouvert
/// DANS l'app — portage de `ResetPasswordViewModel`. Mêmes règles qu'à l'inscription ; le serveur révoque toutes les
/// sessions du compte.
final class ResetPasswordViewModel: ObservableObject {
    @Published private(set) var state: ResetPasswordState

    private let token: String
    private let auth: AuthRepository

    init(token: String, auth: AuthRepository) {
        self.token = token
        self.auth = auth
        state = ResetPasswordState(invalidLink: TextCheck.isBlank(token))
    }

    func onPasswordChange(_ value: String) {
        state.password = value
        state.passwordError = nil
        state.errorMessage = nil
    }

    func onConfirmChange(_ value: String) {
        state.confirm = value
        state.confirmError = nil
        state.errorMessage = nil
    }

    func value(of field: ResetPasswordField) -> String {
        switch field {
        case .password: state.password
        case .confirm: state.confirm
        }
    }

    func update(_ field: ResetPasswordField, to value: String) {
        switch field {
        case .password: onPasswordChange(value)
        case .confirm: onConfirmChange(value)
        }
    }

    @discardableResult
    func submit() -> Task<Void, Never>? {
        let current = state
        guard !current.isSubmitting, !current.invalidLink else { return nil }
        let passwordError = Validators.password(current.password)?.text
        let confirmError: String? = current.confirm != current.password ? ValidationMessage.passwordMismatch.text : nil
        guard passwordError == nil, confirmError == nil else {
            state.passwordError = passwordError
            state.confirmError = confirmError
            return nil
        }
        state.isSubmitting = true
        state.errorMessage = nil
        let token = self.token
        return Task { [weak self] in
            guard let self else { return }
            do {
                try await self.auth.resetPassword(token: token, password: current.password)
                var next = self.state
                next.isSubmitting = false
                next.isDone = true
                next.password = ""
                next.confirm = ""
                self.state = next
            } catch {
                var next = self.state
                next.isSubmitting = false
                next.errorMessage = ErrorMapper.message(for: error)
                self.state = next
            }
        }
    }
}

// MARK: - Code de vérification de l'e-mail (6 chiffres)

nonisolated enum VerifyEmailField: Hashable, Sendable {
    case code
}

nonisolated struct VerifyEmailState: Equatable, Sendable {
    var email: String = ""
    var code: String = ""
    var codeError: String? = nil
    var isSubmitting: Bool = false
    var isResending: Bool = false
    /// Message déjà complété des essais restants (« 2 essais restants. »).
    var errorMessage: String? = nil
    var remainingAttempts: Int? = nil
    /// Secondes avant de pouvoir redemander un code (0 = disponible).
    var cooldownSeconds: Int = 0
    var resent: Bool = false
    var verified: Bool = false

    var canSubmit: Bool { !isSubmitting && code.count == 6 }
    var canResend: Bool { !isResending && cooldownSeconds == 0 }

    /// Vérification ou renvoi en cours, ou code commencé : glisser la feuille ne la ferme plus (« Plus tard » et
    /// « Fermer » restent possibles).
    var keepsSheetOpen: Bool { isSubmitting || isResending || (!verified && !code.isEmpty) }
}

/// Vérification de l'e-mail par le code reçu — portage de `VerifyEmailViewModel` : soumission automatique au
/// 6e chiffre, code effacé s'il est faux, renvoi limité par un compte à rebours (60 s, ou le délai du serveur).
/// Le compte à rebours suit une échéance (`now`) et non des secondes comptées : juste après un passage en arrière-plan.
final class VerifyEmailViewModel: ObservableObject {
    /// Le serveur impose 60 s entre deux envois (Android : RESEND_COOLDOWN_S).
    static let resendCooldownSeconds = 60

    @Published private(set) var state: VerifyEmailState

    private let auth: AuthRepository
    private let now: () -> Date
    private let tick: @Sendable () async throws -> Void
    private var cooldownDeadline: Date?
    private var cooldownTask: Task<Void, Never>?

    /// `startsWithCooldown` : un code vient de partir (inscription) — Android l'applique toujours ; ici, la feuille
    /// ouverte plus tard (bandeau du Profil) laisse redemander un code tout de suite, le serveur gardant sa limite.
    /// `now` / `tick` : horloge et attente d'une seconde, remplaçables par les tests.
    init(
        auth: AuthRepository,
        startsWithCooldown: Bool = true,
        now: @escaping () -> Date = { Date() },
        tick: @escaping @Sendable () async throws -> Void = { try await Task.sleep(nanoseconds: 1_000_000_000) }
    ) {
        self.auth = auth
        self.now = now
        self.tick = tick
        state = VerifyEmailState(email: auth.user?.email ?? "")
        if startsWithCooldown {
            startCooldown(Self.resendCooldownSeconds)
        }
    }

    /// Chiffres seulement (claviers arabe et persan ramenés en ASCII), 6 au plus ; envoi automatique au 6e.
    @discardableResult
    func onCodeChange(_ value: String) -> Task<Void, Never>? {
        let digits = String(Validators.asciiDigits(value).prefix(6))
        var next = state
        next.code = digits
        next.codeError = nil
        next.errorMessage = nil
        next.resent = false
        state = next
        return digits.count == 6 ? submit() : nil
    }

    @discardableResult
    func submit() -> Task<Void, Never>? {
        let current = state
        guard !current.isSubmitting else { return nil }
        if let error = Validators.code6(current.code) {
            state.codeError = error.text
            return nil
        }
        state.isSubmitting = true
        state.errorMessage = nil
        return Task { [weak self] in
            guard let self else { return }
            do {
                try await self.auth.confirmEmail(code: current.code)
                var next = self.state
                next.isSubmitting = false
                next.verified = true
                self.state = next
                self.stopCooldown()
            } catch {
                let apiError = error as? APIError
                var next = self.state
                next.isSubmitting = false
                next.errorMessage = ErrorMapper.messageWithAttemptsHint(for: error)
                next.remainingAttempts = apiError?.remainingAttempts
                if apiError?.code == "incorrectCode" {
                    next.code = ""
                }
                self.state = next
            }
        }
    }

    /// Nouveau code (ignoré pendant le compte à rebours) ; refus du serveur avec délai → compte à rebours de ce délai.
    @discardableResult
    func resend() -> Task<Void, Never>? {
        guard state.canResend else { return nil }
        var next = state
        next.isResending = true
        next.errorMessage = nil
        next.resent = false
        state = next
        return Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.auth.resendVerificationCode()
                var sent = self.state
                sent.isResending = false
                sent.resent = true
                sent.remainingAttempts = nil
                sent.code = ""
                self.state = sent
                self.startCooldown(Self.resendCooldownSeconds)
            } catch {
                var failed = self.state
                failed.isResending = false
                failed.errorMessage = ErrorMapper.message(for: error)
                self.state = failed
                if let retry = (error as? APIError)?.retryAfterSeconds, retry > 0 {
                    self.startCooldown(retry)
                }
            }
        }
    }

    /// Secondes restantes d'après l'échéance (relu à chaque seconde, et par les tests).
    @discardableResult
    func refreshCooldown() -> Int {
        guard let deadline = cooldownDeadline else { return 0 }
        let remaining = max(0, Int(deadline.timeIntervalSince(now()).rounded(.up)))
        if state.cooldownSeconds != remaining {
            state.cooldownSeconds = remaining
        }
        if remaining == 0 {
            cooldownDeadline = nil
        }
        return remaining
    }

    private func startCooldown(_ seconds: Int) {
        cooldownTask?.cancel()
        cooldownDeadline = now().addingTimeInterval(TimeInterval(seconds))
        state.cooldownSeconds = seconds
        let tick = self.tick
        cooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await tick()
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                if self.refreshCooldown() == 0 { return }
            }
        }
    }

    private func stopCooldown() {
        cooldownTask?.cancel()
        cooldownTask = nil
        cooldownDeadline = nil
        state.cooldownSeconds = 0
    }
}
