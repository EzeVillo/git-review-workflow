package com.ezevillo.gitreview.domain

/**
 * Lo que queda del camino del borrador dentro del asistente (012,
 * contracts/client-draft-panel.md § 3): crear, y terminar.
 *
 * Antes había un bucle: crear → abrir → **esperar** → validar → recargar
 * ofertas → elegir esenciales. La espera era un diálogo que se quedaba abierto
 * mientras el revisor escribía su orden de lectura, y todo lo que venía después
 * dependía de que ese diálogo siguiera ahí. Lo que hacían `Build`, `Reload` y
 * `PickKeys` vive ahora en *Validate and start*, un control del panel, sobre un
 * estado que sobrevive a cerrar el IDE. El asistente no espera nada.
 *
 * Tampoco abre el borrador, y por eso ya no necesita su ruta: en el instante
 * posterior a crearlo todavía no hay registro `draft` que la traiga, así que
 * abrir ahí exigiría o una invocación extra o volver a armar la ruta — que es
 * exactamente lo que esta feature retira. El refresco post-mutación que ya
 * existe trae la fila con su `<path>` un instante después.
 *
 * Dominio puro, sin la plataforma IntelliJ, y los mismos estados y transiciones
 * que `draftFlow.ts` en la extensión y `DraftFlow.cs` en Visual Studio: la
 * paridad de producto se sostiene si las transiciones viven en un solo lugar
 * por cliente y se prueban igual, no si cada host las reinventa.
 */
sealed class DraftFlowState {
    /** Invocar `walkthrough draft` (sólo cuando el revisor eligió DRAFT). */
    data object Create : DraftFlowState()

    /**
     * El asistente terminó. No hay review empezada y no queda ningún aviso
     * abierto: el borrador está en el panel, con sus cuatro controles.
     */
    data object Done : DraftFlowState()

    /**
     * Volver al paso de forma de lectura, sin rehacer la elección de rama. El
     * borrador **no** se borra: la siguiente vuelta lo ofrece como
     * DRAFT_RESUME. [error] sólo cuando se vuelve por un fallo.
     */
    data class Back(val error: String? = null) : DraftFlowState()
}

sealed class DraftFlowEvent {
    /** Resultado de `walkthrough draft`. */
    data class Created(val ok: Boolean, val error: String? = null) : DraftFlowEvent()
}

/**
 * Dónde arranca: RESUME no crea nada — el archivo ya existe y volver a crearlo
 * pisaría lo que el revisor escribió, que es justamente lo que `--force` existe
 * para pedir a mano. Sin nada que crear, el asistente ya terminó.
 */
fun initialDraftFlowState(step: DraftStep): DraftFlowState =
    if (step == DraftStep.CREATE) DraftFlowState.Create else DraftFlowState.Done

/**
 * Transición. Un evento que no corresponde al estado actual lo deja intacto:
 * la máquina no inventa caminos, y el host no puede saltearse un paso por
 * mandar el evento equivocado.
 */
fun advanceDraftFlow(state: DraftFlowState, event: DraftFlowEvent): DraftFlowState = when (state) {
    is DraftFlowState.Create ->
        if (event is DraftFlowEvent.Created) {
            // Sin borrador no hay nada que mostrar en el panel: el fallo es de
            // la CLI y el revisor vuelve al paso de forma de lectura.
            if (event.ok) DraftFlowState.Done else DraftFlowState.Back(event.error)
        } else {
            state
        }

    is DraftFlowState.Done -> state
    is DraftFlowState.Back -> state
}

/**
 * Si la CLI ofrece `keys` sobre un borrador ya validado — o sea si trae
 * entradas marcadas esenciales y hay dos recorridos que ofrecer. Lo consume
 * *Validate and start*, que es quien pregunta ahora.
 */
fun offersIncludeKeys(offers: List<ReadingOffer>?): Boolean =
    offers != null && offers.any { it.id == OfferId.KEYS }
