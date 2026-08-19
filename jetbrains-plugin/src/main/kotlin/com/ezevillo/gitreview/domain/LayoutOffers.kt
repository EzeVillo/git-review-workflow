package com.ezevillo.gitreview.domain

/** Fallback when the CLI emits no `offer` rows. */
val FALLBACK_OFFERS: List<ReadingOffer> = listOf(
    ReadingOffer(OfferId.STEP, OfferRank.AVAILABLE),
    ReadingOffer(OfferId.WHOLE, OfferRank.AVAILABLE),
)

/**
 * Elegir DRAFT no es elegir una forma distinta de leer: es escribir el orden
 * que después se lee como walkthrough. Por eso el ítem lleva igual su `layout`
 * —el que quedaría si el borrador se completa— y `draft` marca el desvío por el
 * bucle de armado antes de llegar a start.
 */
enum class DraftStep { CREATE, RESUME }

data class LayoutPickItem(
    val label: String,
    val description: String,
    val layout: ReviewLayout,
    val draft: DraftStep? = null,
)

private data class OfferMeta(
    val label: String,
    val description: String,
    val layout: ReviewLayout,
    val draft: DraftStep? = null,
)

private val OFFER_META: Map<OfferId, OfferMeta> = mapOf(
    OfferId.WALK to OfferMeta("Walkthrough", "curated reading order from the PR", ReviewLayout.WALK),
    OfferId.KEYS to OfferMeta("Walkthrough — keys only", "only entries marked key", ReviewLayout.KEYS),
    // Sin la palabra "walkthrough" como si fuera un término conocido: estas dos
    // son las únicas ofertas que no eligen una forma de leer sino que arman la
    // que el PR no trae, y quien las lee todavía no sabe qué es un walkthrough.
    // Byte por byte iguales en los tres clientes.
    OfferId.DRAFT to OfferMeta(
        "Build a reading order first",
        "nobody wrote one for this PR; otherwise you read the whole diff",
        ReviewLayout.WALK,
        DraftStep.CREATE,
    ),
    OfferId.DRAFT_RESUME to OfferMeta(
        "Finish the reading order you started",
        "pick up the one you left half-written",
        ReviewLayout.WALK,
        DraftStep.RESUME,
    ),
    OfferId.STEP to OfferMeta("Commit by commit", "one commit at a time (--step)", ReviewLayout.STEP),
    OfferId.WHOLE to OfferMeta("Whole diff", "entire diff at once", ReviewLayout.WHOLE),
)

private val OFFER_ORDER =
    listOf(OfferId.WALK, OfferId.KEYS, OfferId.DRAFT, OfferId.DRAFT_RESUME, OfferId.STEP, OfferId.WHOLE)

fun effectiveOffers(offers: List<ReadingOffer>?): List<ReadingOffer> {
    if (offers.isNullOrEmpty()) return FALLBACK_OFFERS.toList()
    return offers
}

fun buildLayoutItems(offers: List<ReadingOffer>?): List<LayoutPickItem> {
    val list = effectiveOffers(offers)
    val byId = LinkedHashMap<OfferId, OfferRank>()
    for (o in list) byId[o.id] = o.rank

    val ordered = ArrayList<OfferId>()
    for (id in OFFER_ORDER) {
        if (byId[id] == OfferRank.RECOMMENDED) ordered.add(id)
    }
    for (id in OFFER_ORDER) {
        if (byId.containsKey(id) && byId[id] != OfferRank.RECOMMENDED) ordered.add(id)
    }

    return ordered.map { id ->
        val meta = OFFER_META.getValue(id)
        val rank = byId[id] ?: OfferRank.AVAILABLE
        val description =
            if (rank == OfferRank.RECOMMENDED) "${meta.description} (recommended)" else meta.description
        val label =
            if (rank == OfferRank.RECOMMENDED) "${meta.label} (recommended)" else meta.label
        LayoutPickItem(
            label = label,
            description = description,
            layout = meta.layout,
            draft = meta.draft,
        )
    }
}

fun layoutSummary(layout: ReviewLayout): String = when (layout) {
    ReviewLayout.WALK -> "as a walkthrough"
    ReviewLayout.KEYS -> "keys only"
    ReviewLayout.STEP -> "commit by commit"
    ReviewLayout.WHOLE -> "as the whole diff"
}

fun offerConfigFlags(source: ReviewSource, range: ReviewRange): List<String> {
    val flags = ArrayList<String>()
    when (source) {
        ReviewSource.LOCAL -> flags.add("--local")
        ReviewSource.OFFLINE -> flags.add("--offline")
        ReviewSource.REMOTE -> {}
    }
    if (range == ReviewRange.DELTA) flags.add("--delta")
    return flags
}
