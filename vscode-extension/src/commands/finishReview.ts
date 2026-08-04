import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {finishOutcome} from "../review/finishOutcome";
import {ReviewStateManager} from "../review/state";
import {captureToken, tokenStillValid} from "../review/staleGuard";

/** El stderr de la CLI, aplanado a una línea para el toast del editor (mismo criterio que el resto de los comandos). */
function message(stderr: string): string {
    return stderr.split("\n").map((line) => line.trim()).filter((line) => line.length > 0).join(" ");
}

interface LocationItem extends vscode.QuickPickItem {
    ontoSource: boolean;
}

const LOCATION_ITEMS: LocationItem[] = [
    {
        label: "A separate branch",
        description: "review-fixes/<branch>, staged on top of the PR tip",
        ontoSource: false,
    },
    {
        label: "Onto the PR branch itself",
        description: "stage the edits directly on the PR branch",
        ontoSource: true,
    },
];

/**
 * `gitReview.finishReview`: cierra la review activa extrayendo las ediciones a
 * donde el revisor elija (contracts/cli-invocation.md § `finish`, FR-018).
 *
 * El `QuickPick` de ubicación es la única decisión — sin casilla, dos ítems
 * con descripción — y no pide una confirmación modal aparte: a diferencia de
 * `abortReview.ts`/`saveReview.ts`, `finish` no descarta nada, así que no cae
 * bajo el mismo criterio que FR-023. El `StateToken` (staleGuard.ts) se
 * captura antes de abrir el `QuickPick` y se revalida justo antes de invocar
 * (FR-038): el diálogo puede quedar abierto un rato, y el repositorio puede
 * cambiar debajo mientras el revisor elige.
 *
 * **"No había ediciones que extraer" se deriva del estado posterior, nunca
 * del texto de la CLI** (T050, contracts/cli-invocation.md § "no parsear la
 * salida humana de ningún verbo" — es la regla que más fácil se pierde acá: la
 * CLI dice con todas las letras "no review changes to apply", y leer esa
 * línea sería lo más corto). `finishOutcome` mira si el refresco posterior
 * reporta un cierre `pending` para esta review; su ausencia es la señal — la
 * CLI misma deshace su propio punto de undo cuando no hubo ediciones que
 * extraer (`bin/git-review-verbs/finish:446-451`) — y se informa como
 * resultado normal, no como error (FR-019). El comando en sí no puede ofrecer
 * deshacer/continuar un cierre trabado todavía: ese es el contrato que
 * consume US4, en una fase posterior; acá sólo se reporta lo que quedó.
 */
export async function finishReview(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const state = stateManager.state;
    if (state.situation !== "review" || !state.state) {
        return;
    }
    const branch = state.state.branch;
    const source = state.state.source;
    const token = captureToken(state);

    const picked = await vscode.window.showQuickPick(LOCATION_ITEMS, {
        title: `Finish the review of ${source} — where do your edits go?`,
        placeHolder: "A separate branch, or onto the PR branch itself",
    });
    if (!picked) {
        return;
    }

    if (!tokenStillValid(token, stateManager.state)) {
        void vscode.window.showInformationMessage(
            "The review state changed while choosing where to finish; nothing was finished."
        );
        return;
    }

    await lock.run(async () => {
        const args = picked.ontoSource ? ["--onto-source"] : [];
        const {invocation, refreshed} = await vscode.window.withProgress(
            {location: vscode.ProgressLocation.Notification, title: `Finishing the review of ${source}…`},
            async () => {
                const result = await invokeGitReview("finish", args, getInvokeOptions());
                // Refrescar pase lo que pase: aunque finish falle, es lo que
                // dice dónde quedó el repositorio, y es lo que finishOutcome
                // necesita para decidir el mensaje de éxito.
                const next = await stateManager.refresh();
                return {invocation: result, refreshed: next};
            }
        );

        if (invocation.exitCode !== 0) {
            const text = message(invocation.stderr);
            if (text.length > 0) {
                void vscode.window.showErrorMessage(text);
            }
            return;
        }

        if (finishOutcome(refreshed, branch) === "pending") {
            const destination = picked.ontoSource ? source : `review-fixes/${source}`;
            void vscode.window.showInformationMessage(`${destination} is ready with your edits staged.`);
        } else {
            void vscode.window.showInformationMessage(`No review changes to apply for ${source}.`);
        }
    });
}
