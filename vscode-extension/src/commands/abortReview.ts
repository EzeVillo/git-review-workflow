import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {isReviewReadable} from "../review/situation";
import {ReviewStateManager} from "../review/state";
import {captureToken, tokenStillValid} from "../review/staleGuard";
import {STALE} from "../review/userCopy";
import {confirmMutation} from "../review/confirm";

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
 * `MutationLock`, y adentro sólo la invocación, con `withProgress` no
 * cancelable — a mitad de un abort no hay nada que cancelar.
 *
 * A diferencia de `continueReview.ts` esto SÍ revalida un `StateToken`
 * (staleGuard.ts) justo antes de invocar: es el primer verbo que lo
 * hace, porque acá el costo de un estado stale es distinto al de "resumir la
 * review equivocada" — es borrar una rama sobre la que el diálogo ya no dice
 * la verdad (p. ej. otra pestaña de terminal corrió `git review abort` o
 * `finish` mientras el modal esperaba). El testigo se captura al abrir el
 * diálogo y se revalida contra el estado vigente recién antes de invocar: si
 * no coincide, no se invoca nada y se avisa que el estado cambió, en vez de
 * arriesgar el abort.
 *
 * Acepta `finish-conflict` además de `review` (`isReviewReadable`): tirar la
 * review entera es uno de los tres caminos que contracts/finish-state.md
 * documenta para un cierre trabado, y `git review abort`
 * (`bin/git-review-verbs/abort`) no tiene ningún guard sobre
 * `reviewundohead` que lo bloquee — hace `switch --discard-changes` y borra
 * `review/<src>` igual que en cualquier otro estado.
 */
export async function abortReview(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const state = stateManager.state;
    if (!isReviewReadable(state.situation) || !state.state) {
        return;
    }
    const source = state.state.source;
    const token = captureToken(state);

    const confirmed = await confirmMutation(
        "abortReview",
        `Cancel the review of ${source}?`,
        "This returns to the branch you started the review from; your uncommitted edits will be discarded.",
        "Cancel Review"
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
                title: `Cancelling the review of ${source}…`,
            },
            async () => {
                if (!tokenStillValid(token, stateManager.state)) {
                    stale = true;
                    return undefined;
                }
                const invocation = await invokeGitReview("abort", [], getInvokeOptions());
                // Refrescar pase lo que pase (ver continueReview.ts): dice dónde
                // quedó el repositorio; la salida humana no se parsea nunca.
                await stateManager.refresh();
                return invocation;
            }
        );

        if (stale) {
            // Informativo, no error: nadie hizo nada mal, el mundo cambió
            // debajo del diálogo mientras esperaba la confirmación.
            void vscode.window.showInformationMessage(
                STALE
            );
            return;
        }

        if (result && result.exitCode !== 0) {
            // El mensaje de la CLI se muestra tal cual, sin redactar acá — es la
            // misma garantía que continueReview.ts. Si el exit no es 0 y no hay
            // stderr (CLI matada / rota), un toast genérico evita el fallo
            // silencioso.
            const text = message(result.stderr);
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "Could not cancel the review."
            );
        }
    });
}
