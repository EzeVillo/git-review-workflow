import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";
import {captureToken, tokenStillValid} from "../review/staleGuard";
import {STALE} from "../review/userCopy";
import {confirmMutation} from "../review/confirm";

/** El stderr de la CLI, aplanado a una línea para el toast del editor. */
function message(stderr: string): string {
    return stderr.split("\n").map((line) => line.trim()).filter((line) => line.length > 0).join(" ");
}

/**
 * `gitReview.saveReview`: pausa la review activa (contracts/cli-invocation.md
 * § `save`) como `review-saved/<src>` y vuelve a la rama de origen. La review
 * queda en el inventario del estado vacío, retomable con `continue`.
 *
 * Mismo molde que `abortReview.ts`: la confirmación va **fuera** del
 * `MutationLock`, y adentro sólo la invocación, con `withProgress` no
 * cancelable. El `StateToken` se captura al abrir el diálogo y se revalida
 * justo antes de invocar (staleGuard.ts): si el estado cambió debajo del
 * modal, no se invoca nada.
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

    const confirmed = await confirmMutation(
        "saveReview",
        `Save the review of ${source} for later?`,
        "This pauses the review and returns to the branch you started from; your edits are kept and you can resume later.",
        "Save for Later"
    );
    if (!confirmed) {
        return;
    }

    await lock.run(async () => {
        // El testigo se comparte entre la revalidación de acá abajo y el chequeo
        // después del progreso: `withProgress` sólo devuelve el resultado de la
        // invocación, así que la marca de "no se invocó" viaja por fuera de él.
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
                // Refrescar pase lo que pase (ver continueReview.ts): dice dónde
                // quedó el repositorio; la salida humana no se parsea nunca.
                await stateManager.refresh();
                return invocation;
            }
        );

        if (stale) {
            void vscode.window.showInformationMessage(
                STALE
            );
            return;
        }

        if (result && result.exitCode !== 0) {
            // El mensaje de la CLI se muestra tal cual, sin redactar acá — es la
            // misma garantía que abortReview.ts. Si el exit no es 0 y no hay
            // stderr (CLI matada / rota), un toast genérico evita el fallo
            // silencioso.
            const text = message(result.stderr);
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "Could not pause the review."
            );
        }
    });
}
