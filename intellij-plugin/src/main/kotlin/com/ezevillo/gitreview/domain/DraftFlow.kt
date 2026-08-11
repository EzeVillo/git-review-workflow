package com.ezevillo.gitreview.domain

/**
 * El bucle del borrador del revisor (011, contracts/client-draft-flow.md):
 * crear → abrir → esperar → validar → recargar ofertas → elegir → confirmar.
 *
 * Dominio puro, sin `com.intellij`, y los mismos estados y transiciones que
 * `draftFlow.ts` en la extensión: la paridad de producto entre los dos clientes
 * se sostiene si las transiciones viven en un solo lugar por cliente y se
 * prueban igual, no si cada host las reinventa entre sus diálogos.
 *
 * Con **un** evento de menos, a propósito: no hay `Dismiss`. En VS Code
 * descartar la notificación no es Cancel —se cierra sola con un *Clear All
 * Notifications*, que es fácil de apretar sin querer mientras se edita el
 * archivo que el aviso pide editar— y por eso allá el aviso se vuelve a mostrar.
 * Acá el vehículo es un `DialogWrapper`: nada lo cierra en masa, cerrarlo es un
 * acto sobre ese diálogo, y Swing entrega la cruz y el botón por el mismo
 * `doCancelAction`. Un `Dismiss` sería un estado que ningún host puede producir.
 * La divergencia está admitida en el contrato, junto a la del flujo síncrono.
 */
sealed class DraftFlowState {
    /** Invocar `walkthrough draft` (sólo cuando el revisor eligió DRAFT). */
    data object Create : DraftFlowState()

    /** Abrir el borrador en el editor; el archivo ya existe. */
    data object Open : DraftFlowState()

    /**
     * El aviso no bloqueante. [error] es el stderr del `--build` que acaba de
     * fallar: se muestra junto al aviso y el revisor reintenta sin límite.
     */
    data class Wait(val error: String? = null) : DraftFlowState()

    /** Invocar `walkthrough draft --build`. */
    data object Build : DraftFlowState()

    /** Releer `config --porcelain` para saber si el borrador trae esenciales. */
    data object Reload : DraftFlowState()

    /** Preguntar recorrido completo vs sólo esenciales. */
    data object PickKeys : DraftFlowState()

    /** Seguir con el asistente normal (confirmación + start) con este layout. */
    data class Done(val layout: ReviewLayout) : DraftFlowState()

    /**
     * Volver al paso de forma de lectura. El borrador **no** se borra: la
     * siguiente vuelta lo ofrece como DRAFT_RESUME. [error] sólo cuando se
     * vuelve por un fallo, nunca al cancelar.
     */
    data class Back(val error: String? = null) : DraftFlowState()
}

sealed class DraftFlowEvent {
    /** Resultado de `walkthrough draft`. */
    data class Created(val ok: Boolean, val error: String? = null) : DraftFlowEvent()

    /** El borrador quedó a la vista (o no se pudo abrir: el bucle sigue igual). */
    data object Opened : DraftFlowEvent()

    /** El revisor apretó Continue en el aviso. */
    data object Continue : DraftFlowEvent()

    /** El revisor apretó Cancel, o cerró el aviso. */
    data object Cancel : DraftFlowEvent()

    /** Resultado de `walkthrough draft --build`. */
    data class Built(val ok: Boolean, val error: String? = null) : DraftFlowEvent()

    /** Ofertas recargadas tras un `--build` en verde. */
    data class Offers(val offers: List<ReadingOffer>?) : DraftFlowEvent()

    /** `null` = el revisor cerró el selector de esenciales. */
    data class KeysPicked(val keysOnly: Boolean?) : DraftFlowEvent()
}

/**
 * Dónde arranca el bucle: RESUME salta la creación porque el borrador ya
 * existe — volver a crearlo pisaría lo que el revisor ya escribió, que es
 * justamente lo que `--force` existe para pedir a mano.
 */
fun initialDraftFlowState(step: DraftStep): DraftFlowState =
    if (step == DraftStep.CREATE) DraftFlowState.Create else DraftFlowState.Open

/**
 * Transición. Un evento que no corresponde al estado actual lo deja intacto:
 * la máquina no inventa caminos, y el host no puede saltearse un paso por
 * mandar el evento equivocado.
 */
fun advanceDraftFlow(state: DraftFlowState, event: DraftFlowEvent): DraftFlowState = when (state) {
    is DraftFlowState.Create ->
        if (event is DraftFlowEvent.Created) {
            // Sin borrador no hay nada que esperar ni que reintentar: el fallo
            // es de la CLI y se resuelve fuera del asistente.
            if (event.ok) DraftFlowState.Open else DraftFlowState.Back(event.error)
        } else {
            state
        }

    is DraftFlowState.Open ->
        if (event is DraftFlowEvent.Opened) DraftFlowState.Wait() else state

    is DraftFlowState.Wait -> when (event) {
        is DraftFlowEvent.Continue -> DraftFlowState.Build
        is DraftFlowEvent.Cancel -> DraftFlowState.Back()
        else -> state
    }

    is DraftFlowState.Build ->
        if (event is DraftFlowEvent.Built) {
            // El motivo del rechazo vuelve al aviso, que queda disponible de
            // nuevo: el revisor corrige el borrador —que sigue byte por byte
            // como lo dejó— y reintenta.
            if (event.ok) DraftFlowState.Reload else DraftFlowState.Wait(event.error)
        } else {
            state
        }

    is DraftFlowState.Reload ->
        if (event is DraftFlowEvent.Offers) {
            // Sólo se pregunta si hay algo que elegir: un borrador sin ninguna
            // entrada marcada key no tiene dos recorridos.
            if (offersIncludeKeys(event.offers)) {
                DraftFlowState.PickKeys
            } else {
                DraftFlowState.Done(ReviewLayout.WALK)
            }
        } else {
            state
        }

    is DraftFlowState.PickKeys ->
        if (event is DraftFlowEvent.KeysPicked) {
            when (event.keysOnly) {
                null -> DraftFlowState.Back()
                true -> DraftFlowState.Done(ReviewLayout.KEYS)
                false -> DraftFlowState.Done(ReviewLayout.WALK)
            }
        } else {
            state
        }

    is DraftFlowState.Done -> state
    is DraftFlowState.Back -> state
}

/** Si la CLI volvió a ofrecer `keys` sobre el borrador ya validado. */
fun offersIncludeKeys(offers: List<ReadingOffer>?): Boolean =
    offers != null && offers.any { it.id == OfferId.KEYS }

/**
 * El gitdir apuntado por un `.git` que es un **archivo** y no un directorio:
 * el caso de `git worktree` y de los submódulos. Formato de git: una única
 * línea `gitdir: <path>`, absoluta o relativa al directorio que la contiene.
 *
 * Se resuelve acá y no invocando `git rev-parse --git-dir` para no agregar un
 * proceso al asistente por un dato que el propio repositorio deja escrito.
 */
fun gitdirFromLink(content: String): String? {
    val match = Regex("""^gitdir:[ \t]*(.+?)[ \t\r]*$""", RegexOption.MULTILINE).find(content)
    return match?.groupValues?.get(1)?.takeIf { it.isNotEmpty() }
}
