import SwiftUI

/// Écran d'attente des routes des phases suivantes (messagerie, compte, dépôt) : la navigation est branchée
/// de bout en bout dès la phase 2, chaque phase remplace sa destination dans `RouteDestination`.
struct ComingSoonView: View {
    private let route: AppRoute

    init(route: AppRoute) {
        self.route = route
    }

    var body: some View {
        VStack(spacing: WeydaSpace.lg) {
            Image(systemName: route.symbol)
                .font(.system(size: WeydaSize.stateIcon, weight: .regular))
                .foregroundStyle(WeydaColor.primary)
                .accessibilityHidden(true)
            Text(route.title)
                .weydaText(.titleLarge)
                .foregroundStyle(WeydaColor.onBackground)
                .multilineTextAlignment(.center)
        }
        .padding(WeydaSpace.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeydaColor.background)
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.comingSoon")
    }
}
