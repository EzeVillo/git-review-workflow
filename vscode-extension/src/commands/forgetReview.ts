import * as vscode from "vscode";
import {InvokeOptions} from "../cli/invoke";
import {BranchRecord, sourceOf} from "../cli/porcelain";
import {MutationLock} from "../review/mutationLock";
import {HousekeepingKind, sourceFromReviewName} from "../review/housekeeping";
import {ReviewStateManager} from "../review/state";
import {captureToken} from "../review/staleGuard";
import {runHousekeeping} from "./runHousekeeping";

type ForgetPick = vscode.QuickPickItem & {action: HousekeepingKind};

/**
 * Discard desde inventario: forget --saved o clean según la fila (006).
 */
export async function discardInventoryReview(
    index: unknown,
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    if (typeof index !== "number") {
        return;
    }
    const review = stateManager.state.branches[index];
    if (!review) {
        return;
    }
    const source = sourceOf(review);
    const kind: HousekeepingKind =
        review.saved || review.name.startsWith("review-saved/")
            ? "forget-saved-one"
            : "clean-one";
    await runHousekeeping(
        "discardInventory",
        {kind, source},
        lock,
        stateManager,
        getInvokeOptions,
        captureToken(stateManager.state)
    );
}

export async function forgetReview(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const items: ForgetPick[] = [
        {label: "Discard one saved review…", action: "forget-saved-one"},
        {label: "Discard every saved review", action: "forget-saved-all"},
        {label: "Forget delta marker for one branch…", action: "forget-delta-one"},
        {label: "Forget every delta marker", action: "forget-delta-all"},
        {label: "Forget stale delta markers", action: "forget-delta-stale"},
    ];
    const pick = await vscode.window.showQuickPick(items, {
        title: "Forget review state",
        placeHolder: "What to discard",
    });
    if (!pick) {
        return;
    }

    if (
        pick.action === "forget-saved-all" ||
        pick.action === "forget-delta-all" ||
        pick.action === "forget-delta-stale"
    ) {
        await runHousekeeping("cleanReview", {kind: pick.action}, lock, stateManager, getInvokeOptions);
        return;
    }

    const source = await pickSource(
        stateManager.state.branches,
        pick.action === "forget-saved-one"
    );
    if (!source) {
        return;
    }
    await runHousekeeping("cleanReview", {kind: pick.action, source}, lock, stateManager, getInvokeOptions);
}

/**
 * La rama sale de la lista y solo de ahí. Un marcador --delta puede sobrevivir a
 * toda rama de review que lo hubiera nombrado, pero tipear ese nombre a ciegas
 * no es la salida: para los huérfanos están "Forget stale delta markers" —que es
 * exactamente los marcadores cuya rama ya no existe— y "Forget every delta
 * marker", que no piden nombrar nada. El QuickPick filtra incrementalmente, así
 * que escribir sigue llegando al ítem sin poder inventar uno.
 */
async function pickSource(
    branches: BranchRecord[],
    savedOnly: boolean
): Promise<string | undefined> {
    const filtered = branches.filter((r) => (savedOnly ? r.saved : true));
    const names = [...new Set(filtered.map((r) => sourceFromReviewName(r.name)))];
    if (names.length === 0) {
        void vscode.window.showErrorMessage(
            savedOnly
                ? "No saved reviews were found."
                : 'No reviews were found to name a delta marker. Use "Forget stale delta markers" for markers whose branch is gone.'
        );
        return undefined;
    }
    const chosen = await vscode.window.showQuickPick(
        names.map((name) => ({label: name})),
        {
            title: savedOnly ? "Saved review to discard" : "Branch for delta marker",
            placeHolder: "Source branch name",
        }
    );
    return chosen?.label;
}
