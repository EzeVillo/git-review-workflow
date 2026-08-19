/**
 * Lo que queda del camino del borrador dentro del asistente (012,
 * contracts/client-draft-panel.md § 3): crear, y terminar.
 *
 * Antes había un bucle: crear → abrir → **esperar** → validar → recargar
 * ofertas → elegir esenciales. La espera era una notificación que quedaba
 * abierta mientras el revisor escribía su orden de lectura, y todo lo que venía
 * después dependía de que esa notificación siguiera ahí — se descartaba sin
 * querer con un "clear all notifications" mientras se editaba justamente el
 * archivo que pedía editar. Lo que hacían `build`, `reload` y `pickKeys` vive
 * ahora en *Validate and start*, un control del panel, sobre un estado que
 * sobrevive a cerrar el editor. El asistente no espera nada.
 *
 * Tampoco abre el borrador, y por eso ya no necesita su ruta: en el instante
 * posterior a crearlo todavía no hay registro `draft` que la traiga, así que
 * abrir ahí exigiría o una invocación extra o volver a armar la ruta — que es
 * exactamente lo que esta feature retira. El refresco post-mutación que ya
 * existe trae la fila con su `<path>` un instante después, y el revisor abre
 * desde el panel.
 *
 * Lógica pura, sin `vscode`, por la misma razón que `layoutOffers` y
 * `reviewIntent`: el plugin de IntelliJ y la extensión de Visual Studio portan
 * esta misma máquina, y la paridad se sostiene si el estado vive acá.
 */

import {ReadingOffer} from "../cli/configPorcelain";

export type DraftFlowState =
/** Invocar `walkthrough draft` (sólo cuando el revisor eligió `draft`). */
    | { kind: "create" }
    /**
     * El asistente terminó. No hay review empezada y no queda ningún aviso
     * abierto: el borrador está en el panel, con sus cuatro controles.
     */
    | { kind: "done" }
    /**
     * Volver al paso de forma de lectura, sin rehacer la elección de rama. El
     * borrador **no** se borra: la siguiente vuelta lo ofrece como
     * `draft-resume`. `error` sólo cuando se vuelve por un fallo.
     */
    | { kind: "back"; error?: string };

export type DraftFlowEvent =
/** Resultado de `walkthrough draft`. */
    { kind: "created"; ok: boolean; error?: string };

/**
 * Dónde arranca: `resume` no crea nada — el archivo ya existe y volver a
 * crearlo pisaría lo que el revisor escribió, que es justamente lo que
 * `--force` existe para pedir a mano. Con nada que crear, el asistente ya
 * terminó.
 */
export function initialDraftFlowState(step: "create" | "resume"): DraftFlowState {
    return step === "create" ? {kind: "create"} : {kind: "done"};
}

/**
 * Transición. Un evento que no corresponde al estado actual lo deja intacto:
 * la máquina no inventa caminos, y el host no puede saltearse un paso por
 * mandar el evento equivocado.
 */
export function advanceDraftFlow(state: DraftFlowState, event: DraftFlowEvent): DraftFlowState {
    switch (state.kind) {
        case "create":
            if (event.kind === "created") {
                if (event.ok) {
                    return {kind: "done"};
                }
                // Sin borrador no hay nada que mostrar en el panel: el fallo es
                // de la CLI (rango irresoluble, borrador existente sin --force)
                // y el revisor vuelve al paso de forma de lectura para elegir
                // otra cosa, sin rehacer la elección de rama.
                return event.error !== undefined
                    ? {kind: "back", error: event.error}
                    : {kind: "back"};
            }
            return state;

        case "done":
        case "back":
            return state;

        default: {
            const _exhaustive: never = state;
            return _exhaustive;
        }
    }
}

/**
 * Si la CLI ofrece `keys` sobre un borrador ya validado — o sea si trae
 * entradas marcadas esenciales y hay dos recorridos posibles que ofrecer.
 * Lo consume *Validate and start*, que es quien pregunta ahora.
 */
export function offersIncludeKeys(offers: readonly ReadingOffer[] | undefined): boolean {
    return offers !== undefined && offers.some((offer) => offer.id === "keys");
}

/**
 * Si dos rutas nombran el mismo archivo, para encontrar entre los documentos
 * abiertos el borrador que hay que guardar antes de que `draft --build` lo lea
 * del disco.
 *
 * No es `===`: la ruta llega de la CLI y el editor devuelve la suya pasada por
 * `Uri.file`, que normaliza separadores y baja la letra de unidad. En Windows
 * las dos cadenas nombran el mismo archivo y se comparan distinto, y de esa
 * comparación depende que el borrador llegue al disco: fallarla no da un error,
 * da una validación silenciosa del archivo sin guardar.
 *
 * El sistema se pasa en vez de leerse acá, como en `userDataDir`, para que la
 * regla de Windows se pueda probar desde cualquier runner.
 */
export function sameDraftFile(a: string, b: string, platform: string = process.platform): boolean {
    const normalise = (p: string): string => {
        const slashed = p.replace(/\\/g, "/");
        return platform === "win32" ? slashed.toLowerCase() : slashed;
    };
    return normalise(a) === normalise(b);
}
