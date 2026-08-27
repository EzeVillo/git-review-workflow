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
        description: "only entries marked key",
        layout: "keys",
    },
    {
        label: "Commit by commit",
        description: "one commit at a time",
        layout: "step",
    },
    {
        label: "Whole diff",
        description: "entire diff at once",
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
        {modal: true, detail: "Your working tree must be clean to start it."},
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
            const text = result.stderr.trim() || "Could not compare those two revisions.";
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

/**
 * El único picker que no se cierra sobre su lista: `compare` toma un commit-ish,
 * y un tag o un SHA son respuestas legítimas que ninguna lista de ramas trae. Lo
 * que sí cambia es dónde se escribe — en la caja del propio QuickPick, que
 * además filtra las candidatas, en vez de un ítem "Enter commit-ish…" que sacaba
 * a otro diálogo y perdía la lista de vista. Lo tipeado se ofrece como primera
 * fila mientras no coincida con una candidata, así que aceptar es siempre elegir
 * una fila y nunca adivinar si el texto contaba.
 */
async function pickCommitIsh(
    candidates: CandidateBranch[],
    title: string
): Promise<string | undefined> {
    if (candidates.length === 0) {
        return inputCommitIsh(title);
    }
    const branches: vscode.QuickPickItem[] = candidates.map((c) => ({
        label: c.name,
        description: c.origin + (c.current ? " · current" : ""),
    }));

    return await new Promise<string | undefined>((resolve) => {
        const quickPick = vscode.window.createQuickPick();
        quickPick.title = title;
        quickPick.placeholder = "Branch, tag or commit";
        quickPick.items = branches;
        quickPick.onDidChangeValue((value) => {
            const typed = value.trim();
            const known = typed === "" || branches.some((b) => b.label === typed);
            quickPick.items = known
                ? branches
                : [{label: typed, description: "use as typed"}, ...branches];
        });
        quickPick.onDidAccept(() => {
            const picked = quickPick.selectedItems[0]?.label ?? quickPick.value.trim();
            quickPick.hide();
            resolve(picked === "" ? undefined : picked);
        });
        // Cancelar (Esc, o el foco afuera) también pasa por acá; el resolve de
        // onDidAccept ya ganó la carrera, así que este solo cubre el descarte.
        quickPick.onDidHide(() => {
            quickPick.dispose();
            resolve(undefined);
        });
        quickPick.show();
    });
}

async function inputCommitIsh(title: string): Promise<string | undefined> {
    const typed = await vscode.window.showInputBox({
        title,
        prompt: "Branch, tag or commit",
        validateInput: (v) => (v.trim() === "" ? "Required" : undefined),
    });
    return typed?.trim();
}
