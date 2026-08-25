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
/**
 * UPDATE y START_OVER son las dos salidas del picker que aparece cuando el orden
 * de lectura ya se usó en una review. UPDATE es el MISMO comando que CREATE -- el
 * verbo reconcilia en vez de negarse -- y START_OVER es ese comando con --force.
 */
enum class DraftStep { CREATE, RESUME, UPDATE, START_OVER }

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
    OfferId.WALK to OfferMeta("Walkthrough", "guided reading order from the PR", ReviewLayout.WALK),
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

/**
 * Lo que dice la fila del borrador cuando su review YA cerró. La de siempre
 * describe un orden a medio escribir, y sobre uno terminado y ya usado es
 * sencillamente falso: lo que sigue no es terminarlo sino reconciliarlo con lo
 * que el PR cambió desde entonces, o empezar uno nuevo.
 */
private val SPENT_RESUME_META = Pair(
    "Reuse the reading order you wrote",
    "you already reviewed with it; update it for what changed, or start over",
)

/**
 * @param spentDraft si el borrador de esta rama tiene su review cerrada, que es
 *   lo único que cambia la copy de DRAFT_RESUME. Lo dice la CLI en el campo
 *   `state` del registro `draft`; acá no se deriva.
 */
@JvmOverloads
fun buildLayoutItems(offers: List<ReadingOffer>?, spentDraft: Boolean = false): List<LayoutPickItem> {
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
        val base = OFFER_META.getValue(id)
        val meta =
            if (id == OfferId.DRAFT_RESUME && spentDraft) {
                base.copy(label = SPENT_RESUME_META.first, description = SPENT_RESUME_META.second)
            } else {
                base
            }
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
