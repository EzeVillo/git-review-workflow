/**
 * El único control de la sección "Edits you extracted": descartar la rama de
 * ediciones que dejó un `finish`.
 *
 * Mismo reparto que los controles del bloque de borradores y del de guías: es
 * un control del CUERPO del panel, no una acción del producto — sin la fila que
 * lo dibuja no tiene sujeto —, así que no está en `contributes.commands` ni en
 * la paleta y el conteo de 27 sigue igual.
 */

import * as vscode from "vscode";

import {invokeGitReview, type InvokeOptions} from "../cli/invoke";
import type {MutationLock} from "../review/mutationLock";
import {
    argsForHousekeeping,
    sourceFromReviewName,
    confirmCopyFor,
    type HousekeepingAction,
} from "../review/housekeeping";
import type {ReviewStateManager} from "../review/state";
import type {FixesRecord} from "../cli/porcelain";

function rowAt(stateManager: ReviewStateManager, index: unknown): FixesRecord | undefined {
    if (typeof index !== "number" || !Number.isInteger(index) || index < 0) {
        return undefined;
    }
    return (stateManager.state.fixes ?? [])[index];
}

function flatten(text: string | undefined): string {
    return (text ?? "").split(/\r?\n/).map((line) => line.trim()).filter(Boolean).join(" ");
}

/**
 * *Discard*: borra la rama de ediciones de ESTA fila, con confirmación previa.
 *
 * La confirmación nombra el verbo real y dice cuánto cuesta, con el estado que
 * reportó la CLI — que es la única que puede preguntarle a git si esos commits
 * están en la base. Acá no se deriva nada.
 *
 * Siempre `--fixes-only`, aunque la sesión ya no exista: el argv no puede
 * depender de un dato que se relee en cada refresco. Un `clean <x>` que llegue
 * tarde —la review volvió a existir entre el refresco y el click— se llevaría
 * puesta una review viva desde un botón que promete borrar una rama de
 * ediciones.
 */
export async function discardFixes(
    index: unknown,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const row = rowAt(stateManager, index);
    if (row === undefined || row.current) {
        return;
    }
    const action: HousekeepingAction = {
        kind: "clean-fixes-only",
        source: sourceFromReviewName(row.name),
        fixesState: row.state,
        session: row.session,
    };
    const copy = confirmCopyFor(action);
    const answer = await vscode.window.showWarningMessage(
        copy.title,
        {modal: true, detail: copy.detail},
        copy.button
    );
    if (answer !== copy.button) {
        return;
    }

    await lock.run(async () => {
        // Re-resolver dentro del lock: el índice puede apuntar a otra fila si el
        // inventario cambió bajo el modal.
        const fresh = rowAt(stateManager, index);
        if (fresh === undefined || fresh.name !== row.name) {
            void vscode.window.showInformationMessage(
                "The branches changed before discard ran; nothing was deleted."
            );
            return;
        }
        const result = await invokeGitReview("clean", argsForHousekeeping(action), {
            ...getInvokeOptions(),
            network: false,
        });
        await stateManager.refresh();
        if (result.errorCode || result.exitCode !== 0) {
            const text = flatten(result.stderr);
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "git review clean --fixes-only failed."
            );
        }
    });
}
