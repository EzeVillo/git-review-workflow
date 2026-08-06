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
 * `gitReview.saveReview`: pausa la review activa (contracts/cli-invocation.md
 * § `save`) como `review-saved/<src>` y vuelve a la rama de origen. La review
 * queda en el inventario del estado vacío, retomable con `continue` (ya
 * existente desde `002`).
 *
 * Mismo molde que `abortReview.ts`: la confirmación va **fuera** del
 * `MutationLock` (tomarlo mientras el modal espera dejaría el panel `busy` sin
 * que nada esté mutando todavía), y adentro sólo la invocación, con
 * `withProgress` no cancelable. El `StateToken` se captura al abrir el diálogo
 * y se revalida justo antes de invocar (staleGuard.ts): si el estado cambió
 * debajo del modal, no se invoca nada.
 *
 * El texto de la confirmación es más suave que el de `abort`: no se descarta
 * nada, sólo se pausa — las ediciones viajan con la review guardada y se
 * recuperan al retomar.
 *
 * Sólo actúa sobre `situation === "review"` (no `finish-conflict`): pausar un
 * cierre trabado no es un camino documentado; para salir de ahí están
 * `undoFinish` / `abortReview` / `resumeFinish`.
 */
export async function saveReview(
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
        `Save the review of ${source} for later?`,
        {
            modal: true,
            detail: "This pauses the review and returns to the branch you started from; your edits are kept and you can resume later.",
        },
        "Save for Later"
    );
    if (answer !== "Save for Later") {
        return;
    }

    await lock.run(async () => {
        // El testigo del estado se comparte entre la revalidacion de aca abajo
        // y el chequeo de despues del progreso: `withProgress` solo devuelve el
        // resultado de la invocacion, asi que la marca de "no se invoco" viaja
        // por fuera de el.
        let stale = false;

        const result = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: `Saving the review of ${source} for later…`,
            },
            async () => {
                if (!tokenStillValid(token, stateManager.state)) {
                    stale = true;
                    return undefined;
                }
                const invocation = await invokeGitReview("save", [], getInvokeOptions());
                // Refrescar pase lo que pase: aunque el verbo falle, es lo que
                // dice donde quedo el repositorio — la salida humana no se
                // parsea nunca.
                await stateManager.refresh();
                return invocation;
            }
        );

        if (stale) {
            // Informativo, no error: nadie hizo nada mal, el mundo cambio
            // debajo del dialogo mientras esperaba la confirmacion.
            void vscode.window.showInformationMessage(
                "The review state changed before the save ran; nothing was saved."
            );
            return;
        }

        if (result && result.exitCode !== 0) {
            // El mensaje de la CLI se muestra tal cual, sin redactar aca
            // (FR-024) — es la misma garantia que abortReview.ts.
            const text = message(result.stderr);
            if (text.length > 0) {
                void vscode.window.showErrorMessage(text);
            }
        }
    });
}
