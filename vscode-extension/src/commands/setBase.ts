import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {CandidateBranch} from "../cli/configPorcelain";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";

/** El nombre a mostrar en el `QuickPick`: la rama, con su origen si conviene desambiguar. */
function label(candidate: CandidateBranch): string {
    return candidate.current ? `${candidate.name}  (current)` : candidate.name;
}

/**
 * `gitReview.setBase`: fija `reviewworkflow.base` desde una lista de
 * `candidate` (contracts/cli-invocation.md § `config <key> <value>`).
 * Invocable standalone desde el estado vacío (sin `candidates`: usa el
 * último reporte de `config --porcelain` que trae `stateManager.state`), y
 * también como el paso que T024 antepone cuando el asistente de inicio
 * arranca sin base configurada — ahí el asistente le pasa las candidatas
 * que **ya leyó fresco** un momento antes, para no depender del reporte
 * cacheado del panel (que puede estar ausente por un fallo transitorio del
 * refresco anterior aunque el asistente tenga la lista en la mano).
 *
 * El valor que llega a la CLI es siempre el `name` de una `candidate` tal
 * cual, precedido por `--` (mismo motivo que en `start`, U1): nunca algo
 * tipeado a mano, y nunca una rama construida por la extensión.
 */
export async function setBase(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions,
    candidates?: CandidateBranch[]
): Promise<void> {
    const list = candidates ?? stateManager.state.candidates ?? [];
    if (list.length === 0) {
        void vscode.window.showErrorMessage("No branches to pick a base from were found.");
        return;
    }

    // La actual primero (research.md Decisión 9, FR-011), igual que el primer
    // paso del asistente de inicio: es casi siempre la que se quiere comparar
    // contra, y la búsqueda incremental del QuickPick cubre el resto.
    const items = [...list]
        .sort((a, b) => (a.current === b.current ? 0 : a.current ? -1 : 1))
        .map((candidate) => ({label: label(candidate), candidate}));

    const picked = await vscode.window.showQuickPick(items, {
        title: "Set the base branch",
        placeHolder: "Branch a full review compares against",
    });
    if (!picked) {
        return;
    }

    await lock.run(async () => {
        const options = getInvokeOptions();
        const result = await invokeGitReview("config", ["base", "--", picked.candidate.name], options);
        await stateManager.refresh();
        if (result.exitCode !== 0) {
            const text = result.stderr.trim();
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "git review config failed."
            );
        }
    });
}
