import * as vscode from "vscode";
import {parseConfigPorcelain, CandidateBranch} from "../cli/configPorcelain";
import {invokeGitReview, InvokeOptions} from "../cli/invoke";
import {MutationLock} from "../review/mutationLock";
import {ReviewStateManager} from "../review/state";

type Layout = "auto" | "step" | "no-walk";

/**
 * `gitReview.compareReview`: monta `git review compare <a> <b> [--step|--no-walk]`
 * con confirmación (006 US3).
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

    const layoutPick = await vscode.window.showQuickPick(
        [
            {label: "Automatic", description: "walkthrough on the tip if present", layout: "auto" as Layout},
            {label: "Commit by commit", description: "--step", layout: "step" as Layout},
            {label: "Ignore the walkthrough", description: "--no-walk", layout: "no-walk" as Layout},
        ],
        {title: "How to read the comparison", placeHolder: "Reading layout"}
    );
    if (!layoutPick) {
        return;
    }

    const layoutNote =
        layoutPick.layout === "step"
            ? "commit by commit"
            : layoutPick.layout === "no-walk"
              ? "as the whole diff (no walkthrough)"
              : "automatically";
    const summary = `Compare ${lower}..${upper} ${layoutNote}? This creates a read-only review (finish will refuse).`;
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
    } else if (layoutPick.layout === "no-walk") {
        args.push("--no-walk");
    }
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
