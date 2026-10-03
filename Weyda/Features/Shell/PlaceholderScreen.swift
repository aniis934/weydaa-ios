import SwiftUI

/// Écran provisoire d'un onglet (la coquille). Chaque phase remplace un onglet par son vrai écran. L'identifiant
/// `screen.<onglet>` sert au tour automatique de captures. (Profil, visiteur ou membre : `ProfileView`.)
struct PlaceholderScreen: View {
    let tab: AppTab

    var body: some View {
        VStack(spacing: WeydaSpace.lg) {
            Image(systemName: tab.symbol)
                .font(.system(size: WeydaSize.stateIcon, weight: .regular))
                .foregroundStyle(WeydaColor.primary)
                .accessibilityHidden(true)
            Text(tab.title)
                .weydaText(.titleLarge)
                .foregroundStyle(WeydaColor.onBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeydaColor.background)
        .navigationTitle(tab.title)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(tab.rawValue)")
    }
}
