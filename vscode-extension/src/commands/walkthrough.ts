import * as path from "node:path";
import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";
import {
    WALKTHROUGH_EXISTS_DETAIL,
    WALKTHROUGH_EXISTS_TITLE,
    WALKTHROUGH_START_OVER_BUTTON,
    WALKTHROUGH_UPDATE_BUTTON,
} from "../review/userCopy";

/**
 * `gitReview.walkthroughInit` / `walkthroughBuild` (006 US4).
 * No parsea el sidecar; init abre el archivo tras éxito.
 * Confirmación de --force **fuera** del lock (mismo molde que abort/save).
 */
/**
 * Cuál de las dos cosas hace `walkthrough init`, preguntado ANTES de invocar.
 *
 * Antes esto colgaba de que la CLI **fallara**: se corría `init`, y si moría
 * porque el archivo ya estaba, recién ahí se ofrecía sobrescribir. Desde que
 * `init` actualiza en vez de negarse, ese camino dejó de existir y con él la
 * única forma de llegar a `--force` desde el panel — el código seguía ahí sin
 * que nada lo ejecutara.
 *
 * Así que la pregunta va delante, y sólo cuando hay algo que preservar: con el
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
 * `gitReview.walkthroughInit` (006 US4). No parsea el sidecar; abre el archivo
 * tras el éxito. La elección entre actualizar y empezar de cero se hace **fuera**
 * del lock (mismo molde que abort/save).
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
                err.length > 0 ? err : "git review walkthrough init failed."
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
    const answer = await vscode.window.showWarningMessage(
        "Rebuild the walkthrough from your filled-in draft?",
        {
            modal: true,
            detail: "Validates .review/walkthrough.md, reorders entries and renumbers 1..N (git review walkthrough build).",
        },
        "Build"
    );
    if (answer !== "Build") {
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
                result.stderr.trim() || "git review walkthrough build failed."
            );
            return;
        }
        void vscode.window.showInformationMessage("Walkthrough built.");
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
