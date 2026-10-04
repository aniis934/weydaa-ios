import Foundation
import XCTest
@testable import Weyda

/// Séparateurs de jour du fil : regroupement par jour civil (calendrier et fuseau injectés), minuit pile, liste vide,
/// séparateurs insérés entre les lignes avec des identifiants stables, libellés du système en chiffres latins.
/// Données fictives.
final class ChatDayGroupingTests: XCTestCase {
    private static let utc = ChatDayGrouping.deviceCalendar(timeZone: TimeZone(identifier: "UTC") ?? .current)
    /// Alger : UTC+1 toute l'année (pas d'heure d'été).
    private static let algiers = ChatDayGrouping.deviceCalendar(timeZone: TimeZone(identifier: "Africa/Algiers") ?? .current)

    /// « Maintenant » des tests, après tous les messages : le résultat ne dépend pas de l'horloge de la CI.
    private static let later = Date(timeIntervalSince1970: 1_796_000_000)

    private static func date(_ iso: String) -> Date {
        DateParsing.parseInstant(iso) ?? Date(timeIntervalSince1970: 0)
    }

    private static func message(_ id: String, at iso: String?, sender: String = "user_2") -> ChatMessage {
        ChatMessage(
            id: id,
            conversationId: "c1",
            senderId: sender,
            content: "m\(id)",
            createdAt: iso.map { date($0) },
            readAt: nil,
            deletedAt: nil
        )
    }

    func testMessagesOverThreeDaysGiveThreeGroupsInOrder() {
        let messages = [
            Self.message("a", at: "2026-10-02T09:00:00.000Z"),
            Self.message("b", at: "2026-10-02T18:30:00.000Z"),
            Self.message("c", at: "2026-10-03T08:15:00.000Z"),
            Self.message("d", at: "2026-10-04T07:00:00.000Z"),
            Self.message("e", at: "2026-10-04T09:12:00.000Z"),
        ]
        let groups = ChatDayGrouping.groups(messages, calendar: Self.utc, now: Self.later)
        XCTAssertEqual(groups.map { $0.day?.key }, ["2026-10-02", "2026-10-03", "2026-10-04"])
        XCTAssertEqual(groups.map { $0.messages.map { $0.id } }, [["a", "b"], ["c"], ["d", "e"]])
        XCTAssertEqual(groups.first?.day?.start, Self.date("2026-10-02T00:00:00.000Z"))
        XCTAssertEqual(groups.first?.day?.id, "chat.day.2026-10-02")
    }

    func testMidnightBelongsToTheNewDay() {
        let messages = [
            Self.message("before", at: "2026-10-03T23:59:59.000Z"),
            Self.message("midnight", at: "2026-10-04T00:00:00.000Z"),
        ]
        let groups = ChatDayGrouping.groups(messages, calendar: Self.utc, now: Self.later)
        XCTAssertEqual(groups.map { $0.day?.key }, ["2026-10-03", "2026-10-04"])
        XCTAssertEqual(groups.last?.messages.map { $0.id }, ["midnight"])
        XCTAssertEqual(groups.last?.day?.start, Self.date("2026-10-04T00:00:00.000Z"))
    }

    func testTheInjectedTimeZoneDecidesTheCivilDay() {
        // 22 h et 23 h 30 UTC : le même jour en UTC, mais minuit est déjà passé à Alger (UTC+1) pour le second.
        let messages = [
            Self.message("late", at: "2026-10-03T22:00:00.000Z"),
            Self.message("later", at: "2026-10-03T23:30:00.000Z"),
        ]
        XCTAssertEqual(ChatDayGrouping.groups(messages, calendar: Self.utc, now: Self.later).map { $0.day?.key }, ["2026-10-03"])
        let local = ChatDayGrouping.groups(messages, calendar: Self.algiers, now: Self.later)
        XCTAssertEqual(local.map { $0.day?.key }, ["2026-10-03", "2026-10-04"])
        XCTAssertEqual(local.last?.day?.start, Self.date("2026-10-03T23:00:00.000Z"))
    }

    func testAnEmptyThreadHasNoGroupAndNoSeparator() {
        XCTAssertTrue(ChatDayGrouping.groups([], calendar: Self.utc, now: Self.later).isEmpty)
        XCTAssertTrue(ChatTimeline.items(rows: [], calendar: Self.utc, now: Self.later).isEmpty)
    }

    func testAnUndatedMessageStaysWithItsNeighbours() {
        let groups = ChatDayGrouping.groups(
            [Self.message("x", at: nil), Self.message("a", at: "2026-10-02T09:00:00.000Z"), Self.message("y", at: nil)],
            calendar: Self.utc,
            now: Self.later
        )
        XCTAssertEqual(groups.map { $0.day?.key }, [nil, "2026-10-02"])
        XCTAssertEqual(groups.last?.messages.map { $0.id }, ["a", "y"])
    }

    func testTimelineInsertsAStableSeparatorBeforeEachDayAndBreaksSuites() {
        let messages = [
            Self.message("a", at: "2026-10-02T21:00:00.000Z"),
            Self.message("b", at: "2026-10-02T21:05:00.000Z"),
            Self.message("c", at: "2026-10-03T08:00:00.000Z"),
        ]
        let rows = ChatTimeline.rows(messages: messages, userId: "user_1", now: Self.date("2026-10-04T10:00:00.000Z"), calendar: Self.utc)
        // Même auteur, mais un jour les sépare : la suite est coupée.
        XCTAssertEqual(rows.map { $0.startsGroup }, [true, false, true])
        XCTAssertEqual(rows.map { $0.endsGroup }, [false, true, true])

        let items = ChatTimeline.items(rows: rows, calendar: Self.utc, now: Self.later)
        XCTAssertEqual(items.map { $0.id }, ["chat.day.2026-10-02", "a", "b", "chat.day.2026-10-03", "c"])
        // Une page plus ancienne du même jour : le séparateur garde son identifiant et passe au-dessus.
        let older = [Self.message("z", at: "2026-10-02T08:00:00.000Z")] + messages
        let olderRows = ChatTimeline.rows(messages: older, userId: "user_1", now: Self.date("2026-10-04T10:00:00.000Z"), calendar: Self.utc)
        XCTAssertEqual(
            ChatTimeline.items(rows: olderRows, calendar: Self.utc, now: Self.later).map { $0.id },
            ["chat.day.2026-10-02", "z", "a", "b", "chat.day.2026-10-03", "c"]
        )
    }

    /// Horloge de l'appareil en retard (ou données simulées en avance) : jamais de séparateur « Demain ».
    func testAFutureMessageIsGroupedUnderTodayWithASingleSeparator() {
        let now = Self.date("2026-10-03T15:00:00.000Z")
        let messages = [
            Self.message("yesterday", at: "2026-10-02T20:00:00.000Z"),
            Self.message("today", at: "2026-10-03T09:00:00.000Z"),
            Self.message("tomorrow", at: "2026-10-04T09:12:00.000Z"),
        ]
        let groups = ChatDayGrouping.groups(messages, calendar: Self.utc, now: now)
        XCTAssertEqual(groups.map { $0.day?.key }, ["2026-10-02", "2026-10-03"])
        XCTAssertEqual(groups.last?.messages.map { $0.id }, ["today", "tomorrow"])
        XCTAssertEqual(groups.last?.day?.start, Self.date("2026-10-03T00:00:00.000Z"))

        let rows = ChatTimeline.rows(messages: messages, userId: "user_1", now: now, calendar: Self.utc)
        let items = ChatTimeline.items(rows: rows, calendar: Self.utc, now: now)
        XCTAssertEqual(items.map { $0.id }, ["chat.day.2026-10-02", "yesterday", "chat.day.2026-10-03", "today", "tomorrow"])
        // Même jour borné : les deux messages restent une seule suite.
        XCTAssertEqual(rows.map { $0.startsGroup }, [true, true, false])

        // Le jour borné porte le libellé relatif d'aujourd'hui (« Today »), jamais « Tomorrow ».
        let boundedTomorrow = ChatDayGrouping.day(of: Date().addingTimeInterval(86_400), calendar: Self.utc)
        XCTAssertEqual(boundedTomorrow.key, ChatDayGrouping.day(of: Date(), calendar: Self.utc).key)
        let label = ChatDayGrouping.label(for: boundedTomorrow, calendar: Self.utc, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(label, ChatDayGrouping.label(for: ChatDayGrouping.day(of: Date(), calendar: Self.utc), calendar: Self.utc, locale: Locale(identifier: "en_US")))
    }

    func testLabelsComeFromTheSystemInLatinDigits() {
        let past = ChatDayGrouping.day(of: Self.date("2025-03-14T12:00:00.000Z"), calendar: Self.utc)
        for identifier in ["fr_DZ", "en_DZ", "ar_DZ"] {
            let locale = WeydaLocale.latinDigits(language: String(identifier.prefix(2)), region: "DZ")
            let label = ChatDayGrouping.label(for: past, calendar: Self.utc, locale: locale)
            XCTAssertTrue(label.contains("2025"), "\(identifier) : \(label)")
            XCTAssertFalse(label.unicodeScalars.contains(where: { (0x0660...0x0669).contains($0.value) }), "\(identifier) : \(label)")
        }
        // Aujourd'hui : libellé relatif du système (« Aujourd'hui », « Today », « اليوم »), sans date chiffrée.
        let today = ChatDayGrouping.day(of: Date(), calendar: Self.utc)
        let todayLabel = ChatDayGrouping.label(for: today, calendar: Self.utc, locale: Locale(identifier: "en_US"))
        XCTAssertFalse(todayLabel.isEmpty)
        XCTAssertFalse(todayLabel.contains(where: { $0.isNumber }), todayLabel)
    }
}
