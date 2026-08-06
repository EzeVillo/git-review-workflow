import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {
    argsForHousekeeping,
    confirmCopyFor,
    HousekeepingAction,
    housekeepingNeedsNetwork,
    verbForHousekeeping,
} from "../review/housekeeping";
import {ReviewStateManager} from "../review/state";
import {captureToken, StateToken, tokenStillValid} from "../review/staleGuard";

function flat(stderr: string): string {
    return stderr.split("\n").map((line) => line.trim()).filter((line) => line.length > 0).join(" ");
}

/**
 * Confirmación + invocación de clean/forget (006). Confirmación fuera del lock;
 * StateToken opcional cuando la acción nació de una fila del inventario.
 */
export async function runHousekeeping(
    action: HousekeepingAction,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions,
    token?: StateToken
): Promise<void> {
    const copy = confirmCopyFor(action);
    const answer = await vscode.window.showWarningMessage(
        copy.title,
        {modal: true, detail: copy.detail},
        copy.button
    );
    if (answer !== copy.button) {
        return;
    }

    const verb = verbForHousekeeping(action);
    const args = argsForHousekeeping(action);
    const network = housekeepingNeedsNetwork(action);
    const guard = token ?? captureToken(stateManager.state);

    await lock.run(async () => {
        let stale = false;
        const result = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: copy.title.replace(/\?$/, "…"),
            },
            async () => {
                if (!tokenStillValid(guard, stateManager.state)) {
                    stale = true;
                    return undefined;
                }
                const invocation = await invokeGitReview(verb, args, {
                    ...getInvokeOptions(),
                    network,
                });
                await stateManager.refresh();
                return invocation;
            }
        );

        if (stale) {
            void vscode.window.showInformationMessage(
                "The review state changed before the action ran; nothing was changed."
            );
            return;
        }

        if (result && result.exitCode !== 0) {
            const text = flat(result.stderr);
            void vscode.window.showErrorMessage(text.length > 0 ? text : `git review ${verb} failed.`);
        }
    });
}
