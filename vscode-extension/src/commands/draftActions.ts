/**
 * Los cuatro controles de una fila del bloque de borradores (012,
 * contracts/client-draft-panel.md § 1). Son controles del **cuerpo** del panel,
 * no acciones del producto: no están en `contributes.commands` ni en la paleta,
 * y sin la fila que los dibuja no tienen sujeto.
 *
 * Todo lo que necesitan sale del registro `draft` de `config --porcelain`: la
 * ruta que abren, el progreso que muestran y los flags de origen y rango con
 * los que se invoca. Nada se deriva acá — armar la ruta o adivinar los flags es
 * exactamente lo que esta feature retira.
 */

import * as vscode from "vscode";
import {DraftRecord} from "../cli/configPorcelain";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {parseConfigPorcelain} from "../cli/configPorcelain";
import {offersIncludeKeys, sameDraftFile} from "../review/draftFlow";
import {MutationLock} from "../review/mutationLock";
import {
    draftArgs,
    draftConfigArgs,
    forgetDraftArgs,
    intentToArgs,
    ReviewIntent,
    ReviewLayout,
    ReviewRange,
    ReviewSource,
} from "../review/reviewIntent";
import {captureToken, tokenStillValid} from "../review/staleGuard";
import {ReviewStateManager} from "../review/state";
import {STALE, draftAgentPrompt, startLayoutTitle} from "../review/userCopy";
import {draftAt} from "../views/panelModel";

/** El stderr de la CLI, aplanado a una línea (mismo criterio que el resto). */
function flatten(stderr: string): string {
    return stderr.split("\n").map((line) => line.trim()).filter((line) => line.length > 0).join(" ");
}

/**
 * Los flags con los que se generó ESTE borrador, tal como los reporta la CLI.
 *
 * `undefined` cuando alguno vale `unknown` (el bloque de instrucciones se borró
 * a mano, cosa permitida): entonces no hay flags que replicar y el control no
 * se ofrece. El panel ya no lo dibuja; esta guarda es la del host, para que un
 * mensaje viejo del webview tampoco pueda dispararlo.
 */
function flagsOf(draft: DraftRecord): { source: ReviewSource; range: ReviewRange } | undefined {
    if (draft.source === "unknown" || draft.range === "unknown") {
        return undefined;
    }
    return {source: draft.source, range: draft.range};
}

/**
 * La fila `index` del bloque, resuelta contra el estado del HOST. El índice es
 * lo único que un mensaje del webview lleva, y nunca se le cree: lo que termina
 * en la CLI sale de acá.
 */
function rowAt(stateManager: ReviewStateManager, index: unknown): DraftRecord | undefined {
    return draftAt(stateManager.state.drafts ?? [], index);
}

/**
 * *Open*: muestra el borrador en el editor, en la ruta que reportó la CLI.
 *
 * Abrirlo es mostrarlo, no leerlo: la extensión no interpreta un byte de su
 * contenido, igual que ya hace con `.review/walkthrough.md` tras un
 * `walkthrough init`.
 */
export async function openDraft(index: unknown, stateManager: ReviewStateManager): Promise<void> {
    const draft = rowAt(stateManager, index);
    if (draft === undefined) {
        return;
    }
    try {
        const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(draft.path));
        await vscode.window.showTextDocument(doc, {preview: false});
    } catch {
        // La ruta la dio la CLI y el archivo existe; si el editor igual no
        // puede abrirlo, decirlo con la ruta adentro es lo único útil.
        void vscode.window.showErrorMessage(`Could not open ${draft.path}.`);
    }
}

/**
 * *Copy for agent*: deja en el portapapeles un puntero al archivo de ESTA fila.
 *
 * No abre ninguna conexión, no invoca ningún modelo y no se integra con ningún
 * asistente: copiar es copiar. La consigna vive dentro del archivo.
 */
export async function copyDraftPrompt(
    index: unknown,
    stateManager: ReviewStateManager
): Promise<void> {
    const draft = rowAt(stateManager, index);
    if (draft === undefined) {
        return;
    }
    await vscode.env.clipboard.writeText(draftAgentPrompt(draft.path));
    void vscode.window.showInformationMessage(`Copied an instruction pointing at ${draft.src}'s reading order.`);
}

/**
 * Guarda el documento del borrador si está abierto y sucio, y sólo ése.
 *
 * `walkthrough draft --build` lee el archivo del disco, y VS Code **no
 * autoguarda por defecto**: sin esto el camino normal —abrir el borrador,
 * escribir el orden, apretar *Validate and start*— validaba el esqueleto vacío
 * que seguía en disco y respondía "unfilled entries remain" con el texto a la
 * vista. Nunca `saveAll`: guardar de paso todo lo demás que el revisor tuviera
 * abierto no es algo que haya pedido nadie.
 */
async function saveDraftDocument(file: string): Promise<void> {
    const doc = vscode.workspace.textDocuments.find((candidate) =>
        sameDraftFile(candidate.uri.fsPath, file)
    );
    if (doc === undefined || !doc.isDirty) {
        return;
    }
    try {
        await doc.save();
    } catch {
        // Deliberadamente sin ruido: lo dice el --build de la línea siguiente,
        // con la ruta adentro.
    }
}

/** Recorrido completo vs sólo esenciales, cuando el borrador marcó entradas. */
async function pickDraftKeys(branch: string): Promise<boolean | undefined> {
    const picked = await vscode.window.showQuickPick(
        [
            {
                label: "Walkthrough",
                description: "the whole reading order you wrote",
                keysOnly: false,
            },
            {
                label: "Walkthrough — keys only",
                description: "only the entries you marked key",
                keysOnly: true,
            },
        ],
        {
            // El único paso entre el botón y el start, así que nombra la rama:
            // misma regla que el último paso del asistente.
            title: startLayoutTitle(branch),
            placeHolder: "Your draft marks key entries: read all of them, or only those",
        }
    );
    return picked?.keysOnly;
}

/**
 * *Validate and start*: los cuatro pasos de contracts/client-draft-panel.md § 1.
 *
 *   1. guardar el documento del borrador si está abierto y sucio
 *   2. `walkthrough draft --build <flags> -- <src>`
 *        rojo  → mostrar el stderr aplanado y no tocar nada más
 *        verde → 3
 *   3. `config --porcelain <flags> -- <src>` para saber si hay esenciales
 *   4. confirmación y `start <flags>`, como cualquier otra forma de lectura
 *
 * Los `<flags>` son los de la fila y van iguales en los tres pasos.
 */
export async function startFromDraft(
    index: unknown,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const draft = rowAt(stateManager, index);
    if (draft === undefined) {
        return;
    }
    const flags = flagsOf(draft);
    if (flags === undefined) {
        return;
    }
    const {source, range} = flags;
    const options = getInvokeOptions();

    await saveDraftDocument(draft.path);

    const built = await lock.run(async () =>
        vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: `Validating your draft for ${draft.src}…`,
            },
            async () =>
                invokeGitReview("walkthrough", draftArgs(draft.src, source, range, true), {
                    ...options,
                    network: false,
                })
        )
    );
    if (built === undefined) {
        return;
    }
    if (built.errorCode || built.exitCode !== 0) {
        // El motivo del rechazo lo escribió la CLI: redactarlo de nuevo sería
        // inventar un segundo vocabulario de validación. El panel y el borrador
        // quedan exactamente como estaban.
        const text = flatten(built.stderr);
        void vscode.window.showErrorMessage(
            text.length > 0 ? text : "Could not check your reading order."
        );
        return;
    }

    // El borrador ya es legible: lo que se relee es si marcó entradas
    // esenciales, y eso sólo lo sabe la CLI.
    let layout: ReviewLayout = "walk";
    const report = await invokeGitReview(
        "config",
        draftConfigArgs(draft.src, source, range),
        {...options, network: false}
    );
    if (!report.errorCode && report.exitCode === 0) {
        const offers = parseConfigPorcelain(report.stdout).offers;
        if (offersIncludeKeys(offers)) {
            const keysOnly = await pickDraftKeys(draft.src);
            if (keysOnly === undefined) {
                return;
            }
            layout = keysOnly ? "keys" : "walk";
        }
    }

    const intent: ReviewIntent = {branch: draft.src, layout, range, source};
    const args = intentToArgs(intent, draft.src);
    // Sin confirmación: es la misma que se borró del asistente, y acá sobra
    // todavía más — el botón que trajo hasta acá dice "Validate and start", y
    // el paso de keys (cuando lo hay) ya nombra la rama.
    const token = captureToken(stateManager.state);
    if (!tokenStillValid(token, stateManager.state)) {
        void vscode.window.showInformationMessage(
            STALE
        );
        return;
    }

    await lock.run(async () => {
        const result = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: `Starting the review of ${draft.src}…`,
            },
            async () => {
                const invocation = await invokeGitReview("start", args, options);
                await stateManager.refresh();
                return invocation;
            }
        );
        if (result.errorCode || result.exitCode !== 0) {
            const text = flatten(result.stderr);
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "Could not start the review."
            );
        }
    });
}

/**
 * *Discard*: borra el borrador de ESTA fila, con confirmación previa.
 *
 * Es prosa escrita a mano, así que se pregunta nombrando el verbo real que se
 * va a correr, como ya hace `discardInventory`. Nunca `--all`: una acción sobre
 * una fila no puede tocar las demás.
 */
export async function discardDraft(
    index: unknown,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const draft = rowAt(stateManager, index);
    if (draft === undefined) {
        return;
    }
    const answer = await vscode.window.showWarningMessage(
        `Discard the reading order you wrote for ${draft.src}?`,
        {
            modal: true,
            detail: `This deletes ${draft.path}. It cannot be undone.`,
        },
        "Discard"
    );
    if (answer !== "Discard") {
        return;
    }

    await lock.run(async () => {
        // Re-resolver dentro del lock: el índice puede apuntar a otra fila si el
        // reporte cambió bajo el modal.
        const fresh = rowAt(stateManager, index);
        if (fresh === undefined || fresh.src !== draft.src) {
            void vscode.window.showInformationMessage(
                STALE
            );
            return;
        }
        const result = await invokeGitReview("forget", forgetDraftArgs(draft.src), {
            ...getInvokeOptions(),
            network: false,
        });
        await stateManager.refresh();
        if (result.errorCode || result.exitCode !== 0) {
            const text = flatten(result.stderr);
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "Could not delete the reading order."
            );
        }
    });
}
