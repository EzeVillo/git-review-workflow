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
        await runHousekeeping({kind: pick.action}, lock, stateManager, getInvokeOptions);
        return;
    }

    const source = await pickSource(
        stateManager.state.branches,
        pick.action === "forget-saved-one"
    );
    if (!source) {
        return;
    }
    await runHousekeeping({kind: pick.action, source}, lock, stateManager, getInvokeOptions);
}

async function pickSource(
    branches: BranchRecord[],
    savedOnly: boolean
): Promise<string | undefined> {
    const filtered = branches.filter((r) => (savedOnly ? r.saved : true));
    const names = [...new Set(filtered.map((r) => sourceFromReviewName(r.name)))];
    const fromList = names.map((name) => ({label: name}));
    if (fromList.length > 0) {
        const items: vscode.QuickPickItem[] = [...fromList, {label: "Enter a branch name…"}];
        const chosen = await vscode.window.showQuickPick(items, {
            title: savedOnly ? "Saved review to discard" : "Branch",
            placeHolder: "Source branch name",
        });
        if (!chosen) {
            return undefined;
        }
        if (chosen.label !== "Enter a branch name…") {
            return chosen.label;
        }
    }
    const typed = await vscode.window.showInputBox({
        title: savedOnly ? "Saved review to discard" : "Branch for delta marker",
        prompt: "Source branch name (e.g. feature/checkout)",
        validateInput: (v) => (v.trim() === "" ? "Required" : undefined),
    });
    return typed?.trim();
}
