import * as path from "node:path";
import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";

/**
 * `gitReview.walkthroughInit` / `walkthroughBuild` (006 US4).
 * No parsea el sidecar; init abre el archivo tras éxito.
 * Confirmación de --force **fuera** del lock (mismo molde que abort/save).
 */
export async function walkthroughInit(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const options = getInvokeOptions();

    const first = await lock.run(async () => {
        const result = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: "Initializing walkthrough…",
            },
            async () => invokeGitReview("walkthrough", ["init"], options)
        );
        if (result.exitCode === 0) {
            await openWalkthrough(options.cwd);
            await stateManager.refresh();
            return "ok" as const;
        }
        const err = result.stderr.trim() || result.stdout.trim();
        if (/already exists|pass --force/i.test(err)) {
            return "exists" as const;
        }
        void vscode.window.showErrorMessage(err.length > 0 ? err : "git review walkthrough init failed.");
        return "fail" as const;
    });

    if (first !== "exists") {
        return;
    }

    const answer = await vscode.window.showWarningMessage(
        "A walkthrough already exists. Overwrite it?",
        {
            modal: true,
            detail: "This runs git review walkthrough init --force and replaces .review/walkthrough.md.",
        },
        "Overwrite"
    );
    if (answer !== "Overwrite") {
        return;
    }

    await lock.run(async () => {
        const forced = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: "Overwriting walkthrough…",
            },
            async () => invokeGitReview("walkthrough", ["init", "--force"], getInvokeOptions())
        );
        await stateManager.refresh();
        if (forced && forced.exitCode !== 0) {
            void vscode.window.showErrorMessage(
                forced.stderr.trim() || "git review walkthrough init --force failed."
            );
            return;
        }
        await openWalkthrough(getInvokeOptions().cwd);
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
