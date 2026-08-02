import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {GitApi} from "../review/repository";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";
import {openEntry} from "./openEntry";

export type NavigateDirection = "next" | "prev";

/**
 * `gitReview.next` / `gitReview.prev`: invoca el verbo de la CLI a través del
 * `MutationLock`, refresca con `status --porcelain` inmediatamente después
 * (nunca parsea la salida humana del verbo, FR-015), y abre el archivo de la
 * entrada resultante. Los límites de la secuencia se propagan tal cual desde
 * la CLI, sin comportamiento propio (FR-016).
 */
export async function navigate(
    direction: NavigateDirection,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions,
    gitApi: GitApi | undefined
): Promise<void> {
    await lock.run(async () => {
        const options = getInvokeOptions();
        const result = await invokeGitReview(direction, [], options);
        const state = await stateManager.refresh();

        if (result.exitCode !== 0) {
            if (result.stderr.trim().length > 0) {
                void vscode.window.showInformationMessage(result.stderr.trim());
            }
            return;
        }

        if (state.situation !== "review" || !state.state) {
            return;
        }
        const current = state.entries.find((e) => e.position === state.state?.position);
        if (current) {
            await openEntry(vscode.Uri.file(options.cwd), state.state.mode, current, gitApi);
        }
    });
}
