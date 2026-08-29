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
/**
 * Invocar `walkthrough draft`. `force` es la diferencia entre reconciliar lo
 * que hay —conservando cada why cuyo archivo sigue en rango— y tirarlo para
 * escribir un esqueleto en blanco.
 */
    | { kind: "create"; force: boolean; update: boolean }
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
 * Los tres puntos de entrada, y sólo dos de ellos invocan algo:
 *
 * - `create` — no hay archivo: se escribe el esqueleto.
 * - `resume` — hay uno a medio escribir y se usa tal cual. No se invoca nada,
 *   así que el asistente ya terminó.
 * - `update` — hay uno que quedó desfasado del rango y se reconcilia con el de
 *   hoy. Es el MISMO comando que `create`: el verbo actualiza en vez de
 *   negarse, así que cada entrada cuyo archivo sigue en rango conserva su
 *   número, su why y su `> key`, y los que entraron llegan como placeholders.
 *
 * No hay `start-over`, y la ausencia es deliberada. Existió como la otra mitad
 * de un modal que preguntaba, sobre cualquier borrador ya usado, si reconciliar
 * o empezar de cero. Ese modal se retiró: la CLI ahora ofrece `draft-update`
 * sólo cuando hay algo que reconciliar, así que no queda pregunta que hacer.
 * Empezar de cero es lo único que destruye prosa escrita a mano y con el modal
 * quedaba a un clic de distancia en un paso por el que se pasaba de largo; sigue
 * disponible como lo que es —un acto deliberado— con Discard en la fila del
 * borrador, o con `walkthrough draft --force` desde la terminal.
 */
export type DraftStep = "create" | "resume" | "update";

export function initialDraftFlowState(step: DraftStep): DraftFlowState {
    switch (step) {
        case "resume":
            return {kind: "done"};
        default:
            // `update` viaja en el estado porque decide el ACUSE, no el argv:
            // los dos pasos corren el mismo comando, y lo unico que los separa
            // es si el panel ya contesta lo que el verbo tiene para decir.
            return {kind: "create", force: false, update: step === "update"};
    }
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
 * Los tres números de un `update`, leídos del registro `merged` que emite
 * `walkthrough draft --porcelain`.
 *
 * Este registro existe porque son lo ÚNICO que el verbo dice y ninguna fila
 * contesta: la del borrador muestra el par annotated/total nuevo, nunca lo que
 * se movió para llegar ahí. La frase humana los trae también, pero leerla sería
 * parsear salida humana — el camino que este archivo tenía y que
 * `contracts/cli-invocation.md` prohíbe.
 *
 * `undefined` cuando el registro no está (una CLI vieja, un `--build`, un
 * `--stdout`): el llamador se calla, que es la degradación correcta —una
 * mutación sin acuse molesta menos que un acuse inventado.
 */
export function parseMergedRecord(
    stdout: string
): { kept: number; added: number; dropped: number } | undefined {
    for (const line of stdout.split("\n")) {
        const fields = line.trim().split("\t");
        if (fields[0] !== "merged" || fields.length < 4) {
            continue;
        }
        const [kept, added, dropped] = fields.slice(1, 4).map((field) => Number(field));
        if (!Number.isInteger(kept) || !Number.isInteger(added) || !Number.isInteger(dropped)) {
            return undefined;
        }
        return {kept, added, dropped};
    }
    return undefined;
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
