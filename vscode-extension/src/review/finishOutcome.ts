import type {ReviewState} from "./state";

export type FinishOutcome = "no-edits" | "pending";

/**
 * Decide qué informar tras un `git review finish [--onto-source]` que salió
 * con exit `0`, mirando ÚNICAMENTE el `ReviewState` ya refrescado — nunca el
 * `stdout`/`stderr` del propio `finish` (contracts/cli-invocation.md § "no
 * parsear la salida humana de ningún verbo"; tasks.md T050/T050a lo llaman
 * "la regla que más fácil se pierde").
 *
 * La señal es la presencia del registro `finish … pending` para `branch` en el
 * inventario (contracts/finish-state.md). Un finish exitoso — con o sin
 * ediciones que extraer — deja ese registro y aterriza en el destino
 * (`review-fixes/<src>` o la rama del PR): el extract vacío también es un
 * cierre pendiente (nada staged, undo vivo para `finish --abort`). La ausencia
 * del registro tras exit 0 es el caso residual "sin cierre" (p. ej. un camino
 * viejo o un estado raro); se informa igual como resultado normal, no como
 * error. `finishReview.ts` es el único llamador.
 */
export function finishOutcome(refreshed: ReviewState, branch: string): FinishOutcome {
    const pending = refreshed.branches.some((b) => b.name === branch && b.finish?.state === "pending");
    return pending ? "pending" : "no-edits";
}
