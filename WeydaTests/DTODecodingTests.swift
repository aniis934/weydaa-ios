import Foundation
import XCTest
@testable import Weyda

/// Tolérance du décodage (champ absent, `null`, clé inconnue, nombre en texte, date sans millisecondes),
/// corps d'édition, et logique des modèles portée d'Android. Données 100 % fictives (formes du contrat d'API).
final class DTODecodingTests: XCTestCase {
    /// 2026-09-07T12:12:43Z.
    private static let referenceEpoch: TimeInterval = 1_788_783_163

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Tolérance

    func testMissingAndNullFieldsTakeAndroidDefaults() throws {
        let json = #"{"id":"a1","title":"Vélo","description":null,"views":null,"images":null,"priceType":null,"isFeatured":null}"#
        let dto = try decode(AnnonceDTO.self, json)
        XCTAssertEqual(dto.description, "")
        XCTAssertEqual(dto.views, 0)
        XCTAssertEqual(dto.images, [])
        XCTAssertEqual(dto.priceType, "FIXED")
        XCTAssertEqual(dto.status, "ACTIVE")
        XCTAssertFalse(dto.isFeatured)
        XCTAssertNil(dto.price)
        XCTAssertNil(dto.hasPhone)
        XCTAssertNil(dto.attributes)

        let listing = dto.toDomain()
        XCTAssertEqual(listing.priceType, PriceType.fixed)
        XCTAssertEqual(listing.listingStatus, ListingStatus.active)
        XCTAssertNil(listing.createdAt)
        XCTAssertEqual(listing.attributes, [:])
        XCTAssertFalse(listing.hasPhone)
        XCTAssertNil(listing.seller)
    }

    func testUnknownKeysAreIgnored() throws {
        let json = #"{"id":"a1","title":"T","futureField":{"x":[1,2,{"y":null}]},"another":true,"deletedAt":null}"#
        let dto = try decode(AnnonceDTO.self, json)
        XCTAssertEqual(dto.id, "a1")
        XCTAssertEqual(dto.title, "T")
    }

    func testNumbersAndBooleansReceivedAsTextAreAccepted() throws {
        let json = #"{"id":"a1","title":"T","price":"45000","views":"12","wilayaId":"16","isFeatured":"true","renewalCount":2.0}"#
        let dto = try decode(AnnonceDTO.self, json)
        XCTAssertEqual(dto.price, 45_000)
        XCTAssertEqual(dto.views, 12)
        XCTAssertEqual(dto.wilayaId, 16)
        XCTAssertTrue(dto.isFeatured)
        XCTAssertEqual(dto.renewalCount, 2)

        let unreadable = try decode(AnnonceDTO.self, #"{"id":"a1","title":"T","price":"sur demande"}"#)
        XCTAssertNil(unreadable.price)
    }

    func testTextFieldReceivingNumberIsConverted() throws {
        let dto = try decode(AnnonceDTO.self, #"{"id":42,"title":"T","slug":7}"#)
        XCTAssertEqual(dto.id, "42")
        XCTAssertEqual(dto.slug, "7")
    }

    func testMissingRequiredFieldFailsAndListSkipsTheBrokenItem() throws {
        XCTAssertThrowsError(try decode(AnnonceDTO.self, #"{"title":"sans id"}"#))
        let json = #"{"annonces":[{"id":"a1","title":"A"},{"title":"sans id"},{"id":"a2","title":"B"}],"total":3}"#
        let page = try decode(AnnoncesPageDTO.self, json)
        XCTAssertEqual(page.annonces.map { $0.id }, ["a1", "a2"])
        XCTAssertEqual(page.total, 3)
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.totalPages, 1)
    }

    func testBareArrayIsDecodedWithoutBreaking() throws {
        let json = #"[{"id":"c1","slug":"vehicules","nameFr":"Véhicules"},{"slug":"sans-id"},{"id":"c2","slug":"immobilier","nameFr":"Immobilier"}]"#
        let categories = try decode(DTOLossyList<CategoryDTO>.self, json).items
        XCTAssertEqual(categories.map { $0.slug }, ["vehicules", "immobilier"])
    }

    func testTokenResponseDefaultsAndRequiredUser() throws {
        let json = #"{"accessToken":"acc","refreshToken":"ref","expiresIn":"3600","user":{"id":"u1"}}"#
        let dto = try decode(TokenResponseDTO.self, json)
        XCTAssertEqual(dto.tokenType, "Bearer")
        XCTAssertEqual(dto.expiresIn, 3600)
        XCTAssertEqual(dto.refreshExpiresIn, 30 * 24 * 3600)
        XCTAssertFalse(dto.isNewUser)
        XCTAssertEqual(dto.user.role, "USER")
        XCTAssertFalse(dto.user.emailVerified)
        XCTAssertThrowsError(try decode(TokenResponseDTO.self, #"{"accessToken":"acc","refreshToken":"ref"}"#))

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tokens = dto.toTokens(now: now)
        XCTAssertEqual(tokens.accessExpiresAt, now.addingTimeInterval(3600))
        XCTAssertFalse(tokens.isAccessExpiring(within: 60, now: now))
        XCTAssertTrue(tokens.isAccessExpiring(within: 3600, now: now))
        XCTAssertFalse(tokens.isRefreshExpired(now: now))
        XCTAssertTrue(tokens.isRefreshExpired(now: now.addingTimeInterval(30 * 24 * 3600)))
    }

    // MARK: - Dates

    func testDatesWithAndWithoutMilliseconds() throws {
        let plain = try XCTUnwrap(DateParsing.parseInstant("2026-09-07T12:12:43Z"))
        XCTAssertEqual(plain.timeIntervalSince1970, Self.referenceEpoch, accuracy: 0.0005)
        let millis = try XCTUnwrap(DateParsing.parseInstant("2026-09-07T12:12:43.698Z"))
        XCTAssertEqual(millis.timeIntervalSince1970, Self.referenceEpoch + 0.698, accuracy: 0.0005)
        let micros = try XCTUnwrap(DateParsing.parseInstant("2026-09-07T12:12:43.698123Z"))
        XCTAssertEqual(micros.timeIntervalSince1970, Self.referenceEpoch, accuracy: 1)
        let offset = try XCTUnwrap(DateParsing.parseInstant("2026-09-07T13:12:43+01:00"))
        XCTAssertEqual(offset.timeIntervalSince1970, Self.referenceEpoch, accuracy: 0.0005)
        XCTAssertNil(DateParsing.parseInstant(nil))
        XCTAssertNil(DateParsing.parseInstant(""))
        XCTAssertNil(DateParsing.parseInstant("hier"))

        let date = Date(timeIntervalSince1970: Self.referenceEpoch)
        XCTAssertEqual(DateParsing.isoString(date), "2026-09-07T12:12:43.000Z")
        let reparsed = try XCTUnwrap(DateParsing.parseInstant(DateParsing.isoString(date)))
        XCTAssertEqual(reparsed.timeIntervalSince1970, Self.referenceEpoch, accuracy: 0.0005)
    }

    // MARK: - Corps d'édition

    func testUpdateBodyEncodesTypedValuesAndExplicitNulls() throws {
        let submission = ListingSubmission(
            title: "Clio 4 diesel",
            description: String(repeating: "d", count: 30),
            price: 1_850_000,
            priceType: .negotiable,
            categoryId: "cat_vehicules",
            wilayaId: 16,
            phone: "0555000000",
            images: [UploadedImage(url: "https://example.com/a.webp", thumbnailUrl: nil, publicId: "annonces/a.webp")],
            attributes: [
                "year": AttributeValue(type: .number, raw: "2015"),
                "engine": AttributeValue(type: .number, raw: "1.5"),
                "note": AttributeValue(type: .number, raw: "abc"),
                "airbag": AttributeValue(type: .boolean, raw: "true"),
                "color": AttributeValue(type: .select, raw: "rouge"),
            ]
        )
        let json = submission.toUpdateJSON()
        XCTAssertEqual(json["price"], JSONValue.number(1_850_000))
        XCTAssertEqual(json["priceType"], JSONValue.string("NEGOTIABLE"))
        XCTAssertEqual(json["wilayaId"], JSONValue.number(16))
        XCTAssertEqual(json["communeId"], JSONValue.null)
        XCTAssertEqual(json["subcategorySlug"], JSONValue.null)
        XCTAssertEqual(json["phone"], JSONValue.string("0555000000"))
        XCTAssertEqual(json["attributes"]?["year"], JSONValue.number(2015))
        XCTAssertEqual(json["attributes"]?["airbag"], JSONValue.bool(true))
        XCTAssertEqual(json["attributes"]?["note"], JSONValue.string("abc"))

        let body = try submission.toUpdateBody()
        let wire = try XCTUnwrap(String(data: body, encoding: .utf8))
        let fragments = [
            #""price":1850000"#,
            #""communeId":null"#,
            #""subcategorySlug":null"#,
            #""year":2015"#,
            #""engine":1.5"#,
            #""airbag":true"#,
            #""color":"rouge""#,
            #""images":[{"publicId":"annonces/a.webp","url":"https://example.com/a.webp"}]"#,
        ]
        for fragment in fragments {
            XCTAssertTrue(wire.contains(fragment), "\(fragment) absent de \(wire)")
        }

        // Le corps relu par JSONSerialization garde bien les clés à null.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertTrue(object["communeId"] is NSNull)
        XCTAssertTrue(object["subcategorySlug"] is NSNull)
    }

    func testCreateRequestOmitsNilFieldsAndKeepsImages() throws {
        let request = ListingSubmission(
            title: "Table en bois",
            description: String(repeating: "d", count: 30),
            price: nil,
            priceType: .free,
            categoryId: "cat_maison"
        ).toRequest()
        XCTAssertNil(request.attributes)
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["price"])
        XCTAssertNil(object["wilayaId"])
        XCTAssertNil(object["phone"])
        XCTAssertNil(object["attributes"])
        XCTAssertEqual((object["images"] as? [Any])?.count, 0)
        XCTAssertEqual(object["priceType"] as? String, "FREE")
    }

    // MARK: - JSON libre

    func testJSONValueRoundTripAndListingAttributes() throws {
        let json = #"{"year":2015,"fuel":"diesel","abs":true,"weight":1.5,"opts":null,"nested":{"a":1},"list":[1]}"#
        let value = try decode(JSONValue.self, json)
        XCTAssertEqual(value["year"], JSONValue.number(2015))
        XCTAssertEqual(value["abs"], JSONValue.bool(true))
        XCTAssertEqual(value["opts"], JSONValue.null)
        XCTAssertEqual(value["nested"], JSONValue.object(["a": .number(1)]))
        XCTAssertEqual(value["list"], JSONValue.array([.number(1)]))
        let reencoded = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: reencoded), value)

        var dto = AnnonceDTO(id: "a1", title: "T")
        dto.attributes = value
        XCTAssertEqual(
            dto.toDomain().attributes,
            ["year": "2015", "fuel": "diesel", "abs": "true", "weight": "1.5"]
        )
    }

    // MARK: - Modèles

    func testFoldedForSearch() {
        XCTAssertEqual("  Électroménager ".foldedForSearch(), "electromenager")
        XCTAssertEqual("Ça coûte CHER".foldedForSearch(), "ca coute cher")
        XCTAssertEqual("Cafe\u{0301}".foldedForSearch(), "cafe")
        // Lettres arabes conservées ; seuls leurs signes diacritiques (marques Mn) disparaissent, comme sur Android.
        XCTAssertEqual("سيارات".foldedForSearch(), "سيارات")
        XCTAssertEqual(
            "\u{0633}\u{064E}\u{064A}\u{0627}\u{0631}\u{0629}".foldedForSearch(),
            "\u{0633}\u{064A}\u{0627}\u{0631}\u{0629}"
        )
    }

    func testConversationSearchAndUnreadState() {
        let conversation = Conversation(
            id: "c1",
            annonceId: "a1",
            annonce: ConversationAnnonce(id: "a1", title: "Réfrigérateur Électroménager", imageUrl: nil),
            buyer: ConversationPartner(id: "u1", name: "Karim B.", avatarUrl: nil),
            seller: ConversationPartner(id: "u2", name: "Samia K.", avatarUrl: nil),
            updatedAt: nil,
            lastMessage: LastMessage(content: "Toujours dispo ?", createdAt: nil, senderId: "u2", readAt: nil, isDeleted: false)
        )
        XCTAssertTrue(conversation.matches(query: "electro", userId: "u1"))
        XCTAssertTrue(conversation.matches(query: "SAMIA", userId: "u1"))
        XCTAssertFalse(conversation.matches(query: "samia", userId: "u2"))
        XCTAssertTrue(conversation.matches(query: "   ", userId: "u1"))
        XCTAssertTrue(conversation.matches(query: "dispo", userId: "u2"))
        XCTAssertTrue(conversation.isUnreadFor("u1"))
        XCTAssertFalse(conversation.isUnreadFor("u2"))
        XCTAssertEqual(conversation.partner("u1").id, "u2")
        XCTAssertTrue(conversation.isSeller("u2"))
    }

    func testNotificationTarget() {
        func notification(_ url: String?) -> AppNotification {
            AppNotification(id: "n1", kind: .message, title: "", body: "", url: url, read: false, createdAt: nil)
        }
        XCTAssertEqual(notification("/annonce/clio-4-ab12").target, NotificationTarget.listing(idOrSlug: "clio-4-ab12"))
        XCTAssertEqual(notification("/fr/annonce/a1?ref=push").target, NotificationTarget.listing(idOrSlug: "a1"))
        XCTAssertEqual(notification("/dashboard/messages/c1").target, NotificationTarget.conversation(id: "c1"))
        XCTAssertEqual(notification("/ar/dashboard/messages/c1/").target, NotificationTarget.conversation(id: "c1"))
        XCTAssertEqual(notification("/profil/u1").target, NotificationTarget.seller(id: "u1"))
        XCTAssertEqual(notification("/dashboard/annonces").target, NotificationTarget.myListings)
        XCTAssertEqual(notification("/en/dashboard/annonces?status=EXPIRED").target, NotificationTarget.myListings)
        XCTAssertNil(notification("/dashboard/annonces/extra").target)
        XCTAssertNil(notification("/dashboard/messages").target)
        XCTAssertNil(notification("/annonce").target)
        XCTAssertNil(notification("/").target)
        XCTAssertNil(notification(nil).target)

        let dto = NotificationDTO(id: "n2", type: "OFFER_COUNTER", title: "Contre-offre", body: nil, url: "  ")
        let mapped = dto.toDomain()
        XCTAssertEqual(mapped.kind, NotificationKind.offerCounter)
        XCTAssertEqual(mapped.body, "")
        XCTAssertNil(mapped.url)
        XCTAssertEqual(NotificationKind.from("NEW_TYPE"), NotificationKind.unknown)
    }

    func testListingWebUrl() {
        var listing = AnnonceDTO(id: "a1", title: "T").toDomain()
        XCTAssertEqual(listing.webUrl(host: "https://weydaa.com//", locale: "en"), "https://weydaa.com/en/annonce/a1")
        listing.slug = "  "
        listing.categorySlug = "vehicules"
        XCTAssertEqual(listing.webUrl(host: "https://weydaa.com"), "https://weydaa.com/fr/annonce/a1")
        listing.slug = "clio-4-ab12"
        XCTAssertEqual(listing.webUrl(host: "https://weydaa.com"), "https://weydaa.com/fr/vehicules/clio-4-ab12")
    }

    func testIsRenewable() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func listing(_ status: String, expiresInDays days: Double?) -> Listing {
            Listing(
                id: "l1",
                title: "T",
                description: "",
                priceType: .fixed,
                status: status,
                views: 0,
                isFeatured: false,
                images: [],
                attributes: [:],
                expiresAt: days.map { now.addingTimeInterval($0 * 86_400) }
            )
        }
        XCTAssertTrue(listing("EXPIRED", expiresInDays: nil).isRenewable(now: now))
        XCTAssertTrue(listing("ACTIVE", expiresInDays: 3).isRenewable(now: now))
        XCTAssertTrue(listing("ACTIVE", expiresInDays: 7).isRenewable(now: now))
        XCTAssertTrue(listing("ACTIVE", expiresInDays: -1).isRenewable(now: now))
        XCTAssertFalse(listing("ACTIVE", expiresInDays: 8).isRenewable(now: now))
        XCTAssertFalse(listing("ACTIVE", expiresInDays: nil).isRenewable(now: now))
        // `expiresAt` court aussi sur une annonce en attente, refusée ou vendue : pas de renouvellement.
        XCTAssertFalse(listing("PENDING", expiresInDays: 1).isRenewable(now: now))
        XCTAssertFalse(listing("REJECTED", expiresInDays: 1).isRenewable(now: now))
        XCTAssertFalse(listing("SOLD", expiresInDays: -1).isRenewable(now: now))

        var renewed = listing("ACTIVE", expiresInDays: 3)
        XCTAssertEqual(renewed.renewalsLeft, 3)
        renewed.renewalCount = 5
        XCTAssertEqual(renewed.renewalsLeft, 0)
    }

    func testChatMessageIsDeletableBy() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func message(sender: String = "u1", sentSecondsAgo: Double?, deleted: Bool = false) -> ChatMessage {
            ChatMessage(
                id: "m1",
                conversationId: "c1",
                senderId: sender,
                content: "Bonjour",
                createdAt: sentSecondsAgo.map { now.addingTimeInterval(-$0) },
                readAt: nil,
                deletedAt: deleted ? now : nil
            )
        }
        XCTAssertTrue(message(sentSecondsAgo: 60).isDeletableBy("u1", now: now))
        // Marge de 2 min pour l'écart d'horloge téléphone / serveur.
        XCTAssertTrue(message(sentSecondsAgo: 6 * 60).isDeletableBy("u1", now: now))
        XCTAssertTrue(message(sentSecondsAgo: -30).isDeletableBy("u1", now: now))
        XCTAssertFalse(message(sentSecondsAgo: 7 * 60).isDeletableBy("u1", now: now))
        XCTAssertFalse(message(sender: "u2", sentSecondsAgo: 60).isDeletableBy("u1", now: now))
        XCTAssertFalse(message(sentSecondsAgo: 60, deleted: true).isDeletableBy("u1", now: now))
        XCTAssertFalse(message(sentSecondsAgo: nil).isDeletableBy("u1", now: now))
    }

    // MARK: - Messagerie

    func testMessagesOffersAndConversationMapping() throws {
        let json = """
        {"id":"c1","annonceId":"","buyerId":"u1","sellerId":"u2",
         "annonce":{"id":"a1","title":"Clio 4","status":"ACTIVE","price":"1850000","priceType":"NEGOTIABLE",
                    "images":[{"url":"https://example.com/2.webp","order":1},{"url":"https://example.com/1.webp","order":0}]},
         "buyer":{"id":"u1","name":"Karim B."},
         "messages":[
           {"id":"m1","senderId":"u1","content":"Bonjour","createdAt":"2026-09-07T12:12:43.698Z","type":"TEXT"},
           {"id":"m2","senderId":"u2","content":"","type":"OFFER","metadata":{"kind":"COUNTER","amount":"1700000"}},
           {"id":"m3","senderId":"u2","content":"","type":"OFFER","metadata":{"kind":"WHAT","amount":10}},
           {"id":"m4","senderId":"u2","content":"","type":"OFFER","metadata":{"kind":"NEW","amount":0}}
         ],
         "hasMore":true,"nextCursor":"","topic":"conv:c1:0000000000000000","isBlockedByMe":false}
        """
        let thread = try decode(ConversationDetailDTO.self, json).toDomain()
        XCTAssertEqual(thread.conversation.annonceId, "a1")
        XCTAssertEqual(thread.conversation.annonce?.imageUrl, "https://example.com/1.webp")
        XCTAssertEqual(thread.conversation.annonce?.price, 1_850_000)
        XCTAssertEqual(thread.conversation.annonce?.acceptsOffers, true)
        XCTAssertEqual(thread.conversation.buyer.name, "Karim B.")
        // Pas de bloc `seller` : l'id de repli `sellerId`, nom vide.
        XCTAssertEqual(thread.conversation.seller.id, "u2")
        XCTAssertEqual(thread.conversation.seller.name, "")
        XCTAssertTrue(thread.hasMore)
        XCTAssertNil(thread.nextCursor)
        XCTAssertEqual(thread.messages.map { $0.conversationId }, ["c1", "c1", "c1", "c1"])
        XCTAssertNotNil(thread.messages[0].createdAt)
        XCTAssertEqual(thread.messages[1].type, MessageType.offer)
        XCTAssertEqual(thread.messages[1].offer, OfferMeta(kind: .counter, amount: 1_700_000))
        XCTAssertNil(thread.messages[2].offer)
        XCTAssertNil(thread.messages[3].offer)

        XCTAssertNil(OfferMeta.parse(JSONValue.object(["kind": .string("NEW"), "amount": .bool(true)])))
        XCTAssertNil(OfferMeta.parse(JSONValue.string("NEW")))
        XCTAssertNil(OfferMeta.parse(nil))
        XCTAssertEqual(
            OfferMeta.parse(JSONValue.object(["kind": .string("ACCEPTED"), "amount": .number(1500)])),
            OfferMeta(kind: .accepted, amount: 1500)
        )
        // Littéraux JSON (tests, corps de requête) : même valeur que la forme explicite.
        let literal: JSONValue = ["kind": "NEW", "amount": 1500, "open": true, "tags": ["a"]]
        XCTAssertEqual(
            literal,
            JSONValue.object([
                "kind": .string("NEW"),
                "amount": .number(1500),
                "open": .bool(true),
                "tags": .array([.string("a")]),
            ])
        )
    }

    func testConversationListUsesLastMessagePreview() throws {
        let json = #"{"conversations":[{"id":"c1","annonce":{"id":"a1","title":"Vélo"},"buyerId":"u1","sellerId":"u2","messages":[{"content":"","senderId":"u2","deletedAt":"2026-09-07T12:12:43.698Z"}]}],"nextCursor":"c1"}"#
        let page = try decode(ConversationsPageDTO.self, json).toDomain()
        XCTAssertEqual(page.nextCursor, "c1")
        let conversation = try XCTUnwrap(page.items.first)
        XCTAssertEqual(conversation.annonceId, "a1")
        XCTAssertEqual(conversation.lastMessage?.isDeleted, true)
        XCTAssertEqual(conversation.buyer.id, "u1")
        XCTAssertEqual(conversation.topic, "")
    }

    // MARK: - Vendeur, catégories, avis, alertes, session

    func testSellerFromUserRef() throws {
        let json = #"{"id":"u1","name":"Karim B.","createdAt":"2025-01-15T08:00:00.000Z","emailVerified":"2025-01-15T08:05:00.000Z","isRecommended":true,"ratingCount":4,"ratingSum":18,"responseMinutes":45,"_count":{"annonces":7},"bio":"  "}"#
        let seller = try decode(UserRefDTO.self, json).toDomain()
        XCTAssertEqual(seller.name, "Karim B.")
        XCTAssertTrue(seller.emailVerified)
        XCTAssertEqual(seller.activeListings, 7)
        XCTAssertEqual(seller.rating, 4.5)
        XCTAssertTrue(seller.isFastResponder)
        XCTAssertNil(seller.bio)
        XCTAssertNotNil(seller.memberSince)

        let unrated = UserRefDTO(id: "u2", emailVerified: nil, responseMinutes: 90).toDomain()
        XCTAssertNil(unrated.rating)
        XCTAssertFalse(unrated.emailVerified)
        XCTAssertFalse(unrated.isFastResponder)
        XCTAssertEqual(unrated.name, "")
    }

    func testCategoriesKeepActiveChildrenInDisplayOrder() throws {
        let json = """
        {"id":"c1","slug":"vehicules","nameFr":"Véhicules","_count":{"annonces":12},"children":[
          {"id":"c3","slug":"motos","nameFr":"Motos","displayOrder":2},
          {"id":"c4","slug":"anciennes","nameFr":"Anciennes","displayOrder":0,"isActive":false},
          {"id":"c2","slug":"voitures","nameFr":"Voitures","displayOrder":1},
          {"id":"c5","slug":"pieces","nameFr":"Pièces","displayOrder":2}
        ]}
        """
        let category = try decode(CategoryDTO.self, json).toDomain()
        XCTAssertEqual(category.listingsCount, 12)
        XCTAssertEqual(category.children.map { $0.slug }, ["voitures", "motos", "pieces"])
        XCTAssertEqual(category.name.resolve("ar"), "Véhicules")
    }

    func testReviewsSavedSearchesAndSuggestions() throws {
        let reviews = try decode(
            ReviewsDTO.self,
            #"{"reviews":[{"id":"r1","rating":9,"comment":" ","author":{"name":"Karim B."}},{"id":"r2","rating":-1}],"ratingCount":2,"average":4.5}"#
        ).toDomain()
        XCTAssertEqual(reviews.reviews.map { $0.rating }, [5, 0])
        XCTAssertNil(reviews.reviews[0].comment)
        XCTAssertEqual(reviews.reviews[0].authorName, "Karim B.")
        XCTAssertEqual(reviews.average, 4.5)

        let search = try decode(
            SavedSearchDTO.self,
            #"{"id":"s1","name":"","params":{"q":"clio","wilaya":16,"category":""}}"#
        ).toDomain()
        XCTAssertEqual(search.name, "—")
        XCTAssertEqual(search.params, ["q": "clio", "wilaya": "16"])

        let suggestions = try decode(
            SuggestionsDTO.self,
            #"{"suggestions":[{"text":"Voitures","type":"category","slug":"voitures"},{"text":"Alger","type":"wilaya","id":16},{"text":"Clio","type":"listing"}]}"#
        ).suggestions.map { $0.toDomain() }
        XCTAssertEqual(suggestions.map { $0.type }, [SuggestionType.category, .wilaya, .listing])
        XCTAssertEqual(suggestions[1].id, 16)
        XCTAssertEqual(SuggestionType.from("rocket"), SuggestionType.listing)
    }

    func testUserMappingAndStorage() throws {
        let previous = User(
            id: "u1", name: "Karim B.", email: "test@example.com", avatarUrl: nil, role: "USER", emailVerified: false,
            phone: "0555000000", bio: "Vendeur de pièces", isRecommended: true, hasPassword: false
        )
        let refreshed = AuthUserDTO(id: "u1", name: "Karim B.", email: "test@example.com", emailVerified: true)
            .toDomain(previous: previous)
        XCTAssertTrue(refreshed.emailVerified)
        XCTAssertEqual(refreshed.phone, "0555000000")
        XCTAssertTrue(refreshed.isRecommended)
        XCTAssertFalse(refreshed.hasPassword)
        XCTAssertEqual(refreshed.maxImages, 8)

        let other = AuthUserDTO(id: "u9", email: "autre@example.com").toDomain(previous: previous)
        XCTAssertNil(other.phone)
        XCTAssertTrue(other.hasPassword)
        XCTAssertEqual(other.displayName, "autre")
        XCTAssertFalse(other.isStaff)

        let me = try decode(MeDTO.self, #"{"id":"u1","email":"test@example.com","createdAt":"2025-01-15T08:00:00.000Z","hasPassword":false}"#)
            .toDomain(emailVerified: true)
        XCTAssertTrue(me.emailVerified)
        XCTAssertFalse(me.hasPassword)
        XCTAssertNotNil(me.memberSince)

        // Stockage local (trousseau) : aller-retour EXACT, fractions de seconde comprises.
        var stored = refreshed
        stored.memberSince = Date(timeIntervalSinceReferenceDate: 810_475_963.123_456)
        let data = try JSONEncoder().encode(stored)
        XCTAssertEqual(try JSONDecoder().decode(User.self, from: data), stored)
        let minimal = try decode(User.self, #"{"id":"u1"}"#)
        XCTAssertEqual(minimal.email, "")
        XCTAssertEqual(minimal.role, "USER")
        XCTAssertFalse(minimal.emailVerified)
        XCTAssertTrue(minimal.hasPassword)
        XCTAssertNil(minimal.memberSince)
        let isoSince = try decode(User.self, #"{"id":"u1","memberSince":"2026-09-07T12:12:43Z"}"#).memberSince
        XCTAssertEqual(isoSince?.timeIntervalSince1970 ?? 0, Self.referenceEpoch, accuracy: 0.0005)

        let tokens = AuthTokens(
            accessToken: "acc",
            refreshToken: "ref",
            accessExpiresAt: Date(timeIntervalSinceReferenceDate: 821_696_400.987_654),
            refreshExpiresAt: Date(timeIntervalSince1970: 1_802_592_000)
        )
        let tokenData = try JSONEncoder().encode(tokens)
        XCTAssertEqual(try JSONDecoder().decode(AuthTokens.self, from: tokenData), tokens)
        XCTAssertThrowsError(try decode(AuthTokens.self, #"{"accessToken":"acc","refreshToken":"ref"}"#))
    }
}
