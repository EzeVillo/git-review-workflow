import type {ReviewState} from "./state";

export type FinishOutcome = "no-edits" | "pending";

/**
 * Decide qué informar tras un `git review finish [--onto-source]` que salió
 * con exit `0`, mirando ÚNICAMENTE el `ReviewState` ya refrescado — nunca el
 * `stdout`/`stderr` del propio `finish` (contracts/cli-invocation.md § "no
 * parsear la salida humana de ningún verbo"; tasks.md T050/T050a lo llaman
 * "la regla que más fácil se pierde": la CLI dice con todas las letras "no
 * review changes to apply", y leer esa línea sería lo más corto).
 *
 * La señal es la ausencia/presencia del registro `finish … pending` para
 * `branch` en el inventario (contracts/finish-state.md): la CLI misma deshace
 * su propio punto de undo cuando no hubo ediciones que extraer
 * (`bin/git-review-verbs/finish:446-451`), así que un cierre sin ediciones
 * nunca deja ese registro — pero uno CON ediciones siempre lo deja, aunque el
 * exit haya sido `0` sin ninguna advertencia. `finishReview.ts` es el único
 * llamador: refresca el estado después de invocar y pasa el resultado acá.
 */
export function finishOutcome(refreshed: ReviewState, branch: string): FinishOutcome {
    const pending = refreshed.branches.some((b) => b.name === branch && b.finish?.state === "pending");
    return pending ? "pending" : "no-edits";
}
