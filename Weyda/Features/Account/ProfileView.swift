import Combine
import SwiftUI

/// Racine de l'onglet Profil (interface fixée de la phase 3) — portage de `ProfileRoute` et de `GuestProfile`
/// (ProfileScreen.kt). Membre connecté : en-tête, statistiques, menu du compte ; visiteur : invitation à se
/// connecter ou à créer un compte, puis ce qui ne demande pas de compte (langue, contact, informations légales).
struct ProfileView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionManager

    init() {}

    var body: some View {
        if let user = session.user {
            ProfileHost(
                model: ProfileViewModel(
                    users: container.users,
                    auth: container.auth,
                    userUpdates: session.$user.eraseToAnyPublisher()
                )
            )
            // Un autre compte = un autre ViewModel : rien ne passe d'un utilisateur au suivant.
            .id(user.id)
        } else {
            GuestProfileScreen()
        }
    }
}

/// Possède le ViewModel du profil connecté.
private struct ProfileHost: View {
    @StateObject private var model: ProfileViewModel
    @EnvironmentObject private var router: AppRouter

    init(model: @autoclosure @escaping () -> ProfileViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        ProfileScreen(
            state: model.state,
            onVerifyEmail: { router.requestEmailVerification() },
            onLogout: { model.logout() }
        )
        // `@MainActor` explicite : juste, que le SDK fasse hériter cette fermeture de l'acteur de la vue ou non.
        .refreshable { @MainActor [model] in
            await model.pullToRefresh()
        }
    }
}

/// Profil d'un membre, sans état propre (hors confirmation de la déconnexion) : liste groupée comme les Réglages
/// d'iOS — en-tête, bandeau « vérifiez votre e-mail », activité, puis le menu du compte.
struct ProfileScreen: View {
    private let state: ProfileState
    private let onVerifyEmail: () -> Void
    private let onLogout: () -> Void
    @State private var confirmsLogout: Bool = false

    init(state: ProfileState, onVerifyEmail: @escaping () -> Void, onLogout: @escaping () -> Void) {
        self.state = state
        self.onVerifyEmail = onVerifyEmail
        self.onLogout = onLogout
    }

    var body: some View {
        List {
            if let user = state.user {
                Section {
                    ProfileHeader(user: user)
                        .listRowBackground(WeydaColor.surface)
                }
                if !user.emailVerified {
                    Section {
                        VerifyEmailBanner(onVerifyEmail: onVerifyEmail)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                if let message = state.errorMessage {
                    Section {
                        ErrorBanner(message: message)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                statsSection
                activitySection
                accountSection(user)
                AccountLanguageSection()
                helpSection
                logoutSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(WeydaColor.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            OfflineBanner()
        }
        .navigationTitle(L10n.profileTitle)
        .navigationBarTitleDisplayMode(.large)
        .alert(L10n.profileLogoutConfirmTitle, isPresented: $confirmsLogout) {
            Button(L10n.profileLogout, role: .destructive) {
                onLogout()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.profileLogoutConfirmBody)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.profile")
    }

    // MARK: - Sections

    /// « Mon activité » : squelette pendant le premier chargement, rien si les statistiques sont illisibles
    /// (le message d'erreur est affiché plus haut), comme Android.
    @ViewBuilder
    private var statsSection: some View {
        if let stats = state.stats {
            Section {
                ProfileStatsGrid(stats: stats)
                    .listRowBackground(WeydaColor.surface)
            } header: {
                Text(L10n.profileStatsTitle)
            }
        } else if state.isRefreshing {
            Section {
                ProfileStatsSkeleton()
                    .listRowBackground(WeydaColor.surface)
            } header: {
                Text(L10n.profileStatsTitle)
            }
        }
    }

    /// Mes annonces, puis les écrans des phases suivantes (favoris, alertes : phase 6 ; notifications : phase 5).
    private var activitySection: some View {
        Section {
            menuLink(.myListings, title: L10n.profileMyListings, symbol: AppRoute.myListings.symbol, id: "myListings")
            menuLink(.favorites, title: L10n.profileFavorites, symbol: AppRoute.favorites.symbol, id: "favorites")
            menuLink(.savedSearches, title: L10n.profileAlerts, symbol: AppRoute.savedSearches.symbol, id: "alerts")
            menuLink(.notifications, title: L10n.notificationsTitle, symbol: AppRoute.notifications.symbol, id: "notifications")
        }
    }

    /// Compte : profil, mot de passe (pas pour un compte créé avec Google ou Apple), données personnelles. La langue
    /// a sa propre section (sa note explique le passage par les Réglages).
    private func accountSection(_ user: User) -> some View {
        Section {
            menuLink(.editProfile, title: L10n.profileEdit, symbol: AppRoute.editProfile.symbol, id: "editProfile")
            if user.hasPassword {
                menuLink(.changePassword, title: L10n.profileChangePassword, symbol: AppRoute.changePassword.symbol, id: "changePassword")
            }
            menuLink(.accountData, title: L10n.profileAccountData, symbol: AppRoute.accountData.symbol, id: "accountData")
            // Phase 5 (App Store 1.2) : la liste de ceux que j'ai bloqués, avec « Débloquer ».
            menuLink(.blockedUsers, title: L10n.blockedUsersTitle, symbol: AppRoute.blockedUsers.symbol, id: "blockedUsers")
        }
    }

    private var helpSection: some View {
        Section {
            menuLink(.contact, title: L10n.contactTitle, symbol: AppRoute.contact.symbol, id: "contact")
            menuLink(.about, title: L10n.legalTitle, symbol: AppRoute.about.symbol, id: "about")
        }
    }

    private var logoutSection: some View {
        Section {
            Button {
                confirmsLogout = true
            } label: {
                AccountMenuRow(title: L10n.profileLogout, systemImage: "rectangle.portrait.and.arrow.right", destructive: true)
            }
            .listRowBackground(WeydaColor.surface)
            .accessibilityIdentifier("profile.logout")
        }
    }

    private func menuLink(_ route: AppRoute, title: String, symbol: String, id: String) -> some View {
        NavigationLink(value: route) {
            AccountMenuRow(title: title, systemImage: symbol)
        }
        .listRowBackground(WeydaColor.surface)
        .accessibilityIdentifier("profile.\(id)")
    }
}

// MARK: - En-tête

/// Avatar (ou initiale), nom, e-mail, badges (e-mail vérifié ou non, vendeur recommandé), ancienneté.
private struct ProfileHeader: View {
    let user: User

    private static let avatarSide: CGFloat = 64

    var body: some View {
        HStack(alignment: .center, spacing: WeydaSpace.lg) {
            ProfileAvatar(user: user, side: Self.avatarSide)
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                Text(user.displayName)
                    .weydaText(.titleLarge)
                    .foregroundStyle(WeydaColor.onSurface)
                    .lineLimit(2)
                // Une adresse e-mail se lit de gauche à droite, même dans une interface en arabe.
                Text(Format.ltrIsolate(user.email))
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProfileBadges(user: user)
                    .padding(.top, WeydaSpace.xs)
                if let since = user.memberSince {
                    Text(L10n.memberSince(Format.monthYear(since)))
                        .weydaText(.bodySmall)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .padding(.top, WeydaSpace.xxs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, WeydaSpace.sm)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.header")
    }
}

/// Photo du compte, ou son initiale sur la pastille de la marque.
private struct ProfileAvatar: View {
    let user: User
    let side: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(WeydaColor.primaryContainer)
            if let avatar = user.avatarUrl {
                RemoteImage(urlString: avatar)
            } else {
                Text(initial)
                    .weydaText(.headlineSmall)
                    .foregroundStyle(WeydaColor.onPrimaryContainer)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: String {
        String(user.displayName.prefix(1)).uppercased()
    }
}

/// Badges d'une ligne ; empilés si le texte agrandi ne tient plus.
private struct ProfileBadges: View {
    let user: User

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WeydaSpace.md) {
                badges
            }
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                badges
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if user.emailVerified {
            ProfileBadge(systemImage: "checkmark.seal.fill", text: L10n.profileVerified, tint: WeydaColor.primary)
        } else {
            ProfileBadge(systemImage: "exclamationmark.triangle.fill", text: L10n.profileUnverified, tint: WeydaColor.tertiary)
        }
        if user.isRecommended {
            ProfileBadge(systemImage: "star.fill", text: L10n.profileRecommended, tint: WeydaColor.tertiary)
        }
    }
}

private struct ProfileBadge: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: WeydaSpace.xs) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text(text)
                .weydaText(.labelSmall)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
    }
}

// MARK: - Statistiques

/// Une statistique du compte (cellule de la grille).
nonisolated struct ProfileStat: Identifiable, Hashable, Sendable {
    let id: String
    let value: Int
    let label: String
}

/// Les vues en grand chiffre, puis six compteurs en grille (actives, en attente, vendues, expirées, favoris
/// reçus, messages reçus) — « gros chiffres, peu de mots ».
private struct ProfileStatsGrid: View {
    let stats: UserStats

    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: WeydaSpace.sm, alignment: .top),
        GridItem(.flexible(), spacing: WeydaSpace.sm, alignment: .top),
        GridItem(.flexible(), spacing: WeydaSpace.sm, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.sm) {
                Text(Format.count(stats.totalViews))
                    .weydaText(.headlineMedium)
                    .foregroundStyle(WeydaColor.primary)
                Text(L10n.statViews)
                    .weydaText(.labelLarge)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.statViews)
            .accessibilityValue(Format.count(stats.totalViews))
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: WeydaSpace.sm) {
                ForEach(cells) { cell in
                    ProfileStatCell(stat: cell)
                }
            }
        }
        .padding(.vertical, WeydaSpace.sm)
        .accessibilityIdentifier("profile.stats")
    }

    private var cells: [ProfileStat] {
        [
            ProfileStat(id: "active", value: stats.activeCount, label: L10n.statActive),
            ProfileStat(id: "pending", value: stats.pendingCount, label: L10n.statPending),
            ProfileStat(id: "sold", value: stats.soldCount, label: L10n.statSold),
            ProfileStat(id: "expired", value: stats.expiredCount, label: L10n.accountStatExpired),
            ProfileStat(id: "favorites", value: stats.favoritesReceived, label: L10n.statFavorites),
            ProfileStat(id: "messages", value: stats.messagesReceived, label: L10n.statMessages),
        ]
    }
}

private struct ProfileStatCell: View {
    let stat: ProfileStat

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
            Text(Format.count(stat.value))
                .weydaText(.titleLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stat.label)
                .weydaText(.labelSmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(WeydaSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeydaColor.surfaceContainer, in: RoundedRectangle(cornerRadius: WeydaRadius.thumb, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.label)
        .accessibilityValue(Format.count(stat.value))
    }
}

/// Fantôme de la grille pendant le premier chargement (lu une fois « Chargement… »).
private struct ProfileStatsSkeleton: View {
    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: WeydaSpace.sm),
        GridItem(.flexible(), spacing: WeydaSpace.sm),
        GridItem(.flexible(), spacing: WeydaSpace.sm),
    ]
    private static let heroWidth: CGFloat = 120
    private static let heroHeight: CGFloat = 28
    private static let cellHeight: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            SkeletonBlock(width: Self.heroWidth, height: Self.heroHeight)
            LazyVGrid(columns: Self.columns, spacing: WeydaSpace.sm) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonBlock(height: Self.cellHeight, radius: WeydaRadius.thumb)
                }
            }
        }
        .padding(.vertical, WeydaSpace.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.loading)
    }
}

// MARK: - Visiteur

/// Onglet Profil d'un visiteur — `GuestProfile` (Android) : connexion ou inscription (feuille de connexion,
/// agent AUTH), puis la langue, « Nous contacter » et les informations légales, consultables sans compte.
private struct GuestProfileScreen: View {
    @EnvironmentObject private var router: AppRouter

    init() {}

    var body: some View {
        List {
            Section {
                GuestWelcome(
                    onLogin: { router.requestLogin() },
                    onRegister: { router.authFlow = .register }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            AccountLanguageSection()
            Section {
                NavigationLink(value: AppRoute.contact) {
                    AccountMenuRow(title: L10n.contactTitle, systemImage: AppRoute.contact.symbol)
                }
                .listRowBackground(WeydaColor.surface)
                .accessibilityIdentifier("profile.contact")
                NavigationLink(value: AppRoute.about) {
                    AccountMenuRow(title: L10n.legalTitle, systemImage: AppRoute.about.symbol)
                }
                .listRowBackground(WeydaColor.surface)
                .accessibilityIdentifier("open.about")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(WeydaColor.background)
        .navigationTitle(AppTab.account.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(AppTab.account.rawValue)")
    }
}

/// La tuile de l'icône de l'app, l'invitation, « Se connecter » et « Créer un compte » (Android : LoginRequired).
private struct GuestWelcome: View {
    let onLogin: () -> Void
    let onRegister: () -> Void

    private static let tileSide: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            WeydaTile(size: Self.tileSide)
            Text(L10n.loginRequiredTitle)
                .weydaText(.headlineSmall)
                .foregroundStyle(WeydaColor.onBackground)
                .multilineTextAlignment(.center)
                .padding(.top, WeydaSpace.lg)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.loginRequiredBody)
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
            .accessibilityIdentifier("profile.login")
            Button(action: onRegister) {
                Text(L10n.authRegisterLink)
                    .weydaText(.labelLarge)
                    .foregroundStyle(WeydaColor.primary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(WeydaColor.primary)
            .padding(.top, WeydaSpace.md)
            .accessibilityIdentifier("profile.register")
        }
        .frame(maxWidth: WeydaSize.formMaxWidth)
        .padding(.horizontal, WeydaSpace.lg)
        .padding(.vertical, WeydaSpace.xl)
        .frame(maxWidth: .infinity)
    }
}
