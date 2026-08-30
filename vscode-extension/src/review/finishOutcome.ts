import type {ReviewState} from "./state";

export type FinishOutcome = "no-edits" | "pending";

/**
 * Decide qué informar tras un `finish` con exit `0` mirando ÚNICAMENTE el
 * `ReviewState` ya refrescado, nunca el `stdout`/`stderr` del propio verbo
 * (contracts/cli-invocation.md § "no parsear la salida humana de ningún verbo").
 *
 * La señal es el registro `finish … pending` para `branch` en el inventario
 * (contracts/finish-state.md): un finish exitoso —con o sin ediciones— lo deja
 * y aterriza en destino (`review-fixes/<src>` o la rama del PR); el extract
 * vacío también es un cierre pendiente (nada staged, undo vivo para
 * `finish --abort`). Su ausencia tras exit 0 es el caso residual "sin cierre"
 * (un camino viejo o un estado raro): se informa igual como resultado normal,
 * no como error. `finishReview.ts` es el único llamador.
 */
export function finishOutcome(refreshed: ReviewState, branch: string): FinishOutcome {
    const pending = refreshed.branches.some((b) => b.name === branch && b.finish?.state === "pending");
    return pending ? "pending" : "no-edits";
}
