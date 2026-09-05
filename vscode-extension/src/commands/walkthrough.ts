import * as path from "node:path";
import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";
import {confirmMutation} from "../review/confirm";
import {
    WALKTHROUGH_EXISTS_DETAIL,
    WALKTHROUGH_EXISTS_TITLE,
    WALKTHROUGH_START_OVER_BUTTON,
    WALKTHROUGH_UPDATE_BUTTON,
} from "../review/userCopy";

/**
 * Cuál de las dos cosas hace `walkthrough init`, preguntado ANTES de invocar.
 *
 * La pregunta va delante, y sólo cuando hay algo que preservar: con el
 * registro `walkthrough` diciendo que el archivo está, las dos salidas son
 * reconciliar (lo normal) o empezar de cero. Sin registro o sin archivo no hay
 * nada que preguntar y se invoca directo, que es lo que hacía siempre.
 *
 * `superseded` es el tercer caso y no se pregunta tampoco: ahí el archivo es de
 * un PR que ya se mergeó y la CLI empieza de cero por su cuenta. Preguntar sería
 * ofrecer preservar prosa que no es de este PR.
 */
async function pickInitMode(
    stateManager: ReviewStateManager
): Promise<"update" | "force" | undefined> {
    const walkthrough = stateManager.state.walkthrough;
    if (walkthrough === undefined || walkthrough.state === "absent") {
        return "update";
    }
    if (walkthrough.state === "superseded") {
        return "update";
    }
    // EXCEPCION DECLARADA a la puerta unica (ver review/confirm.ts y AGENTS.md).
    // La frase de arriba la lee scripts/check-client-product-surface.mjs, literal
    // y sin acentos: es lo que exime a este modal del gate. No la reformules.
    //
    // Es una eleccion entre dos cursos --actualizar lo que hay o empezar de
    // cero--, no una confirmacion, y confirmMutation no puede expresarla porque
    // su "no" es un cancel. Sigue siendo `confirms: true` en el canonico porque
    // hay un modal entre el clic y la mutacion.
    const answer = await vscode.window.showWarningMessage(
        WALKTHROUGH_EXISTS_TITLE,
        {modal: true, detail: WALKTHROUGH_EXISTS_DETAIL},
        WALKTHROUGH_UPDATE_BUTTON,
        WALKTHROUGH_START_OVER_BUTTON
    );
    if (answer === WALKTHROUGH_UPDATE_BUTTON) {
        return "update";
    }
    if (answer === WALKTHROUGH_START_OVER_BUTTON) {
        return "force";
    }
    return undefined;
}

/**
 * `gitReview.walkthroughInit`. No parsea el sidecar; abre el archivo tras el
 * éxito. La elección entre actualizar y empezar de cero se hace **fuera** del
 * lock (mismo molde que abort/save).
 */
export async function walkthroughInit(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const mode = await pickInitMode(stateManager);
    if (mode === undefined) {
        return;
    }
    const args = mode === "force" ? ["init", "--force"] : ["init"];
    const title = mode === "force" ? "Starting the walkthrough over…" : "Initializing walkthrough…";

    await lock.run(async () => {
        const options = getInvokeOptions();
        const result = await vscode.window.withProgress(
            {location: vscode.ProgressLocation.Notification, title},
            async () => invokeGitReview("walkthrough", args, options)
        );
        await stateManager.refresh();
        if (result.exitCode !== 0) {
            const err = result.stderr.trim() || result.stdout.trim();
            void vscode.window.showErrorMessage(
                err.length > 0 ? err : "Could not create the walkthrough."
            );
            return;
        }
        await openWalkthrough(options.cwd);
    });
}

export async function walkthroughBuild(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const confirmed = await confirmMutation(
        "walkthroughBuild",
        "Check and renumber the walkthrough?",
        "This puts the files in the order you wrote and numbers them 1 to N. If something is missing, nothing changes and you will see what to fix.",
        "Build"
    );
    if (!confirmed) {
        return;
    }

    await lock.run(async () => {
        const result = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: "Building walkthrough…",
            },
            async () => {
                const invocation = await invokeGitReview("walkthrough", ["build"], getInvokeOptions());
                await stateManager.refresh();
                return invocation;
            }
        );
        if (result && result.exitCode !== 0) {
            void vscode.window.showErrorMessage(
                result.stderr.trim() || "Could not build the walkthrough."
            );
            return;
        }
        // Sin toast: el build tiene DOS acuses visibles y este era el tercero.
        // El refresco de arriba deja la fila del walkthrough con su badge al día
        // y su par annotated/total recontado, y la línea de abajo abre el
        // archivo en el editor.
        await openWalkthrough(getInvokeOptions().cwd);
    });
}

async function openWalkthrough(cwd: string): Promise<void> {
    if (!cwd) {
        return;
    }
    const file = path.join(cwd, ".review", "walkthrough.md");
    try {
        const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(file));
        await vscode.window.showTextDocument(doc, {preview: false});
    } catch {
        // init falló a medias o path distinto; el error de la CLI ya se mostró si aplica.
    }
}
