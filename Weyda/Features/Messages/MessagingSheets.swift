import SwiftUI
import UIKit

// Feuilles de la messagerie — portage de MessagingDialogs.kt (Android) : montant d'une offre et premier message au
// vendeur. Utilisées par la fiche d'une annonce ET par le fil. L'appelant leur pose son identifiant de tour
// (`detail.offer.sheet`, `detail.contact.sheet`, `chat.offer.sheet`) ; les boutons portent les leurs.

// MARK: - Montant d'une offre

/// Montant d'une offre (nouvelle offre ou contre-offre) : champ numérique (chiffres latins, `Validators.asciiDigits`),
/// prix demandé et offre en cours rappelés, validation 1…9 999 999 999 (`OfferDialogState`), montant groupé sous le
/// champ pour relire les zéros, bouton occupé pendant l'envoi, erreur traduite sous le champ. Montant saisi : un
/// glissement ne ferme plus la feuille (Annuler reste possible), comme `dismissOnClickOutside` d'Android.
struct OfferAmountSheet: View {
    private let title: String
    private let askingPrice: Double?
    private let currentOffer: Double?
    @Binding private var amount: String
    private let isBusy: Bool
    private let errorMessage: String?
    private let onConfirm: () -> Void
    private let onCancel: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    /// Le temps que la feuille finisse de monter avant d'ouvrir le clavier.
    private static let focusDelay: UInt64 = 450_000_000
    private static let fieldHeight: CGFloat = 56

    init(
        title: String,
        askingPrice: Double?,
        currentOffer: Double?,
        amount: Binding<String>,
        isBusy: Bool,
        errorMessage: String?,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.askingPrice = askingPrice
        self.currentOffer = currentOffer
        self._amount = amount
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _text = State(initialValue: amount.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WeydaSpace.xl) {
                    if askingPrice != nil || currentOffer != nil {
                        context
                    }
                    amountField
                    sendButton
                }
                .padding(WeydaSpace.screen)
                .frame(maxWidth: WeydaSize.formMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WeydaColor.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel, action: onCancel)
                        .disabled(isBusy)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isBusy || !text.isEmpty)
        .task {
            try? await Task.sleep(nanoseconds: Self.focusDelay)
            isFocused = true
        }
        .onChange(of: text) { value in
            textChanged(value)
        }
        .onChange(of: amount) { value in
            if value != text {
                text = value
            }
        }
        .onChange(of: errorMessage) { message in
            if let message {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }

    // MARK: Rappels

    /// « Prix demandé » et « Offre actuelle » (contre-offre), alignés comme sur un reçu.
    private var context: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        return VStack(spacing: 0) {
            if let askingPrice {
                OfferContextRow(title: L10n.offerAskingPrice, value: Format.amount(askingPrice))
            }
            if askingPrice != nil && currentOffer != nil {
                Divider()
            }
            if let currentOffer {
                OfferContextRow(title: L10n.offerCurrent, value: Format.amount(currentOffer))
            }
        }
        .padding(.horizontal, WeydaSpace.md)
        .background(WeydaColor.surface, in: shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
    }

    // MARK: Champ

    private var amountField: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.field, style: .continuous)
        return VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            Text(L10n.offerYourOffer)
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .accessibilityHidden(true)
            HStack(spacing: WeydaSpace.sm) {
                TextField(L10n.offerAmountPlaceholder, text: $text)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
                    .weydaText(.titleLarge)
                    .focused($isFocused)
                    .accessibilityLabel(L10n.offerYourOffer)
                    .accessibilityIdentifier("offer.amount")
                Text(L10n.currencyDa)
                    .weydaText(.titleSmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, WeydaSpace.md)
            .frame(minHeight: Self.fieldHeight)
            .background(WeydaColor.surface, in: shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: isFocused || displayedError != nil ? 1.5 : 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
            }
            supporting
        }
    }

    @ViewBuilder
    private var supporting: some View {
        if let error = displayedError {
            Text(error)
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.error)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("offer.error")
        } else {
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                // Le montant groupé (« 3 050 000 DA ») : un zéro de trop se voit avant l'envoi.
                if let value = OfferDialogState.parse(text) {
                    Text(Format.amount(Double(value)))
                        .weydaText(.labelLarge)
                        .foregroundStyle(WeydaColor.primary)
                }
                Text(helper)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Erreur du serveur ou du réseau, sinon « Montant invalide. » dès qu'une saisie ne passe pas la borne.
    private var displayedError: String? {
        if let errorMessage { return errorMessage }
        guard !text.isEmpty, OfferDialogState.parse(text) == nil else { return nil }
        return L10n.offerInvalidAmount
    }

    private var helper: String {
        currentOffer == nil ? L10n.offerHelper : L10n.chatUiCounterHelper
    }

    private var borderColor: Color {
        if displayedError != nil { return WeydaColor.error }
        return isFocused ? WeydaColor.primary : WeydaPalette.cardOutline
    }

    // MARK: Envoi

    private var isValid: Bool {
        OfferDialogState.parse(text) != nil
    }

    private var sendButton: some View {
        Button(action: confirm) {
            ZStack {
                Text(L10n.offerSend)
                    .weydaText(.titleSmall)
                    .foregroundStyle(isValid ? WeydaColor.onPrimary : WeydaColor.onSurfaceVariant)
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView()
                        .tint(WeydaColor.onPrimary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WeydaColor.primary)
        // Pendant l'envoi, le bouton garde sa couleur ; `confirm` ignore un second appui.
        .disabled(!isValid && !isBusy)
        .accessibilityLabel(isBusy ? L10n.loading : L10n.offerSend)
        .accessibilityIdentifier("offer.send")
    }

    private func confirm() {
        guard !isBusy, isValid else { return }
        onConfirm()
    }

    /// Chiffres latins seulement, 10 au plus (le ViewModel applique la même règle).
    private func textChanged(_ value: String) {
        let clean = OfferDialogState.sanitize(value)
        if clean != value {
            text = clean
            return
        }
        if clean != amount {
            amount = clean
        }
    }
}

/// Une ligne du rappel : libellé au début, montant à la fin.
private struct OfferContextRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: WeydaSpace.sm) {
            Text(title)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
            Spacer(minLength: WeydaSpace.sm)
            Text(value)
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.onSurface)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: WeydaSize.touchTarget)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Premier message au vendeur

/// Premier message au vendeur (`POST /api/conversations`) : l'annonce rappelée, les modèles de message d'Android (un
/// appui remplit le champ), champ multiligne de 2000 caractères (compteur près de la limite), envoi. Message commencé :
/// un glissement ne ferme plus la feuille (Annuler reste possible).
struct ContactSellerSheet: View {
    private let listingTitle: String
    @Binding private var message: String
    private let isBusy: Bool
    private let errorMessage: String?
    private let onSend: () -> Void
    private let onCancel: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    private static let templates: [String] = [L10n.contactTemplate1, L10n.contactTemplate2, L10n.contactTemplate3]

    init(
        listingTitle: String,
        message: Binding<String>,
        isBusy: Bool,
        errorMessage: String?,
        onSend: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.listingTitle = listingTitle
        self._message = message
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.onSend = onSend
        self.onCancel = onCancel
        _text = State(initialValue: message.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WeydaSpace.xl) {
                    if let title = TextCheck.nonBlank(listingTitle) {
                        listingContext(title)
                    }
                    suggestions
                    messageField
                    sendButton
                }
                .padding(WeydaSpace.screen)
                .frame(maxWidth: WeydaSize.formMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WeydaColor.background)
            .navigationTitle(L10n.contactSendMessage)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel, action: onCancel)
                        .disabled(isBusy)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isBusy || !TextCheck.isBlank(text))
        .onChange(of: text) { value in
            textChanged(value)
        }
        .onChange(of: message) { value in
            if value != text {
                text = value
            }
        }
        .onChange(of: errorMessage) { message in
            if let message {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }

    // MARK: Annonce

    private func listingContext(_ title: String) -> some View {
        HStack(alignment: .top, spacing: WeydaSpace.sm) {
            Image(systemName: "tag")
                .font(.body)
                .foregroundStyle(WeydaColor.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                Text(L10n.suggestionListing)
                    .weydaText(.labelMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                Text(title)
                    .weydaText(.titleSmall)
                    .foregroundStyle(WeydaColor.onSurface)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Modèles

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.sm) {
            Text(L10n.chatUiSuggestions)
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .accessibilityAddTraits(.isHeader)
            ForEach(Self.templates.indices, id: \.self) { index in
                templateButton(index: index)
            }
        }
    }

    private func templateButton(index: Int) -> some View {
        let template = Self.templates[index]
        let selected = text == template
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.field, style: .continuous)
        return Button {
            text = template
        } label: {
            HStack(spacing: WeydaSpace.sm) {
                Image(systemName: "text.bubble")
                    .font(.body)
                    .foregroundStyle(WeydaColor.primary)
                    .accessibilityHidden(true)
                Text(template)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurface)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WeydaColor.primary)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, WeydaSpace.md)
            .padding(.vertical, WeydaSpace.sm)
            .frame(minHeight: WeydaSize.touchTarget)
            .background(WeydaColor.surface, in: shape)
            .overlay {
                shape.strokeBorder(selected ? WeydaColor.primary : WeydaPalette.cardOutline, lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(WeydaPressStyle())
        .disabled(isBusy)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("contact.template.\(index + 1)")
    }

    // MARK: Message

    private var messageField: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.field, style: .continuous)
        let count = text.utf16.count
        return VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            TextField(L10n.chatMessagePlaceholder, text: $text, axis: .vertical)
                .lineLimit(4...8)
                .weydaText(.bodyLarge)
                .focused($isFocused)
                .disabled(isBusy)
                .accessibilityIdentifier("contact.message")
                .padding(WeydaSpace.md)
                .background(WeydaColor.surface, in: shape)
                .overlay {
                    shape.strokeBorder(fieldBorder, lineWidth: isFocused || errorMessage != nil ? 1.5 : 1)
                }
            if let errorMessage {
                Text(errorMessage)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("contact.error")
            } else if count >= ChatMetrics.counterThreshold {
                Text(L10n.postCharCount(count, ChatState.messageMax))
                    .weydaText(.labelSmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var fieldBorder: Color {
        if errorMessage != nil { return WeydaColor.error }
        return isFocused ? WeydaColor.primary : WeydaPalette.cardOutline
    }

    // MARK: Envoi

    private var canSend: Bool {
        !TextCheck.isBlank(text)
    }

    private var sendButton: some View {
        Button(action: send) {
            ZStack {
                Label(L10n.chatSend, systemImage: "paperplane.fill")
                    .weydaText(.titleSmall)
                    .foregroundStyle(canSend ? WeydaColor.onPrimary : WeydaColor.onSurfaceVariant)
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView()
                        .tint(WeydaColor.onPrimary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WeydaColor.primary)
        .disabled(!canSend && !isBusy)
        .accessibilityLabel(isBusy ? L10n.loading : L10n.chatSend)
        .accessibilityIdentifier("contact.send")
    }

    private func send() {
        guard !isBusy, canSend else { return }
        onSend()
    }

    /// Coupé à 2000 unités UTF-16 comme le serveur (et non refusé : un collage trop long disparaissait sans explication).
    private func textChanged(_ value: String) {
        let capped = RepositorySupport.truncatedUTF16(value, max: ChatState.messageMax)
        if capped != value {
            text = capped
            return
        }
        if capped != message {
            message = capped
        }
    }
}
