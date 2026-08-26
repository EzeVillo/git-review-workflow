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
enum class DraftStep { CREATE, RESUME, UPDATE }

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
    // La CLI manda ésta en lugar de DRAFT_RESUME cuando el borrador quedó
    // desfasado del rango. Antes las dos situaciones llegaban indistinguibles y
    // el asistente preguntaba con un modal cuál era — o sea le pedía al revisor
    // un dato que sólo la CLI tiene, y cuando la respuesta era "no se movió
    // nada" la reconciliación era un no-op que terminaba en una fila sin
    // Validate and start.
    OfferId.DRAFT_UPDATE to OfferMeta(
        "Update the reading order you wrote",
        "the PR moved on; keeps the whys whose files are still in range",
        ReviewLayout.WALK,
        DraftStep.UPDATE,
    ),
    OfferId.STEP to OfferMeta("Commit by commit", "one commit at a time (--step)", ReviewLayout.STEP),
    OfferId.WHOLE to OfferMeta("Whole diff", "entire diff at once", ReviewLayout.WHOLE),
)

private val OFFER_ORDER =
    listOf(
        OfferId.WALK,
        OfferId.KEYS,
        OfferId.DRAFT,
        OfferId.DRAFT_RESUME,
        OfferId.DRAFT_UPDATE,
        OfferId.STEP,
        OfferId.WHOLE,
    )

fun effectiveOffers(offers: List<ReadingOffer>?): List<ReadingOffer> {
    if (offers.isNullOrEmpty()) return FALLBACK_OFFERS.toList()
    return offers
}

/**
 * Cuál de las dos filas del borrador se dibuja ya no se decide acá: la CLI manda
 * DRAFT_RESUME o DRAFT_UPDATE y cada una trae su copy fija.
 *
 * Antes esto miraba el `state` del registro `draft` para reescribir la copy de
 * DRAFT_RESUME cuando la review ya había cerrado. Ese campo contesta "¿ya se
 * leyó este orden?", no "¿sigue cubriendo el rango?", así que una rama que
 * avanzó después de su review y una que no se movió llegaban con el MISMO
 * `reviewed` — y la fila terminaba ofreciendo reconciliar un orden que no tenía
 * nada que reconciliar.
 */
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
