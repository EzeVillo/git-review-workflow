import * as vscode from "vscode";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {CandidateRemote} from "../cli/configPorcelain";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";

/** El nombre a mostrar en el `QuickPick`: el remoto, con marca si es el efectivo. */
function label(remote: CandidateRemote): string {
    return remote.current ? `${remote.name}  (current)` : remote.name;
}

/**
 * `gitReview.setRemote`: fija `reviewworkflow.remote` desde la lista de
 * `remote-candidate` (contracts/config-porcelain.md). Invocable desde el
 * setup (sin base) y desde Settings en el empty state configurado. El valor
 * que llega a la CLI es siempre el `name` de una fila tal cual, precedido por
 * `--` (mismo motivo que en `setBase`/`start`): nunca algo tipeado a mano.
 */
export async function setRemote(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions,
    remotes?: CandidateRemote[]
): Promise<void> {
    const list = remotes ?? stateManager.state.remotes ?? [];
    if (list.length === 0) {
        void vscode.window.showErrorMessage("No remotes to pick from were found.");
        return;
    }

    const items = [...list]
        .sort((a, b) => (a.current === b.current ? 0 : a.current ? -1 : 1))
        .map((remote) => ({label: label(remote), remote}));

    const picked = await vscode.window.showQuickPick(items, {
        title: "Set the remote",
        placeHolder: "Remote a full review fetches from",
    });
    if (!picked) {
        return;
    }

    await lock.run(async () => {
        const options = getInvokeOptions();
        const result = await invokeGitReview("config", ["remote", "--", picked.remote.name], options);
        await stateManager.refresh();
        if (result.exitCode !== 0) {
            const text = result.stderr.trim();
            void vscode.window.showErrorMessage(
                text.length > 0 ? text : "Could not save the setting."
            );
        }
    });
}
