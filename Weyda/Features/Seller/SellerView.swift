// FICHIER D'ATTENTE (SHELL) — remplacé par l'agent DETAIL.
import SwiftUI

struct SellerView: View {
    let id: String

    init(id: String) {
        self.id = id
    }

    var body: some View {
        ComingSoonView(route: .seller(id: id))
    }
}
