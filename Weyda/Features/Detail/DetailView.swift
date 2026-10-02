// FICHIER D'ATTENTE (SHELL) — remplacé par l'agent DETAIL.
import SwiftUI

struct DetailView: View {
    let idOrSlug: String

    init(idOrSlug: String) {
        self.idOrSlug = idOrSlug
    }

    var body: some View {
        ComingSoonView(route: .detail(idOrSlug: idOrSlug))
    }
}
