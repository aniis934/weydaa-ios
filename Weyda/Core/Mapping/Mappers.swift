import Foundation

// Portage de data/mapper/Mappers.kt : DTO → domaine, domaine → corps de requête. Mêmes règles et mêmes replis
// qu'Android, cas limites compris ; dates lues par `DateParsing.parseInstant`. `StoredUserDto` / `toStored`
// n'ont pas d'équivalent : `User` est `Codable` (format de stockage local).

/// Aides internes des mappers.
private nonisolated enum MappingSupport {
    /// Tri stable par clé entière : `sortedBy` (Kotlin) est stable, `sorted(by:)` (Swift) ne le garantit pas.
    static func stableSorted<T>(_ items: [T], by key: (T) -> Int) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                let left = key(lhs.element)
                let right = key(rhs.element)
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    /// `JsonElement?.toStringList()` : tableau → ses valeurs simples ; valeur simple → [elle] ; sinon [].
    static func stringList(_ value: JSONValue?) -> [String] {
        guard let value else { return [] }
        if let values = value.arrayValue {
            return values.compactMap { $0.textValue }
        }
        guard let text = value.textValue else { return [] }
        return [text]
    }

    /// `attributes` d'une annonce → `{ clé: texte }` : valeurs simples seulement (nombre écrit, booléen
    /// `true`/`false`) ; `null`, objets et tableaux ignorés (`contentOrNull` Android).
    static func attributeTexts(_ value: JSONValue?) -> [String: String] {
        guard let object = value?.objectValue else { return [:] }
        return object.compactMapValues { $0.textValue }
    }

    /// `UserRefDto?.toPartner(fallbackId)` : l'id du bloc (même vide) s'il existe, sinon l'id de repli.
    static func partner(_ ref: UserRefDTO?, fallbackId: String) -> ConversationPartner {
        ConversationPartner(id: ref?.id ?? fallbackId, name: ref?.name ?? "", avatarUrl: ref?.avatar)
    }

    /// Valeur JSON, ou `null` EXPLICITE (corps d'édition).
    static func orNull(_ value: JSONValue?) -> JSONValue {
        value ?? .null
    }
}

/* ───────── Annonces ───────── */

nonisolated extension AiModerationDTO {
    func toDomain() -> ModerationVerdict {
        ModerationVerdict(
            decision: decision,
            confidence: confidence,
            reasons: MappingSupport.stringList(reasons),
            suggestions: descriptionSuggestions
        )
    }
}

nonisolated extension UserRefDTO {
    /// Vendeur : bloc `user` d'une annonce ET réponse de `GET /api/users/{id}` (mêmes champs).
    /// `emailVerified` est une date ISO côté serveur : sa seule présence vaut « vérifié ».
    func toDomain() -> Seller {
        let trimmedBio = bio?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Seller(
            id: id,
            name: name ?? "",
            avatarUrl: avatar,
            memberSince: DateParsing.parseInstant(createdAt),
            isRecommended: isRecommended,
            emailVerified: !TextCheck.isBlank(emailVerified),
            ratingCount: ratingCount,
            ratingSum: ratingSum,
            responseMinutes: responseMinutes,
            activeListings: count?.annonces ?? 0,
            bio: TextCheck.nonBlank(trimmedBio)
        )
    }
}

nonisolated extension AnnonceDTO {
    func toDomain() -> Listing {
        let sortedImages = MappingSupport.stableSorted(images) { $0.order }
        let refs: [UploadedImage] = sortedImages
            .filter { !TextCheck.isBlank($0.publicId) }
            .map { UploadedImage(url: $0.url, thumbnailUrl: nil, publicId: $0.publicId) }
        let categoryName: LocalizedName? = category.map { LocalizedName(fr: $0.nameFr, ar: $0.nameAr, en: $0.nameEn) }
        let wilayaName: LocalizedName? = wilaya.map { LocalizedName(fr: $0.nameFr, ar: $0.nameAr) }
        let communeName: LocalizedName? = commune.map { LocalizedName(fr: $0.nameFr, ar: $0.nameAr) }
        // Ancien serveur : `phone` public, pas de `hasPhone`.
        let showsPhone: Bool = hasPhone ?? !TextCheck.isBlank(phone)
        return Listing(
            id: id,
            slug: slug,
            title: title,
            description: description,
            price: price,
            priceType: PriceType.from(priceType),
            status: status,
            views: views,
            isFeatured: isFeatured,
            phone: phone,
            createdAt: DateParsing.parseInstant(createdAt),
            images: sortedImages.map { $0.url },
            category: categoryName,
            categorySlug: category?.slug,
            wilaya: wilayaName,
            commune: communeName,
            seller: user?.toDomain(),
            attributes: MappingSupport.attributeTexts(attributes),
            expiresAt: DateParsing.parseInstant(expiresAt),
            renewalCount: renewalCount,
            parentCategorySlug: TextCheck.nonBlank(category?.parent?.slug),
            moderation: aiModeration?.toDomain(),
            imageRefs: refs,
            wilayaId: wilayaId ?? wilaya?.id,
            communeId: communeId ?? commune?.id,
            hasPhone: showsPhone
        )
    }
}

nonisolated extension AnnoncesPageDTO {
    func toDomain() -> ListingPage {
        var pageFacets: [String: [FacetValue]] = [:]
        for (key, values) in facets ?? [:] where !values.isEmpty {
            pageFacets[key] = values.map { FacetValue(value: $0.value, count: $0.count) }
        }
        return ListingPage(
            items: annonces.map { $0.toDomain() },
            total: total,
            page: page,
            totalPages: totalPages,
            facets: pageFacets
        )
    }
}

nonisolated extension CategoryDTO {
    /// Sous-catégories actives seulement, dans l'ordre `displayOrder`.
    func toDomain() -> Category {
        let activeChildren = MappingSupport.stableSorted(children.filter { $0.isActive }) { $0.displayOrder }
        return Category(
            id: id,
            slug: slug,
            name: LocalizedName(fr: nameFr, ar: nameAr, en: nameEn),
            icon: icon,
            color: color,
            listingsCount: count?.annonces ?? 0,
            children: activeChildren.map { $0.toDomain() }
        )
    }
}

/* ───────── Catalogue ───────── */

nonisolated extension AttributeDTO {
    func toDomain() -> AttributeDefinition {
        let resolvedOptions: [AttributeOption] = options.map { option in
            AttributeOption(
                value: option,
                label: TextCheck.nonBlank(optionLabels[option]) ?? AttributeDefinition.displayLabel(option)
            )
        }
        return AttributeDefinition(
            key: key,
            label: TextCheck.nonBlank(label) ?? AttributeDefinition.displayLabel(key),
            type: AttributeType.from(type),
            requirement: Requirement.from(requirement),
            options: resolvedOptions,
            dependsOn: TextCheck.nonBlank(dependsOn),
            min: min,
            max: max,
            step: step,
            unit: unit,
            unitLabel: unitLabel ?? unit,
            rangePresets: rangePresets,
            filterable: filterable,
            filterType: filterType
        )
    }
}

nonisolated extension SubcategoryDTO {
    func toDomain() -> Subcategory {
        Subcategory(
            slug: slug,
            parentSlug: parentSlug,
            name: LocalizedName(fr: TextCheck.ifBlank(nameFr, AttributeDefinition.displayLabel(slug)), ar: nameAr, en: nameEn)
        )
    }
}

nonisolated extension AttributesResponseDTO {
    func toDomain() -> AttributeSet {
        AttributeSet(
            attributes: attributes.map { $0.toDomain() },
            subcategories: subcategories.map { $0.toDomain() }
        )
    }
}

nonisolated extension ReviewsDTO {
    func toDomain() -> ReviewSummary {
        let items: [Review] = reviews.map { review in
            Review(
                id: review.id,
                rating: Swift.min(Swift.max(review.rating, 0), 5),
                comment: TextCheck.nonBlank(review.comment),
                createdAt: DateParsing.parseInstant(review.createdAt),
                authorName: review.author?.name,
                authorAvatar: review.author?.avatar
            )
        }
        return ReviewSummary(reviews: items, total: total, ratingCount: ratingCount, average: average)
    }
}

nonisolated extension SavedSearchDTO {
    func toDomain() -> SavedSearch {
        SavedSearch(
            id: id,
            name: TextCheck.ifBlank(name, "—"),
            params: (params ?? [:]).filter { !TextCheck.isBlank($0.value) },
            createdAt: DateParsing.parseInstant(createdAt)
        )
    }
}

nonisolated extension SuggestionDTO {
    func toDomain() -> Suggestion {
        Suggestion(text: text, type: SuggestionType.from(type), slug: slug, id: id)
    }
}

nonisolated extension WilayaDTO {
    func toDomain() -> Wilaya {
        Wilaya(id: id, name: LocalizedName(fr: nameFr, ar: nameAr), listingsCount: listingsCount)
    }
}

nonisolated extension CommuneDTO {
    func toDomain() -> Commune {
        Commune(id: id, wilayaId: wilayaId ?? 0, name: LocalizedName(fr: nameFr, ar: nameAr))
    }
}

nonisolated extension UploadResponseDTO {
    func toDomain() -> UploadedImage {
        UploadedImage(url: url, thumbnailUrl: TextCheck.nonBlank(thumbnailUrl), publicId: publicId)
    }
}

/* ───────── Dépôt et édition d'annonce ───────── */

nonisolated extension AttributeValue {
    /// Encodage typé attendu par l'API (`validateListingAttributes`) : nombre → nombre JSON (entier sans
    /// décimale), booléen → `true` seulement pour "true", select et texte → texte. Nombre illisible → texte.
    var jsonValue: JSONValue {
        switch self.type {
        case .number:
            if let number = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite {
                return .number(number)
            }
            return .string(raw)
        case .boolean:
            return .bool(raw == "true")
        case .select, .text:
            return .string(raw)
        }
    }
}

nonisolated extension ListingSubmission {
    /// Corps de `POST /api/annonces` (champs `nil` omis ; `images` toujours présent).
    func toRequest() -> CreateAnnonceRequestDTO {
        let imageRefs: [ImageRefDTO] = images.map { ImageRefDTO(url: $0.url, publicId: $0.publicId) }
        let typedAttributes: [String: JSONValue]? = attributes.isEmpty ? nil : attributes.mapValues { $0.jsonValue }
        return CreateAnnonceRequestDTO(
            title: title,
            description: description,
            price: price,
            priceType: priceType.rawValue,
            categoryId: categoryId,
            subcategorySlug: subcategorySlug,
            wilayaId: wilayaId,
            communeId: communeId,
            phone: phone,
            images: imageRefs,
            attributes: typedAttributes
        )
    }

    /// Corps du PUT d'édition (`PUT /api/annonces/{id}`, `editAnnonce` Android). Le serveur ne modifie que les
    /// champs PRÉSENTS : pour vider un prix (passage en « gratuit »), une wilaya, une commune retirée par un
    /// changement de wilaya ou des attributs devenus sans objet après un changement de catégorie, il faut un
    /// `null` EXPLICITE — ce qu'un DTO `Encodable` généré n'écrit jamais (il omet les `nil`).
    /// `phone` vide = numéro masqué ; `attributes` vide = attributs effacés (contrat du serveur).
    func toUpdateJSON() -> JSONValue {
        let request = toRequest()
        let imageValues: [JSONValue] = request.images.map { image in
            JSONValue.object(["url": .string(image.url), "publicId": .string(image.publicId)])
        }
        var body: [String: JSONValue] = [:]
        body["title"] = .string(request.title)
        body["description"] = .string(request.description)
        body["price"] = MappingSupport.orNull(request.price.map { JSONValue.number($0) })
        body["priceType"] = .string(request.priceType)
        body["categoryId"] = .string(request.categoryId)
        body["subcategorySlug"] = MappingSupport.orNull(request.subcategorySlug.map { JSONValue.string($0) })
        body["wilayaId"] = MappingSupport.orNull(request.wilayaId.map { JSONValue.number(Double($0)) })
        body["communeId"] = MappingSupport.orNull(request.communeId.map { JSONValue.number(Double($0)) })
        body["phone"] = .string(request.phone ?? "")
        body["images"] = .array(imageValues)
        body["attributes"] = .object(request.attributes ?? [:])
        return .object(body)
    }

    /// `toUpdateJSON()` encodé (clés triées) : le corps prêt à envoyer, `null` explicites compris.
    func toUpdateBody() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(toUpdateJSON())
    }
}

/* ───────── Session ───────── */

nonisolated extension AuthUserDTO {
    /// `previous` conserve les champs de profil (téléphone, bio…) que la réponse token ne renvoie pas,
    /// seulement s'il s'agit du même compte.
    func toDomain(previous: User? = nil) -> User {
        let same: User? = previous?.id == id ? previous : nil
        return User(
            id: id,
            name: name,
            email: email,
            avatarUrl: avatar,
            role: role,
            emailVerified: emailVerified,
            phone: same?.phone,
            phoneCountryCode: same?.phoneCountryCode,
            bio: same?.bio,
            isRecommended: same?.isRecommended ?? false,
            memberSince: same?.memberSince,
            hasPassword: same?.hasPassword ?? true
        )
    }
}

nonisolated extension MeDTO {
    /// GET /users/me ne renvoie pas `emailVerified` : il vient de la session courante.
    func toDomain(emailVerified: Bool) -> User {
        User(
            id: id,
            name: name,
            email: email,
            avatarUrl: avatar,
            role: role,
            emailVerified: emailVerified,
            phone: phone,
            phoneCountryCode: phoneCountryCode,
            bio: bio,
            isRecommended: isRecommended,
            memberSince: DateParsing.parseInstant(createdAt),
            hasPassword: hasPassword ?? true
        )
    }
}

nonisolated extension TokenResponseDTO {
    /// Échéances calculées depuis `now` (horloge du téléphone) : le jeton est opaque, seul `expiresIn` compte.
    func toTokens(now: Date = Date()) -> AuthTokens {
        AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessExpiresAt: now.addingTimeInterval(TimeInterval(expiresIn)),
            refreshExpiresAt: now.addingTimeInterval(TimeInterval(refreshExpiresIn))
        )
    }
}

nonisolated extension UserStatsDTO {
    func toDomain() -> UserStats {
        UserStats(
            totalViews: totalViews,
            activeCount: activeCount,
            pendingCount: pendingCount,
            soldCount: soldCount,
            expiredCount: expiredCount,
            favoritesReceived: favoritesReceived,
            messagesReceived: messagesReceived
        )
    }
}

/* ───────── Messagerie ───────── */

nonisolated extension OfferMeta {
    /// `metadata` d'un message OFFER → offre ; `nil` si la forme est invalide (défensif : base, temps réel).
    /// Équivalent de `parseOfferMeta` (Android) ; le montant peut arriver en texte.
    static func parse(_ metadata: JSONValue?) -> OfferMeta? {
        guard let object = metadata?.objectValue,
              let kind = OfferKind.from(object["kind"]?.textValue),
              let amount = object["amount"]?.doubleValue,
              amount.isFinite, amount > 0 else { return nil }
        return OfferMeta(kind: kind, amount: amount)
    }
}

nonisolated extension MessageDTO {
    func toDomain(fallbackConversationId: String = "") -> ChatMessage {
        ChatMessage(
            id: id,
            conversationId: TextCheck.ifBlank(conversationId, fallbackConversationId),
            senderId: senderId,
            content: content,
            createdAt: DateParsing.parseInstant(createdAt),
            readAt: DateParsing.parseInstant(readAt),
            deletedAt: DateParsing.parseInstant(deletedAt),
            type: MessageType.from(self.type),
            offer: OfferMeta.parse(metadata)
        )
    }
}

nonisolated extension MessagePreviewDTO {
    func toDomain() -> LastMessage {
        LastMessage(
            content: content,
            createdAt: DateParsing.parseInstant(createdAt),
            senderId: senderId,
            readAt: DateParsing.parseInstant(readAt),
            isDeleted: deletedAt != nil
        )
    }
}

nonisolated extension ConversationAnnonceDTO {
    func toDomain() -> ConversationAnnonce {
        let cover = MappingSupport.stableSorted(images) { $0.order }.first
        return ConversationAnnonce(
            id: id,
            title: title,
            imageUrl: cover?.url,
            status: status.map { ListingStatus.from($0) },
            price: price,
            priceType: priceType.map { PriceType.from($0) }
        )
    }
}

nonisolated extension ConversationDTO {
    func toDomain() -> Conversation {
        Conversation(
            id: id,
            annonceId: TextCheck.ifBlank(annonceId, annonce?.id ?? ""),
            annonce: annonce?.toDomain(),
            buyer: MappingSupport.partner(buyer, fallbackId: buyerId),
            seller: MappingSupport.partner(seller, fallbackId: sellerId),
            updatedAt: DateParsing.parseInstant(updatedAt),
            lastMessage: messages.first?.toDomain(),
            topic: topic
        )
    }
}

nonisolated extension ConversationsPageDTO {
    func toDomain() -> ConversationPage {
        ConversationPage(items: conversations.map { $0.toDomain() }, nextCursor: TextCheck.nonBlank(nextCursor))
    }
}

nonisolated extension ConversationDetailDTO {
    func toDomain() -> ChatThread {
        let conversation = Conversation(
            id: id,
            annonceId: TextCheck.ifBlank(annonceId, annonce?.id ?? ""),
            annonce: annonce?.toDomain(),
            buyer: MappingSupport.partner(buyer, fallbackId: buyerId),
            seller: MappingSupport.partner(seller, fallbackId: sellerId),
            updatedAt: DateParsing.parseInstant(updatedAt),
            lastMessage: nil,
            topic: topic
        )
        return ChatThread(
            conversation: conversation,
            messages: messages.map { $0.toDomain(fallbackConversationId: id) },
            hasMore: hasMore,
            nextCursor: TextCheck.nonBlank(nextCursor),
            isBlockedByMe: isBlockedByMe
        )
    }
}

/* ───────── Notifications ───────── */

nonisolated extension NotificationDTO {
    func toDomain() -> AppNotification {
        AppNotification(
            id: id,
            kind: NotificationKind.from(self.type),
            title: title,
            body: body ?? "",
            url: TextCheck.nonBlank(url),
            read: read,
            createdAt: DateParsing.parseInstant(createdAt)
        )
    }
}

nonisolated extension NotificationsPageDTO {
    func toDomain() -> NotificationPage {
        NotificationPage(
            items: notifications.map { $0.toDomain() },
            unreadCount: unreadCount,
            total: total,
            page: page,
            totalPages: totalPages,
            topic: topic
        )
    }
}
