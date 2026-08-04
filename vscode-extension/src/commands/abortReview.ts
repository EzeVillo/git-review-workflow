import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";
import {captureToken, tokenStillValid} from "../review/staleGuard";

/** El stderr de la CLI, aplanado a una línea para el toast del editor. */
function message(stderr: string): string {
    return stderr.split("\n").map((line) => line.trim()).filter((line) => line.length > 0).join(" ");
}

/**
 * `gitReview.abortReview`: cancela la review activa (contracts/cli-invocation.md
 * § `abort`) y deja el repositorio exactamente como antes de `start` — vuelve al
 * `reviewreturn`, borra `review/<src>` y sus ediciones bancadas.
 *
 * Mismo molde que `continueReview.ts`: la confirmación va **fuera** del
 * `MutationLock` (tomarlo mientras el modal espera dejaría el panel `busy` sin
 * que nada esté mutando todavía), y adentro sólo la invocación, con
 * `withProgress` no cancelable — a mitad de un abort no hay nada que cancelar.
 *
 * A diferencia de `continueReview.ts` esto SÍ revalida un `StateToken`
 * (staleGuard.ts, Fase 2) justo antes de invocar: es el primer verbo que lo
 * hace, porque acá el costo de un estado stale es distinto al de "resumir la
 * review equivocada" — es borrar una rama sobre la que el diálogo ya no dice
 * la verdad (p. ej. otra pestaña de terminal corrió `git review abort` o
 * `finish` mientras el modal esperaba). El testigo se captura al abrir el
 * diálogo y se revalida contra el estado vigente recién antes de invocar: si
 * no coincide, no se invoca nada y se avisa que el estado cambió, en vez de
 * arriesgar el abort.
 */
export async function abortReview(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const state = stateManager.state;
    if (state.situation !== "review" || !state.state) {
        return;
    }
    const source = state.state.source;
    const token = captureToken(state);

    const answer = await vscode.window.showWarningMessage(
        `Cancel the review of ${source}?`,
        {
            modal: true,
            detail: "This returns to the branch you started the review from; your uncommitted edits will be discarded.",
        },
        "Cancel Review"
    );
    if (answer !== "Cancel Review") {
        return;
    }

    await lock.run(async () => {
        // El testigo del estado se comparte entre la revalidacion de acá abajo
        // y el chequeo de despues del progreso: `withProgress` sólo devuelve el
        // resultado de la invocación, así que la marca de "no se invocó" viaja
        // por fuera de él.
        let stale = false;

        const result = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: `Cancelling the review of ${source}…`,
            },
            async () => {
                if (!tokenStillValid(token, stateManager.state)) {
                    stale = true;
                    return undefined;
                }
                const invocation = await invokeGitReview("abort", [], getInvokeOptions());
                // Refrescar pase lo que pase: aunque el verbo falle, es lo que
                // dice dónde quedó el repositorio — la salida humana no se
                // parsea nunca.
                await stateManager.refresh();
                return invocation;
            }
        );

        if (stale) {
            // Informativo, no error: nadie hizo nada mal, el mundo cambió
            // debajo del diálogo mientras esperaba la confirmación.
            void vscode.window.showInformationMessage(
                "The review state changed before the cancellation ran; nothing was cancelled."
            );
            return;
        }

        if (result && result.exitCode !== 0) {
            // El mensaje de la CLI se muestra tal cual, sin redactar acá
            // (FR-024) — es la misma garantía que continueReview.ts.
            const text = message(result.stderr);
            if (text.length > 0) {
                void vscode.window.showErrorMessage(text);
            }
        }
    });
}
