package com.ezevillo.gitreview.domain

/**
 * Lo que queda del camino del borrador dentro del asistente: crear, y terminar.
 * No espera nada -- lo que hacían `Build`, `Reload` y `PickKeys` vive ahora en
 * *Validate and start*, un control del panel sobre un estado que sobrevive a
 * cerrar el IDE.
 *
 * Tampoco abre el borrador, y por eso no necesita su ruta: en el instante
 * posterior a crearlo todavía no hay registro `draft` que la traiga, así que
 * abrir ahí exigiría una invocación extra o volver a armar la ruta a mano. El
 * refresco post-mutación que ya existe trae la fila con su `<path>` un instante
 * después.
 *
 * Dominio puro, sin la plataforma IntelliJ.
 */
sealed class DraftFlowState {
    /**
     * Invocar `walkthrough draft`. [force] es la diferencia entre reconciliar lo
     * que hay —conservando cada why cuyo archivo sigue en rango— y tirarlo para
     * escribir un esqueleto en blanco.
     */
    data class Create(val force: Boolean = false, val update: Boolean = false) : DraftFlowState()

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
 * Los tres puntos de entrada, y sólo dos de ellos invocan algo:
 *
 * - CREATE — no hay archivo: se escribe el esqueleto.
 * - RESUME — hay uno a medio escribir y se usa tal cual. No se invoca nada, así
 *   que el asistente ya terminó.
 * - UPDATE — hay uno que quedó desfasado del rango y se reconcilia con el de
 *   hoy. Es el MISMO comando que CREATE: el verbo actualiza en vez de negarse.
 *
 * No hay START_OVER, y la ausencia es deliberada: la CLI ofrece `draft-update`
 * sólo cuando hay algo que reconciliar, así que no queda pregunta que hacer.
 * Empezar de cero sigue disponible como acto deliberado -- con Discard en la
 * fila del borrador, o `walkthrough draft --force` desde la terminal -- nunca
 * como default de un paso por el que se pasa de largo.
 */
fun initialDraftFlowState(step: DraftStep): DraftFlowState = when (step) {
    DraftStep.RESUME -> DraftFlowState.Done
    // `update` no toca el argv, sólo decide el acuse (ver StartWizard.invokeDraft).
    else -> DraftFlowState.Create(update = step == DraftStep.UPDATE)
}

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

/** Los tres numeros de un `update`, tal como los cuenta el registro `merged`. */
data class MergedCounts(val kept: Int, val added: Int, val dropped: Int)

/**
 * Lee el registro `merged` que emite `walkthrough draft --porcelain`.
 *
 * Existe porque esos tres numeros son lo UNICO que el verbo dice y ninguna fila
 * contesta: la del borrador muestra el par annotated/total nuevo, nunca lo que
 * se movio para llegar ahi. La frase humana los trae tambien, pero leerla seria
 * parsear salida humana -- el camino que este cliente tenia y que su contrato de
 * invocacion prohibe.
 *
 * `null` cuando el registro no esta (una CLI vieja, un `--build`, un
 * `--stdout`): el llamador se calla, que es la degradacion correcta -- una
 * mutacion sin acuse molesta menos que un acuse inventado.
 */
fun parseMergedRecord(stdout: String): MergedCounts? {
    for (line in stdout.split("\n")) {
        val fields = line.trim().split("\t")
        if (fields.size < 4 || fields[0] != "merged") continue
        val kept = fields[1].toIntOrNull() ?: return null
        val added = fields[2].toIntOrNull() ?: return null
        val dropped = fields[3].toIntOrNull() ?: return null
        return MergedCounts(kept, added, dropped)
    }
    return null
}
