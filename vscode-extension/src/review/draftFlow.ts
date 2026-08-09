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
    | {kind: "create"}
    /** Abrir el borrador en el editor; el archivo ya existe. */
    | {kind: "open"}
    /**
     * El aviso no bloqueante. `error` es el stderr del `--build` que acaba de
     * fallar: se muestra junto al aviso y el revisor vuelve a intentar sin
     * límite (requisito 3 del contrato).
     */
    | {kind: "wait"; error?: string}
    /** Invocar `walkthrough draft --build`. */
    | {kind: "build"}
    /** Releer `config --porcelain` para saber si el borrador trae esenciales. */
    | {kind: "reload"}
    /** Preguntar recorrido completo vs sólo esenciales. */
    | {kind: "pickKeys"}
    /** Seguir con el asistente normal (confirmación + start) con este layout. */
    | {kind: "done"; layout: ReviewLayout}
    /**
     * Volver al paso de forma de lectura. El borrador **no** se borra: la
     * siguiente vuelta lo ofrece como `draft-resume` (FR-018a). `error` sólo
     * cuando se vuelve por un fallo, nunca al cancelar.
     */
    | {kind: "back"; error?: string};

export type DraftFlowEvent =
    /** Resultado de `walkthrough draft`. */
    | {kind: "created"; ok: boolean; error?: string}
    /** El borrador quedó a la vista (o no se pudo abrir: el bucle sigue igual). */
    | {kind: "opened"}
    /** El revisor apretó Continue en el aviso. */
    | {kind: "continue"}
    /** El revisor apretó Cancel, o descartó el aviso. */
    | {kind: "cancel"}
    /** Resultado de `walkthrough draft --build`. */
    | {kind: "built"; ok: boolean; error?: string}
    /** Ofertas recargadas tras un `--build` en verde. */
    | {kind: "offers"; offers: readonly ReadingOffer[] | undefined}
    /** `undefined` = el revisor cerró el selector de esenciales. */
    | {kind: "keysPicked"; keysOnly: boolean | undefined};

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
            return state;

        case "build":
            if (event.kind === "built") {
                if (event.ok) {
                    return {kind: "reload"};
                }
                // El motivo del rechazo vuelve al aviso, que queda disponible de
                // nuevo: el revisor corrige el borrador —que sigue byte por byte
                // como lo dejó— y reintenta.
                return event.error !== undefined ? {kind: "wait", error: event.error} : {kind: "wait"};
            }
            return state;

        case "reload":
            if (event.kind === "offers") {
                // Sólo se pregunta si hay algo que elegir (FR-019): un borrador
                // sin ninguna entrada marcada key no tiene dos recorridos.
                return offersIncludeKeys(event.offers) ? {kind: "pickKeys"} : {kind: "done", layout: "walk"};
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

/** Si la CLI volvió a ofrecer `keys` sobre el borrador ya validado. */
export function offersIncludeKeys(offers: readonly ReadingOffer[] | undefined): boolean {
    return offers !== undefined && offers.some((offer) => offer.id === "keys");
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
