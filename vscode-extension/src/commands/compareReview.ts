import * as vscode from "vscode";
import {parseConfigPorcelain, CandidateBranch} from "../cli/configPorcelain";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {layoutSummary} from "../review/layoutOffers";
import {ReviewLayout} from "../review/reviewIntent";
import {ReviewStateManager} from "../review/state";

interface LayoutItem extends vscode.QuickPickItem {
    layout: ReviewLayout;
}

/**
 * Layouts de compare: mismos nombres honestos que start (sin Automatic).
 * Compare no tiene informe `offer` por tip de rama; se listan las cuatro
 * formas de la CLI y el rechazo de --keys / degradación de walk queda en la CLI.
 */
const LAYOUT_ITEMS: LayoutItem[] = [
    {
        label: "Walkthrough",
        description: "guided reading order if the upper tip has a walkthrough",
        layout: "walk",
    },
    {
        label: "Walkthrough — keys only",
        description: "only entries marked key (--keys)",
        layout: "keys",
    },
    {
        label: "Commit by commit",
        description: "one commit at a time (--step)",
        layout: "step",
    },
    {
        label: "Whole diff",
        description: "entire diff at once (--no-walk)",
        layout: "whole",
    },
];

/**
 * `gitReview.compareReview`: monta `git review compare <a> <b> [--step|--no-walk|--keys]`
 * con confirmación (006 US3). Sin layout "auto" / "Automatic".
 */
export async function compareReview(
    lock: MutationLock,
    stateManager: ReviewStateManager,
    getInvokeOptions: () => InvokeOptions
): Promise<void> {
    const candidates = await loadCandidates(stateManager, getInvokeOptions());
    const lower = await pickCommitIsh(candidates, "Compare: lower bound (from)");
    if (!lower) {
        return;
    }
    const upper = await pickCommitIsh(candidates, "Compare: upper bound (to)");
    if (!upper) {
        return;
    }

    const layoutPick = await vscode.window.showQuickPick(LAYOUT_ITEMS, {
        title: "How to read the comparison",
        placeHolder: "Walkthrough, keys only, commit by commit, or whole diff",
    });
    if (!layoutPick) {
        return;
    }

    const summary = `Compare ${lower}..${upper} ${layoutSummary(layoutPick.layout)}? This creates a read-only review (finish will refuse).`;
    const answer = await vscode.window.showWarningMessage(
        summary,
        {modal: true, detail: "Same effect as git review compare. Local changes must be clean."},
        "Compare"
    );
    if (answer !== "Compare") {
        return;
    }

    const args: string[] = [];
    if (layoutPick.layout === "step") {
        args.push("--step");
    } else if (layoutPick.layout === "whole") {
        args.push("--no-walk");
    } else if (layoutPick.layout === "keys") {
        args.push("--keys");
    }
    // walk: sin flag de layout (la CLI detecta walkthrough en el tip)
    // Separador -- antes de posicionales: commit-ish que empiezan con - no se
    // confunden con flags (misma disciplina que start).
    args.push("--", lower, upper);

    await lock.run(async () => {
        const result = await vscode.window.withProgress(
            {
                location: vscode.ProgressLocation.Notification,
                title: `Comparing ${lower}..${upper}…`,
            },
            async () => {
                const invocation = await invokeGitReview("compare", args, getInvokeOptions());
                await stateManager.refresh();
                return invocation;
            }
        );
        if (result && result.exitCode !== 0) {
            const text = result.stderr.trim() || "git review compare failed.";
            void vscode.window.showErrorMessage(text);
        }
    });
}

async function loadCandidates(
    stateManager: ReviewStateManager,
    options: InvokeOptions
): Promise<CandidateBranch[]> {
    const cached = stateManager.state.candidates;
    if (cached && cached.length > 0) {
        return cached;
    }
    const result = await invokeGitReview("config", ["--porcelain"], {...options, network: false});
    if (result.exitCode !== 0) {
        return [];
    }
    return parseConfigPorcelain(result.stdout).candidates;
}

async function pickCommitIsh(
    candidates: CandidateBranch[],
    title: string
): Promise<string | undefined> {
    const items: {label: string; description?: string; value?: string}[] = candidates.map((c) => ({
        label: c.name,
        description: c.origin + (c.current ? " · current" : ""),
        value: c.name,
    }));
    items.push({label: "Enter commit-ish…", value: "__input__"});

    if (candidates.length === 0) {
        return inputCommitIsh(title);
    }

    const picked = await vscode.window.showQuickPick(items, {title, placeHolder: "Branch, tag or commit"});
    if (!picked) {
        return undefined;
    }
    if (picked.value === "__input__" || picked.label === "Enter commit-ish…") {
        return inputCommitIsh(title);
    }
    return picked.value ?? picked.label;
}

async function inputCommitIsh(title: string): Promise<string | undefined> {
    const typed = await vscode.window.showInputBox({
        title,
        prompt: "Branch, tag or commit",
        validateInput: (v) => (v.trim() === "" ? "Required" : undefined),
    });
    return typed?.trim();
}
