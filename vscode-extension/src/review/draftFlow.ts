/**
 * El bucle del borrador del revisor (011, contracts/client-draft-flow.md):
 * crear → abrir → esperar → validar → recargar ofertas → elegir → confirmar.
 *
 * Lógica pura, sin `vscode`, por la misma razón que `layoutOffers` y
 * `reviewIntent`: lo que hay que poder probar sin editor es *cuándo* se
 * reintenta, cuándo se vuelve atrás y cuándo se pregunta por las esenciales —
 * no cómo se dibuja el aviso. El plugin de IntelliJ porta esta misma máquina
 * (`DraftFlow.kt`), y la paridad se sostiene si el estado vive acá y no
 * repartido por los dos hosts.
 */

import {ReadingOffer} from "../cli/configPorcelain";
import {ReviewLayout} from "./reviewIntent";

export type DraftFlowState =
/** Invocar `walkthrough draft` (sólo cuando el revisor eligió `draft`). */
    | { kind: "create" }
    /** Abrir el borrador en el editor; el archivo ya existe. */
    | { kind: "open" }
    /**
     * El aviso no bloqueante. `error` es el stderr del `--build` que acaba de
     * fallar: se muestra junto al aviso y el revisor vuelve a intentar sin
     * límite (requisito 3 del contrato).
     */
    | { kind: "wait"; error?: string }
    /** Invocar `walkthrough draft --build`. */
    | { kind: "build" }
    /** Releer `config --porcelain` para saber si el borrador trae esenciales. */
    | { kind: "reload" }
    /** Preguntar recorrido completo vs sólo esenciales. */
    | { kind: "pickKeys" }
    /** Seguir con el asistente normal (confirmación + start) con este layout. */
    | { kind: "done"; layout: ReviewLayout }
    /**
     * Volver al paso de forma de lectura. El borrador **no** se borra: la
     * siguiente vuelta lo ofrece como `draft-resume` (FR-018a). `error` sólo
     * cuando se vuelve por un fallo, nunca al cancelar.
     */
    | { kind: "back"; error?: string };

export type DraftFlowEvent =
/** Resultado de `walkthrough draft`. */
    | { kind: "created"; ok: boolean; error?: string }
    /** El borrador quedó a la vista (o no se pudo abrir: el bucle sigue igual). */
    | { kind: "opened" }
    /** El revisor apretó Continue en el aviso. */
    | { kind: "continue" }
    /** El revisor apretó Cancel. */
    | { kind: "cancel" }
    /**
     * El aviso se cerró sin elegir (la X, o un "clear all notifications").
     * **No** es Cancel: descartar una notificación es lo más fácil de hacer sin
     * querer mientras se edita el archivo que el aviso pide editar, y no es una
     * respuesta a la pregunta. El bucle se queda donde está y vuelve a
     * preguntar; sólo Cancel abandona.
     */
    | { kind: "dismiss" }
    /** Resultado de `walkthrough draft --build`. */
    | { kind: "built"; ok: boolean; error?: string }
    /** Ofertas recargadas tras un `--build` en verde. */
    | { kind: "offers"; offers: readonly ReadingOffer[] | undefined }
    /** `undefined` = el revisor cerró el selector de esenciales. */
    | { kind: "keysPicked"; keysOnly: boolean | undefined };

/**
 * Dónde arranca el bucle: `resume` salta la creación porque el borrador ya
 * existe — volver a crearlo pisaría lo que el revisor ya escribió, que es
 * justamente lo que `--force` existe para pedir a mano.
 */
export function initialDraftFlowState(step: "create" | "resume"): DraftFlowState {
    return step === "create" ? {kind: "create"} : {kind: "open"};
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
                    return {kind: "open"};
                }
                // Sin borrador no hay nada que esperar ni que reintentar: el
                // fallo es de la CLI (rango irresoluble, borrador existente sin
                // --force) y se resuelve fuera del asistente.
                return event.error !== undefined
                    ? {kind: "back", error: event.error}
                    : {kind: "back"};
            }
            return state;

        case "open":
            return event.kind === "opened" ? {kind: "wait"} : state;

        case "wait":
            if (event.kind === "continue") {
                return {kind: "build"};
            }
            if (event.kind === "cancel") {
                return {kind: "back"};
            }
            // `dismiss` cae acá y devuelve el mismo estado —con su error, si lo
            // traía—, de modo que el host vuelve a mostrar el aviso. Es el
            // equivalente al diálogo persistente del plugin de IntelliJ: se sale
            // del bucle por Cancel, no por descartar una notificación.
            return state;

        case "build":
            if (event.kind === "built") {
                if (event.ok) {
                    return {kind: "reload"};
                }
                // El motivo del rechazo vuelve al aviso, que queda disponible de
                // nuevo: el revisor corrige el borrador —que sigue byte por byte
                // como lo dejó— y reintenta.
                return event.error !== undefined ? {
                    kind: "wait",
                    error: event.error
                } : {kind: "wait"};
            }
            return state;

        case "reload":
            if (event.kind === "offers") {
                // Sólo se pregunta si hay algo que elegir (FR-019): un borrador
                // sin ninguna entrada marcada key no tiene dos recorridos.
                return offersIncludeKeys(event.offers) ? {kind: "pickKeys"} : {
                    kind: "done",
                    layout: "walk"
                };
            }
            return state;

        case "pickKeys":
            if (event.kind === "keysPicked") {
                if (event.keysOnly === undefined) {
                    return {kind: "back"};
                }
                return {kind: "done", layout: event.keysOnly ? "keys" : "walk"};
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
 * El texto del aviso de espera. `unopened` viaja **sólo** cuando el editor no
 * pudo mostrar el borrador: en ese caso el aviso pide llenar un archivo que el
 * revisor no tiene delante, y la ruta no aparece en ninguna otra parte de la UI
 * —la CLI la imprime por stdout y los dos clientes muestran únicamente stderr—,
 * así que el aviso es el único lugar donde puede decirla.
 *
 * Ocurre cuando el workspace abierto no es el toplevel del repo (una subcarpeta
 * de un monorepo): `<cwd>/.git` no existe, no hay gitdir que resolver y el
 * archivo se escribió igual. Sin esto el asistente pedía editar algo sin decir
 * qué ni dónde.
 */
export function draftWaitMessage(
    branch: string,
    error: string | undefined,
    unopened: { file?: string } | undefined
): string {
    const head =
        error !== undefined
            ? `The draft is not valid yet: ${error}`
            : `Fill in the reading order for ${branch}, then continue.`;
    if (unopened === undefined) {
        return head;
    }
    // El motivo del rechazo viene de la CLI y no siempre cierra la oración, así
    // que la frase que sigue arrancaba pegada a la anterior ("...no entries found
    // It could not be opened here"). Se cierra acá y no en el head, que cuando va
    // solo se muestra tal cual lo escribió la CLI.
    const lead = head.endsWith(".") ? head : `${head}.`;
    if (unopened.file !== undefined) {
        return `${lead} It could not be opened here — the draft is at ${unopened.file}.`;
    }
    // Ni la ruta se pudo armar (no hay gitdir que resolver desde este cwd). Se
    // dice el nombre relativo, que es estable, en vez de callar.
    return `${lead} It could not be opened here — look for review-walkthrough/${branch}.md inside this repository's git directory.`;
}

/** Si la CLI volvió a ofrecer `keys` sobre el borrador ya validado. */
export function offersIncludeKeys(offers: readonly ReadingOffer[] | undefined): boolean {
    return offers !== undefined && offers.some((offer) => offer.id === "keys");
}

/**
 * Si dos rutas nombran el mismo archivo, para encontrar entre los documentos
 * abiertos el borrador que el asistente escribió — y guardarlo antes de que
 * `draft --build` lo lea del disco.
 *
 * No es `===`: la ruta se arma con `path.join` y el editor devuelve la suya
 * pasada por `Uri.file`, que normaliza separadores y baja la letra de unidad.
 * En Windows las dos cadenas nombran el mismo archivo y se comparan distinto,
 * y de esa comparación depende que el borrador llegue al disco: fallarla no da
 * un error, da una validación silenciosa del archivo sin guardar.
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

/**
 * El gitdir apuntado por un `.git` que es un **archivo** y no un directorio:
 * el caso de `git worktree` y de los submódulos. Formato de git: una única
 * línea `gitdir: <path>`, absoluta o relativa al directorio que la contiene.
 *
 * Se resuelve acá y no invocando `git rev-parse --git-dir` para no agregar un
 * proceso al asistente por un dato que el propio repositorio deja escrito. No
 * es derivar estado de review: es dónde está el repositorio, lo mismo que ya
 * hace `watchGitDirFallback` mirando `.git/HEAD`.
 */
export function gitdirFromLink(content: string): string | undefined {
    const match = /^gitdir:\s*(.+?)\s*$/m.exec(content);
    if (!match) {
        return undefined;
    }
    const target = match[1];
    return target.length > 0 ? target : undefined;
}
