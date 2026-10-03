import Foundation

/// Formats affichés — portage de `ui/common/Format.kt` (Android).
///
/// Toujours en chiffres LATINS, y compris en arabe : la locale par défaut est `WeydaLocale.formatting`
/// (comme `LatinDigits` sur Android, et comme le site qui force `ar-DZ`). Les textes (« DA », « Gratuit »…)
/// viennent du catalogue via `L10n`. La locale et le fuseau sont des paramètres : les tests les fixent,
/// l'app garde les valeurs par défaut.
nonisolated enum Format {

    // MARK: - Prix

    /// « 12 500 DA », « Gratuit » ou « Prix sur demande » — miroir de `formatPrice`.
    static func price(_ price: Double?, type: PriceType, locale: Locale = WeydaLocale.formatting) -> String {
        if type == .free { return L10n.priceFree }
        guard let price else { return L10n.priceOnRequest }
        return L10n.priceDzd(integer(price, locale: locale))
    }

    /// Montant d'une offre, sans dépendre du type de prix de l'annonce — miroir de `formatAmount`.
    static func amount(_ amount: Double, locale: Locale = WeydaLocale.formatting) -> String {
        L10n.priceDzd(integer(amount, locale: locale))
    }

    /// Mention « Négociable » posée à côté d'un prix renseigné (`PriceText`, Android) ; nil sinon.
    static func negotiableLabel(price: Double?, type: PriceType) -> String? {
        guard type == .negotiable, price != nil else { return nil }
        return L10n.priceNegotiable
    }

    // MARK: - Nombres

    /// Entier groupé par milliers selon la locale (« 12 500 », « 12.500 », « 12,500 »), tronqué comme le
    /// `toLong()` d'Android. Une valeur non finie ou démesurée donne une chaîne vide (jamais de plantage).
    static func integer(_ value: Double, locale: Locale = WeydaLocale.formatting) -> String {
        let truncated = value.rounded(.towardZero)
        guard truncated.isFinite, truncated > -9.2e18, truncated < 9.2e18 else { return "" }
        return count(Int(truncated), locale: locale)
    }

    /// Compteur groupé par milliers (vues, annonces, avis) en chiffres latins.
    static func count(_ value: Int, locale: Locale = WeydaLocale.formatting) -> String {
        WeydaLocale.visibleGrouping(latinDigits(value.formatted(.number.locale(locale))))
    }

    /// Nombre décimal d'un attribut (surface, cylindrée…), trois décimales au plus — comme
    /// `NumberFormat.getInstance()` sur l'écran de relecture Android.
    static func decimal(_ value: Double, locale: Locale = WeydaLocale.formatting) -> String {
        guard value.isFinite else { return "" }
        return WeydaLocale.visibleGrouping(latinDigits(value.formatted(.number.precision(.fractionLength(0...3)).locale(locale))))
    }

    /// Pastille plafonnée : « 9+ » pour l'onglet Messages, « 99+ » pour la cloche (Android).
    static func badge(_ count: Int, cap: Int) -> String {
        count > cap ? "\(cap)+" : "\(max(count, 0))"
    }

    // MARK: - Dates

    /// « maintenant », « il y a 3 min », « il y a 2 h », « hier », « il y a 4 jours », puis la date courte
    /// (« 12 sept. », l'année en plus si elle diffère) — miroir de `relativeTime` (DateUtils, style abrégé).
    /// Le repère est plafonné à maintenant : une horloge serveur en avance de quelques secondes afficherait
    /// sinon « dans 0 min ». nil → chaîne vide.
    static func relativeTime(
        _ date: Date?,
        now: Date = Date(),
        locale: Locale = WeydaLocale.formatting,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date else { return "" }
        let instant = min(date, now)
        let elapsed = now.timeIntervalSince(instant)
        if elapsed >= 7 * 86_400 {
            let calendar = gregorian(timeZone)
            let sameYear = calendar.component(.year, from: instant) == calendar.component(.year, from: now)
            return formatted(instant, template: sameYear ? "dMMM" : "dMMMy", locale: locale, timeZone: timeZone)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        let text: String
        if elapsed < 60 {
            // Android écrirait « il y a 0 min » ; le système propose « maintenant ».
            text = formatter.localizedString(fromTimeInterval: 0)
        } else if elapsed < 3_600 {
            text = formatter.localizedString(from: DateComponents(minute: -Int(elapsed / 60)))
        } else if elapsed < 86_400 {
            text = formatter.localizedString(from: DateComponents(hour: -Int(elapsed / 3_600)))
        } else {
            // Jours de CALENDRIER (comme DateUtils) : « hier » dès la veille, « avant-hier » si la langue l'a.
            text = formatter.localizedString(from: DateComponents(day: -dayDistance(from: instant, to: now, timeZone: timeZone)))
        }
        return latinDigits(text)
    }

    /// Date moyenne localisée (« 12 sept. 2026 ») — miroir de `formatDate` (FormatStyle.MEDIUM).
    static func date(_ date: Date?, locale: Locale = WeydaLocale.formatting, timeZone: TimeZone = .current) -> String {
        guard let date else { return "" }
        let formatter = makeFormatter(locale: locale, timeZone: timeZone)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return latinDigits(formatter.string(from: date))
    }

    /// Mois et année (« septembre 2026 », « Membre depuis … ») — miroir de `formatMonthYear`.
    static func monthYear(_ date: Date?, locale: Locale = WeydaLocale.formatting, timeZone: TimeZone = .current) -> String {
        guard let date else { return "" }
        return formatted(date, template: "MMMMy", locale: locale, timeZone: timeZone)
    }

    /// Heure courte localisée (« 14:32 »), horodatage des bulles de la messagerie — miroir de `formatTime`.
    static func time(_ date: Date?, locale: Locale = WeydaLocale.formatting, timeZone: TimeZone = .current) -> String {
        guard let date else { return "" }
        let formatter = makeFormatter(locale: locale, timeZone: timeZone)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return latinDigits(formatter.string(from: date))
    }

    // MARK: - Texte bidirectionnel et chiffres

    /// Isole un fragment à lire de gauche à droite (téléphone, référence, « 2 / 5 ») dans une phrase arabe :
    /// sans les isolats U+2066 / U+2069, l'algorithme bidi déplace le « + » — « +213550… » s'affichait
    /// « 213550…+ » (miroir de `ltrIsolate`).
    static func ltrIsolate(_ text: String) -> String {
        "\u{2066}\(text)\u{2069}"
    }

    /// Filet de sécurité : ramène en ASCII les chiffres arabes-indiens (U+0660…0669) et persans
    /// (U+06F0…06F9) qu'un formateur système produirait malgré `@numbers=latn`.
    static func latinDigits(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        var changed = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x0660...0x0669).contains(value) {
                scalars.append(Unicode.Scalar(UInt8(value - 0x0660 + 48)))
                changed = true
            } else if (0x06F0...0x06F9).contains(value) {
                scalars.append(Unicode.Scalar(UInt8(value - 0x06F0 + 48)))
                changed = true
            } else {
                scalars.append(scalar)
            }
        }
        return changed ? String(scalars) : text
    }

    // MARK: - Interne

    /// Calendrier grégorien imposé : un téléphone réglé sur un autre calendrier garde des dates lisibles
    /// comme sur le site.
    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// DateFormatter n'est pas Sendable : un par appel (le coût est négligeable à l'échelle d'un écran).
    private static func makeFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        // Après la locale : la changer réinitialise le calendrier du formateur.
        formatter.calendar = gregorian(timeZone)
        formatter.timeZone = timeZone
        return formatter
    }

    private static func formatted(_ date: Date, template: String, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = makeFormatter(locale: locale, timeZone: timeZone)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return latinDigits(formatter.string(from: date))
    }

    private static func dayDistance(from start: Date, to end: Date, timeZone: TimeZone) -> Int {
        let calendar = gregorian(timeZone)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day
        return max(days ?? 1, 1)
    }
}
