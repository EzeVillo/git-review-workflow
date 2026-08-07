import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
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
 * **El toast de éxito no se deriva del texto de la CLI** (T050,
 * contracts/cli-invocation.md § "no parsear la salida humana"). Un finish con
 * exit 0 siempre aterrizó en el destino (extract vacío incluido: undo vivo en
 * `review-fixes/<src>` o la rama del PR). El panel se refresca después y pasa a
 * `finish-pending` cuando el inventario lo reporta; un list fallido no debe
 * decir "sin cambios" porque el finish ya corrió.
 *
 * Deshacer/continuar un cierre (`undoFinish` / `resumeFinish` abajo) es US4:
 * este comando sólo arranca un cierre nuevo.
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
    // Defensa: la UI ya oculta Finish con gitReview.readonly; la CLI también
    // rechazaría. No abrir el QuickPick de destino si no hay a dónde escribir.
    if (state.readonly) {
        void vscode.window.showInformationMessage(
            "This is a read-only compare review; there is nothing to finish. Use Cancel when done."
        );
        return;
    }
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
        const invocation = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: `Finishing the review of ${source}…`
            },
            async () => {
                const result = await invokeGitReview("finish", args, getInvokeOptions());
                // Refrescar pase lo que pase: el panel necesita el estado real.
                await stateManager.refresh();
                return result;
            }
        );

        if (invocation.exitCode !== 0) {
            // stderr de la CLI tal cual (FR-024); si viene vacío (CLI matada /
            // rota), un toast genérico evita el fallo silencioso.
            const text = message(invocation.stderr);
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "git review finish failed."
            );
            return;
        }

        // Exit 0 always lands on the destination (empty extract included). Never
        // claim "no changes" from a missing inventory row — list --porcelain can
        // fail after a successful finish and would collapse to empty branches.
        const destination = picked.ontoSource ? source : `review-fixes/${source}`;
        void vscode.window.showInformationMessage(`${destination} is ready.`);
    });
}

/**
 * `gitReview.undoFinish`: deshace un cierre `pending` o `conflict`
 * (contracts/cli-invocation.md § `finish --abort` / `--force`, FR-021/FR-029).
 *
 * Mismo molde que `abortReview.ts`: la confirmación va **fuera** del
 * `MutationLock`, el `StateToken` se captura al abrir el diálogo y se revalida
 * justo antes de invocar. Si `finish --abort` falla porque hay trabajo nuevo
 * en la rama del cierre, el `stderr` de la CLI se muestra en una **segunda**
 * confirmación (visualmente distinta — el texto nombra el trabajo que se
 * perdería) y sólo entonces se invoca `finish --abort --force`. El testigo se
 * revalida **otra vez** antes del `--force`: es la invocación más destructiva
 * del ciclo, y entre el rechazo y la segunda confirmación pasa tiempo.
 *
 * `--force` **nunca** es opción de primera clase: no hay casilla, no hay
 * reintento automático, no aparece en el primer diálogo.
 */
export async function undoFinish(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const state = stateManager.state;
    if (state.situation !== "finish-pending" && state.situation !== "finish-conflict") {
        return;
    }
    const token = captureToken(state);
    const detail =
        state.situation === "finish-conflict"
            ? "This discards any in-progress resolution and returns you to editing the review."
            : "This returns you to the review branch with your edits restored.";

    const answer = await vscode.window.showWarningMessage(
        "Undo this finish?",
        {modal: true, detail},
        "Undo Finish"
    );
    if (answer !== "Undo Finish") {
        return;
    }

    const abortResult = await lock.run(async () => {
        let stale = false;
        const invocation = await vscode.window.withProgress(
            {location: vscode.ProgressLocation.Notification, title: "Undoing the finish…"},
            async () => {
                if (!tokenStillValid(token, stateManager.state)) {
                    stale = true;
                    return undefined;
                }
                const result = await invokeGitReview("finish", ["--abort"], getInvokeOptions());
                await stateManager.refresh();
                return result;
            }
        );
        if (stale) {
            void vscode.window.showInformationMessage(
                "The review state changed before the undo ran; nothing was undone."
            );
            return {stale: true as const};
        }
        return {stale: false as const, invocation};
    });

    if (!abortResult || abortResult.stale) {
        return;
    }
    const {invocation} = abortResult;
    if (!invocation || invocation.exitCode === 0) {
        return;
    }

    // Fallo esperado: hay trabajo nuevo en la rama del cierre. El stderr es lo
    // que habilita la segunda confirmación (contracts/cli-invocation.md §
    // finish --abort --force) — se muestra tal cual, sin redactar (FR-024).
    // Sin stderr no hay diagnóstico ni mención de --force: toast genérico y
    // se detiene (nunca ofrecer force a ciegas).
    const text = message(invocation.stderr);
    if (text.length === 0) {
        void vscode.window.showErrorMessage("git review finish --abort failed.");
        return;
    }

    // Sólo cuando la CLI nombra --force como escape: otros fallos (sin punto
    // de undo, etc.) se muestran y se detienen acá, sin ofrecer force.
    if (!text.includes("--force")) {
        void vscode.window.showErrorMessage(text);
        return;
    }

    const forceAnswer = await vscode.window.showWarningMessage(
        text,
        {
            modal: true,
            detail: "Aborting with --force permanently discards the work made since the finish. This cannot be undone.",
        },
        "Discard Work and Undo"
    );
    if (forceAnswer !== "Discard Work and Undo") {
        return;
    }

    await lock.run(async () => {
        let stale = false;
        const forceInvocation = await vscode.window.withProgress(
            {location: vscode.ProgressLocation.Notification, title: "Force-undoing the finish…"},
            async () => {
                // Mismo token capturado al abrir el *primer* diálogo — no se
                // recaptura entre el rechazo y la segunda confirmación.
                if (!tokenStillValid(token, stateManager.state)) {
                    stale = true;
                    return undefined;
                }
                const result = await invokeGitReview(
                    "finish",
                    ["--abort", "--force"],
                    getInvokeOptions()
                );
                await stateManager.refresh();
                return result;
            }
        );
        if (stale) {
            void vscode.window.showInformationMessage(
                "The review state changed before the force-undo ran; nothing was undone."
            );
            return;
        }
        if (forceInvocation && forceInvocation.exitCode !== 0) {
            const forceText = message(forceInvocation.stderr);
            void vscode.window.showErrorMessage(
                forceText.length > 0 ? forceText : "git review finish --abort --force failed."
            );
        }
    });
}

/**
 * `gitReview.resumeFinish`: continúa un cierre trabado por conflicto
 * (contracts/cli-invocation.md § `finish --resume`, FR-020).
 *
 * Sin confirmación previa: no descarta nada — es el reverso de deshacer. El
 * flag `--onto-source` sale **únicamente** del campo `onto` del registro
 * `finish` que reporta `status --porcelain` (`state.finish.onto`), nunca de
 * una variable en memoria del comando de finish: el editor puede reiniciarse
 * entre el rechazo y el resume, y ahí una memoria en proceso mandaría las
 * ediciones a un lugar distinto del que el revisor eligió, en silencio.
 */
export async function resumeFinish(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const state = stateManager.state;
    if (state.situation !== "finish-conflict" || !state.finish) {
        return;
    }
    // onto del contrato, no de memoria: es el motivo de que el registro lo
    // exponga (contracts/finish-state.md).
    const args = state.finish.onto ? ["--resume", "--onto-source"] : ["--resume"];

    await lock.run(async () => {
        const result = await vscode.window.withProgress(
            {location: vscode.ProgressLocation.Notification, title: "Resuming the finish…"},
            async () => {
                const invocation = await invokeGitReview("finish", args, getInvokeOptions());
                await stateManager.refresh();
                return invocation;
            }
        );
        if (result.exitCode !== 0) {
            const text = message(result.stderr);
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "git review finish --resume failed."
            );
        }
    });
}
