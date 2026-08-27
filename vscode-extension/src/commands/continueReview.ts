import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";
import {captureToken, tokenStillValid} from "../review/staleGuard";
import {resumableSourceAt} from "../views/panelModel";
import {STALE} from "../review/userCopy";

/** El stderr de la CLI, aplanado a una línea para el toast del editor. */
function message(stderr: string): string {
    return stderr.split("\n").map((line) => line.trim()).filter((line) => line.length > 0).join(" ");
}

/**
 * `gitReview.continueReview`: resume la review guardada de la fila `index` del
 * inventario del estado vacío (contracts/cli-invocation.md § `continue`).
 *
 * A diferencia de `next`/`prev` **pide confirmación**: el verbo cambia `HEAD`,
 * restaura las ediciones en el working tree y borra `review-saved/<src>`, que no
 * es el costo de un clic de navegación. La confirmación va **fuera** del
 * `MutationLock` — tomarlo mientras un modal espera dejaría el panel en `busy`
 * todo ese tiempo, y la mutación es la invocación, no la pregunta.
 *
 * El `index` viene del webview y no se le cree: `resumableSourceAt` lo resuelve
 * contra el inventario del host, así que el argumento que llega a la CLI sale
 * del estado del host. Un índice que no resuelve no hace nada.
 *
 * El `StateToken` se captura al abrir el diálogo y se revalida justo antes de
 * invocar (FR-012 / staleGuard), igual que finish/save/abort: el inventario
 * puede cambiar debajo del modal.
 *
 * La espera se muestra con el progreso del editor y no con el esqueleto del
 * panel: el esqueleto es la silueta de una entrada y acá no hay ninguna —el
 * panel está en `no-review`—, y lo que el panel no puede comunicar es
 * justamente lo que hace lento a este verbo, que git está tocando el working
 * tree y con eso se mueve el resto del editor. El `busy` del panel sigue siendo
 * lo que apaga los controles.
 */
export async function continueReview(
    index: unknown,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const source = resumableSourceAt(stateManager.state.branches, index);
    if (source === undefined) {
        return;
    }
    const token = captureToken(stateManager.state);

    const answer = await vscode.window.showWarningMessage(
        `Continue the saved review of ${source}?`,
        {
            modal: true,
            detail: `This switches to review/${source} and restores your edits in the working tree.`,
        },
        "Continue"
    );
    if (answer !== "Continue") {
        return;
    }

    await lock.run(async () => {
        // El refresh va adentro del progreso: es parte de la misma espera, y
        // soltarlo antes dejaría el panel con el inventario viejo justo cuando
        // el indicador dice que ya terminó. No es cancelable — a mitad de un
        // checkout no hay nada que cancelar.
        let stale = false;
        // Re-resolver el source dentro del lock: el índice del webview puede
        // apuntar a otra fila si el inventario cambió bajo el modal.
        const freshSource = resumableSourceAt(stateManager.state.branches, index);
        if (freshSource === undefined || freshSource !== source || !tokenStillValid(token, stateManager.state)) {
            stale = true;
        }

        const result = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: `Continuing the review of ${source}…`,
            },
            async () => {
                if (stale) {
                    return undefined;
                }
                const invocation = await invokeGitReview("continue", [source], getInvokeOptions());
                // Refrescar pase lo que pase: aunque el verbo falle, es lo que
                // dice dónde quedó el repositorio — la salida humana no se
                // parsea nunca.
                await stateManager.refresh();
                return invocation;
            }
        );

        if (stale || result === undefined) {
            void vscode.window.showInformationMessage(
                STALE
            );
            return;
        }

        if (result.exitCode !== 0) {
            // El working tree sucio es el modo de fallo que no se puede
            // anticipar desde el inventario, y su mensaje ya dice qué hacer
            // ("commit or stash them first"): se muestra el de la CLI, no uno
            // redactado acá (FR-024). Si no hay stderr (CLI matada / rota),
            // un toast genérico evita el fallo silencioso.
            const text = message(result.stderr);
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "Could not resume the review."
            );
        }
    });
}
