import SwiftUI

/// Écran provisoire d'un onglet (phase 0 : la coquille). Chaque phase remplace un onglet par son
/// vrai écran. L'identifiant `screen.<onglet>` sert au tour automatique de captures.
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
            #if DEBUG
            if tab == .account {
                NavigationLink {
                    DesignShowcaseView()
                } label: {
                    Text(verbatim: "Design system")
                        .weydaText(.labelLarge)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("open.showcase")
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeydaColor.background)
        .navigationTitle(tab.title)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(tab.rawValue)")
    }
}
